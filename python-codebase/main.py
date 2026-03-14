#!/usr/bin/env python3
"""
LEGO AI Sorting Machine — Main Controller
==========================================
Entry point that orchestrates all subsystems:
  - Conveyor belt (stepper motor with optional encoder)
  - Scanner (camera + motion detection, multi-angle support)
  - Classifier (Brickognize API with local cache)
  - Sorter (binary gate tree, multiple sort modes)
  - Inventory (SQLite + Rebrickable + analytics)
  - Web dashboard (Flask, OTA config, export)

Usage:
    python main.py                  # Run the full system
    python main.py --test-gates     # Test all servo gates
    python main.py --test-camera    # Test camera capture
    python main.py --test-classify  # Test classification on a photo
    python main.py --test-rescan    # Test rescan workflow on an image
    python main.py --web-only       # Start web dashboard without hardware
    python main.py --sort-mode color  # Start with color sorting
"""
import sys
import time
import signal
import threading
import argparse
import collections
from typing import Optional

import yaml

from conveyor import Conveyor
from scanner import Scanner
from classifier import Classifier
from sorter import Sorter
from inventory import Inventory
from web_ui import create_app
from logger import get_logger

log = get_logger("main")

# ── CENTRALIZED GPIO SETUP ────────────────────────────────
PI_GPIO = None
try:
    import RPi.GPIO as _GPIO
    _GPIO.setmode(_GPIO.BCM)
    PI_GPIO = _GPIO
except (ImportError, RuntimeError):
    pass


class RetryQueue:
    """Queue for bricks that failed API classification.

    Holds image + metadata for deferred re-classification when the
    API becomes available again. Max 20 entries to bound memory.
    """

    def __init__(self, max_size: int = 20) -> None:
        self.queue = collections.deque(maxlen=max_size)
        self._lock = threading.Lock()

    def add(self, image, metadata: dict) -> None:
        """Add a failed classification to the retry queue."""
        with self._lock:
            self.queue.append({"image": image, "metadata": metadata,
                               "added_at": time.time()})
            log.info(f"Retry queue: {len(self.queue)} pending")

    def get_all(self) -> list:
        """Drain and return all queued items."""
        with self._lock:
            items = list(self.queue)
            self.queue.clear()
            return items

    @property
    def size(self) -> int:
        """Number of items in the queue."""
        return len(self.queue)


class SortingMachine:
    """Main controller that orchestrates the sorting pipeline.

    Attributes:
        config: Loaded configuration dictionary.
        state: Current machine state string.
        sort_mode: Active sort mode (delegates to Sorter).
    """

    def __init__(self, config_path: str = "config.yaml") -> None:
        with open(config_path, "r") as f:
            self.config = yaml.safe_load(f)
        self._config_path = config_path

        log.info("=" * 60)
        log.info("  LEGO AI Sorting Machine v3")
        log.info("=" * 60)

        # Initialize all subsystems
        self.conveyor = Conveyor(self.config)
        self.scanner = Scanner(self.config)
        self.classifier = Classifier(self.config)
        self.sorter = Sorter(self.config)
        self.inventory = Inventory(self.config)

        # State management
        self.state: str = "idle"
        self._running: bool = False
        self._sort_thread: Optional[threading.Thread] = None

        # Rescan statistics
        self.rescan_attempts: int = 0
        self.rescan_successes: int = 0

        # Error recovery
        self._retry_queue = RetryQueue(max_size=20)
        self._retry_thread: Optional[threading.Thread] = None
        self._api_healthy: bool = True

        # Graceful shutdown
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

        # Power sequencing
        self._power_sequence()
        log.info(f"Bins: {self.sorter.num_bins}")
        log.info(f"Gate tree: {self.sorter.num_levels} levels, "
                 f"{self.sorter.num_gates} gates")
        log.info(f"Sort mode: {self.sorter.sort_mode}")
        log.info(f"API: {self.classifier.api_url}")

    @property
    def sort_mode(self) -> str:
        """Current sort mode (delegates to Sorter)."""
        return self.sorter.sort_mode

    def _power_sequence(self) -> None:
        """Enable servo power relay after hardware initialization."""
        servo_cfg = self.config.get("sorter", {})
        servo_power_pin = servo_cfg.get("servo_power_pin", 22)
        self._servo_power_pin: Optional[int] = None

        if PI_GPIO is None:
            log.info("Servo power sequencing: not on Raspberry Pi")
            return

        try:
            PI_GPIO.setup(servo_power_pin, PI_GPIO.OUT)
            PI_GPIO.output(servo_power_pin, PI_GPIO.HIGH)
            self._servo_power_pin = servo_power_pin
            log.info(f"Servo power enabled (GPIO {servo_power_pin})")
        except RuntimeError as e:
            log.error(f"Servo power sequencing failed: {e}")

    def start(self) -> None:
        """Start the sorting machine."""
        if self._running:
            return

        log.info("Starting sorting machine...")

        if not self.scanner.initialize():
            log.warning("Camera initialization failed")

        self._running = True
        self.state = "running"

        self.conveyor.start()

        # Start sorting loop
        self._sort_thread = threading.Thread(target=self._sorting_loop,
                                              daemon=True)
        self._sort_thread.start()

        # Start retry processor
        self._retry_thread = threading.Thread(target=self._retry_loop,
                                               daemon=True)
        self._retry_thread.start()

        log.info("Machine running — place bricks on the belt!")

    def stop(self) -> None:
        """Stop the sorting machine."""
        log.info("Stopping...")
        self._running = False
        self.state = "idle"
        self.conveyor.stop()
        if self._sort_thread:
            self._sort_thread.join(timeout=5)
        if self._retry_thread:
            self._retry_thread.join(timeout=3)
        log.info("Machine stopped")

    def _classify_with_rescan(self, initial_frame) -> tuple:
        """Classify a brick with automatic rescan on low confidence.

        Belt must be PAUSED when called. Belt remains PAUSED on return.

        Args:
            initial_frame: Primary camera frame (BGR numpy array).

        Returns:
            Tuple of (ClassificationResult, bin_number).
        """
        # Get secondary frame if available
        secondary = self.scanner.capture_secondary()

        # First classification attempt (with multi-angle)
        cropped = self.scanner.crop_brick(initial_frame)
        result = self.classifier.classify(cropped, secondary_image=secondary)

        if not result.is_confident and not result.needs_review:
            log.info("Low confidence — attempting re-scan...")
            self.rescan_attempts += 1

            try:
                self.conveyor.resume()
                time.sleep(0.05)
                self.conveyor.pause()
                time.sleep(0.15)

                frame_2 = self.scanner.capture_brick()
                if frame_2 is not None:
                    cropped_2 = self.scanner.crop_brick(frame_2)
                    secondary_2 = self.scanner.capture_secondary()
                    result_2 = self.classifier.classify(cropped_2,
                                                         secondary_image=secondary_2)

                    if result_2.is_confident or result_2.needs_review:
                        self.rescan_successes += 1
                        log.info("Rescan successful!")
                        result = result_2
                else:
                    log.warning("Rescan capture failed, using first result")
            except Exception as e:
                log.error(f"Rescan error: {e}", extra={"error": str(e)})
            finally:
                self.conveyor.pause()

        # Determine bin assignment based on sort mode
        if result.is_confident:
            bin_num = self.sorter.get_bin_for_part(
                result.category, color=result.color, part_id=result.part_id)
        elif result.needs_review:
            bin_num = self.classifier.review_bin
        else:
            bin_num = self.sorter.unknown_bin

        return result, bin_num

    def _sorting_loop(self) -> None:
        """Main sorting loop — runs in a background thread."""
        consecutive_errors = 0

        while self._running:
            try:
                if self.scanner.detect_motion():
                    self.state = "scanning"
                    log.info("Brick detected!")

                    self.conveyor.pause()
                    time.sleep(0.15)

                    frame = self.scanner.capture_brick()
                    if frame is None:
                        log.warning("Capture failed, resuming belt")
                        self.conveyor.resume()
                        self.state = "running"
                        continue

                    self.state = "classifying"
                    result, bin_num = self._classify_with_rescan(frame)

                    # If API is down, queue for retry
                    if (not result.is_confident and not result.needs_review
                            and not self._api_healthy):
                        self._retry_queue.add(frame, {"timestamp": time.time()})
                        bin_num = self.sorter.unknown_bin

                    self.state = "sorting"
                    self.sorter.route_to_bin(bin_num)

                    self.conveyor.resume()

                    self.inventory.log_part(
                        part_id=result.part_id,
                        part_name=result.part_name,
                        color=result.color,
                        category=result.category,
                        confidence=result.confidence,
                        bin_number=bin_num,
                        image_url=result.image_url,
                        needs_review=result.needs_review,
                        sort_mode=self.sorter.sort_mode,
                    )

                    self.state = "running"
                    stats = self.inventory.get_stats()
                    log.info(f"{result.part_name or 'Unknown'} -> Bin {bin_num} "
                             f"({stats['total_sorted']} total, "
                             f"{stats['parts_per_minute']}/min)",
                             extra={"part_id": result.part_id,
                                    "bin_number": bin_num,
                                    "confidence": result.confidence})

                    consecutive_errors = 0
                    self._api_healthy = True
                    time.sleep(0.3)

                else:
                    time.sleep(0.05)

            except Exception as e:
                consecutive_errors += 1
                log.error(f"Sorting loop error: {e}", extra={"error": str(e)})
                import traceback
                traceback.print_exc()
                self.conveyor.resume()
                self.state = "running"

                if consecutive_errors >= 3:
                    self._api_healthy = False
                    log.warning("Multiple errors — marking API unhealthy")

                time.sleep(1)

    def _retry_loop(self) -> None:
        """Background thread that retries failed classifications every 30s."""
        while self._running:
            time.sleep(30)

            if self._retry_queue.size == 0 or not self._api_healthy:
                continue

            items = self._retry_queue.get_all()
            log.info(f"Retrying {len(items)} queued classifications...")

            for item in items:
                try:
                    image = item["image"]
                    cropped = self.scanner.crop_brick(image)
                    result = self.classifier.classify(cropped)

                    if result.is_confident:
                        bin_num = self.sorter.get_bin_for_part(
                            result.category, color=result.color,
                            part_id=result.part_id)
                        self.inventory.log_part(
                            part_id=result.part_id,
                            part_name=result.part_name,
                            color=result.color,
                            category=result.category,
                            confidence=result.confidence,
                            bin_number=bin_num,
                            image_url=result.image_url,
                            sort_mode=self.sorter.sort_mode,
                        )
                        log.info(f"Retry succeeded: {result.part_name}")
                except Exception as e:
                    log.warning(f"Retry failed: {e}")
                    self._api_healthy = False
                    break

    def update_config(self, section: str, key: str, value) -> bool:
        """Update a configuration value at runtime and save to disk.

        Args:
            section: Top-level config section (e.g. 'belt', 'classifier').
            key: Configuration key within the section.
            value: New value to set.

        Returns:
            True if update was successful.
        """
        if section not in self.config:
            log.warning(f"Unknown config section: {section}")
            return False

        old_value = self.config[section].get(key)
        self.config[section][key] = value
        log.info(f"Config updated: {section}.{key} = {value} (was {old_value})")

        # Apply live changes
        if section == "belt" and key == "speed_mm_per_sec":
            self.conveyor.set_speed(float(value))
        elif section == "classifier" and key == "confidence_threshold":
            self.classifier.confidence_threshold = float(value)
        elif section == "classifier" and key == "review_threshold":
            self.classifier.review_threshold = float(value)
        elif section == "scanner" and key == "led_brightness":
            try:
                if self.scanner._led_pwm:
                    self.scanner._led_pwm.ChangeDutyCycle(int(value))
            except Exception:
                pass

        # Save to disk
        try:
            with open(self._config_path, 'w') as f:
                yaml.dump(self.config, f, default_flow_style=False,
                          sort_keys=False)
            return True
        except Exception as e:
            log.error(f"Failed to save config: {e}")
            return False

    def _signal_handler(self, signum, frame) -> None:
        """Handle Ctrl+C gracefully."""
        log.info("Shutdown signal received...")
        self.shutdown()
        sys.exit(0)

    def shutdown(self) -> None:
        """Clean shutdown of all subsystems."""
        self.stop()

        if self._servo_power_pin is not None and PI_GPIO is not None:
            try:
                PI_GPIO.output(self._servo_power_pin, PI_GPIO.LOW)
            except RuntimeError:
                pass

        self.scanner.cleanup()
        self.conveyor.cleanup()
        self.sorter.cleanup()
        self.inventory.cleanup()

        if PI_GPIO is not None:
            try:
                PI_GPIO.cleanup()
            except RuntimeError:
                pass

        log.info("All subsystems shut down cleanly")

    def run_web_dashboard(self) -> None:
        """Start the Flask web dashboard."""
        web_cfg = self.config.get("web", {})
        app = create_app(self)
        log.info(f"Web dashboard: http://0.0.0.0:{web_cfg.get('port', 5000)}")
        log.info("Open in browser on any device on your network")
        app.run(
            host=web_cfg.get("host", "0.0.0.0"),
            port=web_cfg.get("port", 5000),
            debug=web_cfg.get("debug", False),
            use_reloader=False,
        )


# ── CLI ENTRY POINT ─────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="LEGO AI Sorting Machine")
    parser.add_argument("--config", default="config.yaml",
                       help="Path to config file")
    parser.add_argument("--test-gates", action="store_true",
                       help="Test all servo gates")
    parser.add_argument("--test-camera", action="store_true",
                       help="Test camera capture")
    parser.add_argument("--test-classify", metavar="IMAGE",
                       help="Test classification on an image file")
    parser.add_argument("--test-rescan", metavar="IMAGE",
                       help="Test rescan workflow (classifies twice)")
    parser.add_argument("--web-only", action="store_true",
                       help="Start web dashboard without hardware")
    parser.add_argument("--sort-mode",
                       choices=["part", "color", "category", "set"],
                       help="Set the sort mode")
    args = parser.parse_args()

    machine = SortingMachine(args.config)

    if args.sort_mode:
        machine.sorter.set_sort_mode(args.sort_mode)

    if args.test_gates:
        log.info("Testing all servo gates...")
        machine.sorter.test_all_gates()
        for i in range(machine.sorter.num_bins):
            log.info(f"  Testing bin {i}...")
            machine.sorter.test_bin(i)
            time.sleep(0.5)
        log.info("Gate test complete!")
        machine.shutdown()

    elif args.test_camera:
        log.info("Testing camera...")
        machine.scanner.initialize()
        frame = machine.scanner.capture_brick()
        if frame is not None:
            try:
                import cv2
                cv2.imwrite("test_capture.jpg", frame)
                log.info("Saved test_capture.jpg")
            except ImportError:
                log.info(f"Captured frame: {frame.shape}")
        if machine.scanner.has_secondary:
            sec = machine.scanner.capture_secondary()
            if sec is not None:
                try:
                    import cv2
                    cv2.imwrite("test_secondary.jpg", sec)
                    log.info("Saved test_secondary.jpg")
                except ImportError:
                    log.info(f"Secondary frame: {sec.shape}")
        machine.shutdown()

    elif args.test_classify:
        log.info(f"Testing classification on {args.test_classify}...")
        try:
            import cv2
            image = cv2.imread(args.test_classify)
            if image is not None:
                result = machine.classifier.classify(image)
                log.info(f"Result: {result}")
                log.info(f"Category: {result.category}")
                log.info(f"Bin (part): "
                         f"{machine.sorter.get_bin_for_part(result.category)}")
                log.info(f"Bin (color): "
                         f"{machine.sorter.get_bin_for_part(result.category, color=result.color)}")
                if result.needs_review:
                    log.info("** This part needs manual review **")
                if result.alternatives:
                    log.info("Alternatives:")
                    for alt in result.alternatives:
                        log.info(f"  - {alt['part_name']} "
                                 f"({alt['confidence']:.2f})")
            else:
                log.error(f"Could not read image: {args.test_classify}")
        except ImportError:
            log.error("OpenCV required for image classification test")
        machine.shutdown()

    elif args.test_rescan:
        log.info(f"Testing rescan workflow on {args.test_rescan}...")
        try:
            import cv2
            image = cv2.imread(args.test_rescan)
            if image is not None:
                log.info("First classification attempt:")
                cropped_1 = machine.scanner.crop_brick(image)
                result_1 = machine.classifier.classify(cropped_1)
                log.info(f"  Part: {result_1.part_name or 'Unknown'}")
                log.info(f"  Confidence: {result_1.confidence:.4f}")
                log.info(f"  Needs review: {result_1.needs_review}")

                log.info("Second classification attempt:")
                result_2 = machine.classifier.classify(cropped_1)
                log.info(f"  Part: {result_2.part_name or 'Unknown'}")
                log.info(f"  Confidence: {result_2.confidence:.4f}")

                if result_1.is_confident:
                    log.info(f"First succeeded: {result_1.part_name}")
                elif result_2.is_confident:
                    log.info(f"Second succeeded: {result_2.part_name}")
                else:
                    log.info("Both failed — would route to unknown bin")
            else:
                log.error(f"Could not read image: {args.test_rescan}")
        except ImportError:
            log.error("OpenCV required for rescan test")
        machine.shutdown()

    elif args.web_only:
        log.info("Starting web dashboard (no hardware)...")
        machine.run_web_dashboard()

    else:
        machine.start()
        for set_num in machine.inventory.target_sets:
            machine.inventory.load_set(set_num)
        machine.run_web_dashboard()


if __name__ == "__main__":
    main()
