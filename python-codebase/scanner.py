"""
LEGO AI Sorting Machine — Scanner (Camera + Motion Detection)
Captures images from the Pi Camera Module 3 and detects when
a brick enters the scanning chamber. Supports optional second
camera for multi-angle classification.
"""
import time
from typing import Optional, List, Tuple

import numpy as np

from logger import get_logger

log = get_logger("scanner")

try:
    import cv2
    CV2_AVAILABLE = True
except ImportError:
    CV2_AVAILABLE = False
    log.info("OpenCV not available — running in simulation mode")


class Scanner:
    """Camera and motion detection subsystem.

    Supports a primary top-down camera and an optional secondary side-view
    camera for multi-angle classification. The second camera is configured
    in config.yaml under scanner.secondary_camera.

    Attributes:
        resolution: Primary camera resolution (width, height).
        has_secondary: True if secondary camera is configured and active.
    """

    def __init__(self, config: dict) -> None:
        cfg = config["scanner"]
        self.camera_index: int = cfg["camera_index"]
        self.resolution: Tuple[int, int] = tuple(cfg["resolution"])
        self.capture_frames: int = cfg["capture_frames"]
        self.motion_threshold: int = cfg["motion_threshold"]
        self.motion_roi: Tuple[int, int, int, int] = tuple(cfg["motion_roi"])
        self.warmup_frames: int = cfg["warmup_frames"]
        self.led_pin: int = cfg["led_pin"]
        self.led_brightness: int = cfg["led_brightness"]

        # Secondary camera configuration
        sec_cfg = cfg.get("secondary_camera", {})
        self.secondary_enabled: bool = sec_cfg.get("enabled", False)
        self.secondary_index: int = sec_cfg.get("camera_index", 1)
        self.secondary_resolution: Tuple[int, int] = tuple(
            sec_cfg.get("resolution", [1280, 720])
        )

        self._cap: Optional[object] = None
        self._cap_secondary: Optional[object] = None
        self._bg_frame: Optional[np.ndarray] = None
        self._initialized: bool = False
        self._led_pwm: Optional[object] = None

        log.info(f"Config: {self.resolution[0]}x{self.resolution[1]}, "
                 f"motion_threshold={self.motion_threshold}"
                 f"{', secondary camera enabled' if self.secondary_enabled else ''}")

    @property
    def has_secondary(self) -> bool:
        """True if a secondary camera is active."""
        return self._cap_secondary is not None

    def initialize(self) -> bool:
        """Open camera(s) and warm up auto-exposure.

        Returns:
            True if primary camera initialized successfully.
        """
        if not CV2_AVAILABLE:
            log.info("Simulation mode — no camera")
            self._initialized = True
            return True

        self._cap = cv2.VideoCapture(self.camera_index)
        if not self._cap.isOpened():
            log.error("Could not open primary camera")
            return False

        self._cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.resolution[0])
        self._cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.resolution[1])

        # Warm up auto-exposure
        log.info(f"Warming up primary camera ({self.warmup_frames} frames)...")
        for _ in range(self.warmup_frames):
            self._cap.read()
            time.sleep(0.03)

        # Capture background reference (empty belt)
        ret, self._bg_frame = self._cap.read()
        if ret:
            self._bg_frame = cv2.cvtColor(self._bg_frame, cv2.COLOR_BGR2GRAY)
            self._bg_frame = cv2.GaussianBlur(self._bg_frame, (21, 21), 0)

        # Initialize secondary camera
        if self.secondary_enabled:
            self._init_secondary_camera()

        self._setup_leds()
        self._initialized = True
        log.info("Camera initialized")
        return True

    def _init_secondary_camera(self) -> None:
        """Initialize the optional secondary (side-view) camera."""
        if not CV2_AVAILABLE:
            return
        try:
            self._cap_secondary = cv2.VideoCapture(self.secondary_index)
            if not self._cap_secondary.isOpened():
                log.warning("Secondary camera not found — disabling")
                self._cap_secondary = None
                return
            self._cap_secondary.set(cv2.CAP_PROP_FRAME_WIDTH,
                                     self.secondary_resolution[0])
            self._cap_secondary.set(cv2.CAP_PROP_FRAME_HEIGHT,
                                     self.secondary_resolution[1])
            # Warm up
            for _ in range(15):
                self._cap_secondary.read()
                time.sleep(0.03)
            log.info(f"Secondary camera initialized: "
                     f"{self.secondary_resolution[0]}x{self.secondary_resolution[1]}")
        except Exception as e:
            log.warning(f"Secondary camera setup failed: {e}")
            self._cap_secondary = None

    def _setup_leds(self) -> None:
        """Initialize LED strip brightness via PWM.

        NOTE: GPIO.setmode(BCM) is called once by main.py at import time.
        """
        try:
            import RPi.GPIO as GPIO
            GPIO.setup(self.led_pin, GPIO.OUT)
            self._led_pwm = GPIO.PWM(self.led_pin, 1000)
            self._led_pwm.start(self.led_brightness)
            log.info(f"LEDs set to {self.led_brightness}%")
        except (ImportError, Exception) as e:
            log.debug(f"LED setup skipped: {e}")

    def detect_motion(self) -> bool:
        """Check if a brick is present in the scanning chamber.

        Uses frame differencing against the background reference.

        Returns:
            True if motion/object is detected in the ROI.
        """
        if not CV2_AVAILABLE or self._cap is None:
            return False

        ret, frame = self._cap.read()
        if not ret:
            return False

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (21, 21), 0)

        # Crop to region of interest (with bounds checking)
        x1, y1, x2, y2 = self.motion_roi
        h, w = gray.shape[:2]
        x1 = max(0, min(x1, w - 1))
        y1 = max(0, min(y1, h - 1))
        x2 = max(x1 + 1, min(x2, w))
        y2 = max(y1 + 1, min(y2, h))
        roi_current = gray[y1:y2, x1:x2]
        roi_bg = self._bg_frame[y1:y2, x1:x2]

        # Frame difference
        diff = cv2.absdiff(roi_bg, roi_current)
        _, thresh = cv2.threshold(diff, 30, 255, cv2.THRESH_BINARY)

        motion_pixels = cv2.countNonZero(thresh)
        return motion_pixels > self.motion_threshold

    def capture_brick(self) -> Optional[np.ndarray]:
        """Capture multiple frames and return the sharpest one.

        Call this after motion is detected and belt is paused.

        Returns:
            Best image as a BGR numpy array, or None on failure.
        """
        if not CV2_AVAILABLE or self._cap is None:
            log.debug("Simulation: returning dummy image")
            return np.zeros((480, 640, 3), dtype=np.uint8)

        time.sleep(0.1)  # Let vibrations settle

        frames: List[np.ndarray] = []
        for _ in range(self.capture_frames):
            ret, frame = self._cap.read()
            if ret:
                frames.append(frame)
            time.sleep(0.05)

        if not frames:
            log.error("No frames captured")
            return None

        # Select sharpest frame (highest Laplacian variance)
        best_frame = None
        best_sharpness = -1.0
        for frame in frames:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            sharpness = cv2.Laplacian(gray, cv2.CV_64F).var()
            if sharpness > best_sharpness:
                best_sharpness = sharpness
                best_frame = frame

        log.info(f"Captured {len(frames)} frames, best sharpness={best_sharpness:.1f}")
        return best_frame

    def capture_secondary(self) -> Optional[np.ndarray]:
        """Capture a frame from the secondary (side-view) camera.

        Returns:
            BGR numpy array from secondary camera, or None if unavailable.
        """
        if self._cap_secondary is None:
            return None
        if not CV2_AVAILABLE:
            return np.zeros((720, 1280, 3), dtype=np.uint8)
        ret, frame = self._cap_secondary.read()
        if ret:
            log.debug("Secondary camera frame captured")
            return frame
        log.warning("Secondary camera capture failed")
        return None

    def capture_multi_angle(self) -> List[np.ndarray]:
        """Capture frames from all available cameras.

        Returns:
            List of BGR numpy arrays (primary first, then secondary if available).
        """
        frames = []
        primary = self.capture_brick()
        if primary is not None:
            frames.append(primary)
        secondary = self.capture_secondary()
        if secondary is not None:
            frames.append(secondary)
        return frames

    def crop_brick(self, frame: np.ndarray) -> np.ndarray:
        """Crop the frame to the brick region using background subtraction.

        Args:
            frame: Full camera frame (BGR).

        Returns:
            Cropped image focused on the brick.
        """
        if not CV2_AVAILABLE:
            return frame

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (11, 11), 0)

        if self._bg_frame is not None:
            bg_resized = cv2.resize(self._bg_frame,
                                     (blurred.shape[1], blurred.shape[0]))
            diff = cv2.absdiff(bg_resized, blurred)
        else:
            _, diff = cv2.threshold(blurred, 200, 255, cv2.THRESH_BINARY_INV)

        _, mask = cv2.threshold(diff, 25, 255, cv2.THRESH_BINARY)

        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL,
                                        cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            log.debug("No brick contour found, returning full ROI")
            x1, y1, x2, y2 = self.motion_roi
            return frame[y1:y2, x1:x2]

        largest = max(contours, key=cv2.contourArea)
        x, y, w, h = cv2.boundingRect(largest)

        pad = 20
        x1 = max(0, x - pad)
        y1 = max(0, y - pad)
        x2 = min(frame.shape[1], x + w + pad)
        y2 = min(frame.shape[0], y + h + pad)

        cropped = frame[y1:y2, x1:x2]
        log.debug(f"Cropped brick: {cropped.shape[1]}x{cropped.shape[0]}px")
        return cropped

    def update_background(self) -> None:
        """Re-capture background reference (call with empty belt)."""
        if not CV2_AVAILABLE or self._cap is None:
            return
        ret, frame = self._cap.read()
        if ret:
            self._bg_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            self._bg_frame = cv2.GaussianBlur(self._bg_frame, (21, 21), 0)
            log.info("Background updated")

    def get_frame_jpeg(self) -> bytes:
        """Get current primary camera frame as JPEG bytes (for web dashboard).

        Returns:
            JPEG-encoded bytes, or empty bytes if no camera.
        """
        if not CV2_AVAILABLE or self._cap is None:
            return b""
        ret, frame = self._cap.read()
        if not ret:
            return b""
        _, jpeg = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 75])
        return jpeg.tobytes()

    def get_secondary_jpeg(self) -> bytes:
        """Get current secondary camera frame as JPEG bytes.

        Returns:
            JPEG-encoded bytes, or empty bytes if no secondary camera.
        """
        if self._cap_secondary is None:
            return b""
        if not CV2_AVAILABLE:
            return b""
        ret, frame = self._cap_secondary.read()
        if not ret:
            return b""
        _, jpeg = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 75])
        return jpeg.tobytes()

    def cleanup(self) -> None:
        """Release camera resources."""
        if self._cap:
            self._cap.release()
        if self._cap_secondary:
            self._cap_secondary.release()
        if self._led_pwm:
            try:
                self._led_pwm.stop()
            except Exception:
                pass
        log.info("Cleaned up")
