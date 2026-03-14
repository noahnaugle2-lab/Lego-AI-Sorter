"""
LEGO AI Sorting Machine — Conveyor Belt Controller
Controls the NEMA 17 stepper motor via TMC2209 driver.
Supports optional rotary encoder for closed-loop speed control.
"""
import time
import threading
from typing import Optional

from logger import get_logger

log = get_logger("conveyor")

try:
    import RPi.GPIO as GPIO
    PI_AVAILABLE = True
except ImportError:
    PI_AVAILABLE = False
    log.info("RPi.GPIO not available — running in simulation mode")


class Conveyor:
    """Belt motor controller with optional encoder feedback.

    Attributes:
        speed: Current belt speed in mm/s.
        is_running: True if belt is actively stepping.
        actual_rpm: Measured RPM from encoder (0 if no encoder).
    """

    def __init__(self, config: dict) -> None:
        belt_cfg = config["belt"]
        self.step_pin: int = belt_cfg["step_pin"]
        self.dir_pin: int = belt_cfg["dir_pin"]
        self.enable_pin: int = belt_cfg["enable_pin"]
        self.speed: float = belt_cfg["speed_mm_per_sec"]
        self.steps_per_mm: float = belt_cfg["steps_per_mm"]
        self.pause_delay: float = belt_cfg["pause_after_classify_ms"] / 1000.0

        # Encoder configuration (optional)
        encoder_cfg = belt_cfg.get("encoder", {})
        self.encoder_enabled: bool = encoder_cfg.get("enabled", False)
        self.encoder_pin_a: int = encoder_cfg.get("pin_a", 23)
        self.encoder_pin_b: int = encoder_cfg.get("pin_b", 24)
        self.encoder_ppr: int = encoder_cfg.get("pulses_per_rev", 600)
        self.roller_circumference_mm: float = encoder_cfg.get("roller_circumference_mm", 75.4)

        self._running: bool = False
        self._paused: bool = False
        self._thread: Optional[threading.Thread] = None
        self._lock = threading.Lock()
        self._step_delay: float = 1.0 / (self.speed * self.steps_per_mm * 2)

        # Encoder state
        self._encoder_count: int = 0
        self._encoder_last_time: float = time.time()
        self._actual_rpm: float = 0.0
        self._target_step_delay: float = self._step_delay
        self._speed_correction: float = 1.0

        if PI_AVAILABLE:
            # NOTE: GPIO.setmode(BCM) is called once by main.py at import time.
            GPIO.setup(self.step_pin, GPIO.OUT)
            GPIO.setup(self.dir_pin, GPIO.OUT)
            GPIO.setup(self.enable_pin, GPIO.OUT)
            GPIO.output(self.dir_pin, GPIO.HIGH)   # Forward direction
            GPIO.output(self.enable_pin, GPIO.HIGH)  # Disabled initially

            if self.encoder_enabled:
                self._setup_encoder()

        log.info(f"Initialized: {self.speed} mm/s, step_delay={self._step_delay*1000:.1f}ms"
                 f"{', encoder enabled' if self.encoder_enabled else ''}")

    def _setup_encoder(self) -> None:
        """Configure rotary encoder GPIO pins with interrupt callbacks."""
        if not PI_AVAILABLE:
            return
        try:
            GPIO.setup(self.encoder_pin_a, GPIO.IN, pull_up_down=GPIO.PUD_UP)
            GPIO.setup(self.encoder_pin_b, GPIO.IN, pull_up_down=GPIO.PUD_UP)
            GPIO.add_event_detect(
                self.encoder_pin_a, GPIO.RISING,
                callback=self._encoder_callback, bouncetime=1
            )
            log.info(f"Encoder configured: pins A={self.encoder_pin_a}, "
                     f"B={self.encoder_pin_b}, PPR={self.encoder_ppr}")
        except Exception as e:
            log.warning(f"Encoder setup failed: {e}")
            self.encoder_enabled = False

    def _encoder_callback(self, channel: int) -> None:
        """ISR for encoder pulse — counts rising edges on channel A."""
        self._encoder_count += 1

    def _update_encoder_speed(self) -> None:
        """Calculate actual RPM from encoder pulses and adjust step delay.

        Called periodically from the step loop. Implements a simple
        proportional correction: if measured speed is too slow, decrease
        step delay (speed up); if too fast, increase delay (slow down).
        """
        now = time.time()
        elapsed = now - self._encoder_last_time
        if elapsed < 0.25:  # Update every 250ms
            return

        count = self._encoder_count
        self._encoder_count = 0
        self._encoder_last_time = now

        # Calculate actual RPM
        revs = count / self.encoder_ppr
        self._actual_rpm = (revs / elapsed) * 60.0

        # Calculate actual mm/s from RPM
        actual_mm_per_sec = (self._actual_rpm / 60.0) * self.roller_circumference_mm

        if actual_mm_per_sec > 0 and self.speed > 0:
            # Proportional correction (Kp=0.3 for gentle adjustment)
            error_ratio = self.speed / actual_mm_per_sec
            self._speed_correction = 1.0 + 0.3 * (error_ratio - 1.0)
            self._speed_correction = max(0.5, min(2.0, self._speed_correction))
            self._step_delay = self._target_step_delay / self._speed_correction

            log.debug(f"Encoder: {actual_mm_per_sec:.1f} mm/s actual, "
                      f"target {self.speed:.1f}, correction {self._speed_correction:.3f}",
                      extra={"encoder_rpm": round(self._actual_rpm, 1)})

    @property
    def actual_rpm(self) -> float:
        """Measured belt RPM from encoder (0 if encoder not enabled)."""
        return self._actual_rpm if self.encoder_enabled else 0.0

    def start(self) -> None:
        """Start the belt moving."""
        if self._running:
            return
        self._running = True
        self._paused = False
        if PI_AVAILABLE:
            GPIO.output(self.enable_pin, GPIO.LOW)  # Enable driver
        self._thread = threading.Thread(target=self._run_loop, daemon=True)
        self._thread.start()
        log.info("Belt started")

    def stop(self) -> None:
        """Stop the belt completely."""
        self._running = False
        if self._thread:
            self._thread.join(timeout=2)
        if PI_AVAILABLE:
            GPIO.output(self.enable_pin, GPIO.HIGH)  # Disable driver
        log.info("Belt stopped")

    def pause(self) -> None:
        """Pause the belt (for scanning)."""
        with self._lock:
            self._paused = True
        log.info("Belt paused")

    def resume(self) -> None:
        """Resume belt after scanning."""
        time.sleep(self.pause_delay)
        with self._lock:
            self._paused = False
        log.info("Belt resumed")

    def set_speed(self, mm_per_sec: float) -> None:
        """Change belt speed dynamically.

        Args:
            mm_per_sec: New belt speed in mm/s (clamped 5-100).
        """
        mm_per_sec = max(5.0, min(100.0, mm_per_sec))
        self.speed = mm_per_sec
        self._target_step_delay = 1.0 / (self.speed * self.steps_per_mm * 2)
        self._step_delay = self._target_step_delay
        self._speed_correction = 1.0
        log.info(f"Speed changed to {mm_per_sec} mm/s", extra={"speed": mm_per_sec})

    @property
    def is_running(self) -> bool:
        """True if belt is actively moving (started and not paused)."""
        return self._running and not self._paused

    def _run_loop(self) -> None:
        """Stepper pulse generation loop with optional encoder feedback."""
        loop_count = 0
        while self._running:
            with self._lock:
                if self._paused:
                    time.sleep(0.01)
                    continue

            if PI_AVAILABLE:
                GPIO.output(self.step_pin, GPIO.HIGH)
                time.sleep(self._step_delay)
                GPIO.output(self.step_pin, GPIO.LOW)
                time.sleep(self._step_delay)
            else:
                time.sleep(self._step_delay * 2)

            # Update encoder feedback periodically
            if self.encoder_enabled:
                loop_count += 1
                if loop_count % 50 == 0:
                    self._update_encoder_speed()

    def cleanup(self) -> None:
        """Stop belt motor. GPIO.cleanup() is handled centrally by main.py."""
        self.stop()
        if PI_AVAILABLE:
            GPIO.output(self.enable_pin, GPIO.HIGH)  # Disable driver
            if self.encoder_enabled:
                try:
                    GPIO.remove_event_detect(self.encoder_pin_a)
                except Exception:
                    pass
        log.info("Cleaned up")
