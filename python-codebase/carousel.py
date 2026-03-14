"""
carousel.py — Carousel Feeder Controller
=========================================

Controls the 4-platform rotating carousel that replaces the linear
conveyor belt in the v4 Hybrid design.

Pipeline positions (each 90° rotation advances all by one stage):
    Position 0 (LOAD)     — step feeder deposits one brick
    Position 1 (IMAGE)    — camera captures, AI classifies
    Position 2 (DISPENSE) — platform tilts, brick drops to stack
    Position 3 (CLEAR)    — platform returns flat, ready to load

Hardware:
    Central rotation : NEMA 17 stepper + TMC2209 (same GPIO as old belt)
    Platform tilt    : 4× SG90 servos on PCA9685 channels 0–3
    Home sensor      : Optical end-stop on channel 4 (GPIO input)

Usage:
    carousel = CarouselFeeder(config)
    carousel.home()           # find position 0
    carousel.advance()        # rotate 90°, advance pipeline
    carousel.dispense()       # tilt current dispense platform
    brick_ready = carousel.wait_for_load()  # True when pos-0 is loaded
"""

from __future__ import annotations

import time
import logging
import threading
from typing import Optional

try:
    import RPi.GPIO as GPIO
    from adafruit_pca9685 import PCA9685
    import board
    import busio
    HW_AVAILABLE = True
except ImportError:
    HW_AVAILABLE = False  # running off-pi (simulation / tests)

logger = logging.getLogger(__name__)

# ── Platform positions (indices into 4-platform ring) ──────
POS_LOAD     = 0
POS_IMAGE    = 1
POS_DISPENSE = 2
POS_CLEAR    = 3

# ── Servo pulse widths (µs) for SG90 ───────────────────────
_FLAT_PW    = 1500   # platform horizontal (90°)
_TILT_PW    = 2100   # platform tilted ~45° for dispense (150°)
_RETURN_PW  = _FLAT_PW

_SERVO_FREQ = 50          # Hz (standard SG90 frequency)
_PW_TO_DC   = lambda pw, freq=_SERVO_FREQ: int(pw / (1_000_000 / freq) * 0xFFFF)


class _SimBus:
    """Null hardware bus used when running off-Pi."""
    def write_byte_data(self, *a, **k): pass
    def read_byte_data(self, *a, **k): return 0


class CarouselFeeder:
    """4-platform carousel feeder controller."""

    # One full carousel rotation = 200 steps × 4 microsteps × gear_ratio
    STEPS_PER_REV   = 200        # NEMA 17 full-step count
    MICROSTEPS      = 4          # TMC2209 microstepping
    GEAR_RATIO      = 4.0        # carousel shaft to motor shaft (worm)
    STEPS_PER_90    = int(STEPS_PER_REV * MICROSTEPS * GEAR_RATIO / 4)

    STEP_DELAY_S    = 0.0008     # inter-step delay (~60 rpm at 4× microstep)

    # GPIO (same pins as belt stepper in conveyor.py, reused)
    PIN_STEP   = 17
    PIN_DIR    = 18
    PIN_ENABLE = 27
    PIN_HOME   = 22   # optical end-stop: LOW = at home

    # PCA9685 channels 0–3 = platform tilt servos
    SERVO_CHANNELS = [0, 1, 2, 3]

    def __init__(self, config: dict):
        self._cfg = config
        self._lock = threading.Lock()
        self._position = 0      # current carousel position (0–3)
        self._tilt_state = [False] * 4  # is each platform tilted?

        if HW_AVAILABLE:
            GPIO.setmode(GPIO.BCM)
            GPIO.setup(self.PIN_STEP,   GPIO.OUT, initial=GPIO.LOW)
            GPIO.setup(self.PIN_DIR,    GPIO.OUT, initial=GPIO.LOW)
            GPIO.setup(self.PIN_ENABLE, GPIO.OUT, initial=GPIO.HIGH)  # disabled
            GPIO.setup(self.PIN_HOME,   GPIO.IN,  pull_up_down=GPIO.PUD_UP)

            i2c = busio.I2C(board.SCL, board.SDA)
            pca_addr = config.get("pca9685_address", 0x40)
            self._pca = PCA9685(i2c, address=pca_addr)
            self._pca.frequency = _SERVO_FREQ
        else:
            self._pca = None
            logger.warning("Hardware not available — CarouselFeeder running in simulation mode")

        logger.info("CarouselFeeder initialised (steps/90°=%d)", self.STEPS_PER_90)

    # ── Enable / disable stepper ──────────────────────────────

    def _enable(self):
        if HW_AVAILABLE:
            GPIO.output(self.PIN_ENABLE, GPIO.LOW)

    def _disable(self):
        if HW_AVAILABLE:
            GPIO.output(self.PIN_ENABLE, GPIO.HIGH)

    # ── Stepper motion ────────────────────────────────────────

    def _step(self, n: int, direction: int = 1):
        """Drive n steps. direction=1 forward, -1 reverse."""
        if not HW_AVAILABLE:
            return
        GPIO.output(self.PIN_DIR, GPIO.HIGH if direction > 0 else GPIO.LOW)
        self._enable()
        for _ in range(abs(n)):
            GPIO.output(self.PIN_STEP, GPIO.HIGH)
            time.sleep(self.STEP_DELAY_S / 2)
            GPIO.output(self.PIN_STEP, GPIO.LOW)
            time.sleep(self.STEP_DELAY_S / 2)
        self._disable()

    # ── Servo control ─────────────────────────────────────────

    def _set_servo(self, channel: int, pulse_width_us: int):
        if self._pca is None:
            return
        dc = _PW_TO_DC(pulse_width_us)
        self._pca.channels[channel].duty_cycle = dc

    def _platform_flat(self, platform_idx: int):
        ch = self.SERVO_CHANNELS[platform_idx]
        self._set_servo(ch, _FLAT_PW)
        self._tilt_state[platform_idx] = False

    def _platform_tilt(self, platform_idx: int):
        ch = self.SERVO_CHANNELS[platform_idx]
        self._set_servo(ch, _TILT_PW)
        self._tilt_state[platform_idx] = True

    # ── Public API ────────────────────────────────────────────

    def home(self):
        """
        Rotate until the optical home sensor triggers, then set
        position = 0 (LOAD position).  Raises RuntimeError if
        home is not found within two full rotations.
        """
        logger.info("Homing carousel …")
        if not HW_AVAILABLE:
            self._position = 0
            logger.info("Simulation: homed to position 0")
            return

        max_steps = self.STEPS_PER_90 * 8   # 2 full revolutions
        GPIO.output(self.PIN_DIR, GPIO.HIGH)
        self._enable()
        for i in range(max_steps):
            if GPIO.input(self.PIN_HOME) == GPIO.LOW:
                self._disable()
                self._position = 0
                logger.info("Homed — found home after %d steps", i)
                return
            GPIO.output(self.PIN_STEP, GPIO.HIGH)
            time.sleep(self.STEP_DELAY_S / 2)
            GPIO.output(self.PIN_STEP, GPIO.LOW)
            time.sleep(self.STEP_DELAY_S / 2)
        self._disable()
        raise RuntimeError("Carousel home not found — check optical end-stop wiring")

    def advance(self):
        """
        Rotate carousel 90° (one pipeline stage forward).
        Blocks until rotation is complete.
        """
        with self._lock:
            logger.debug("Carousel advance: pos %d → %d", self._position,
                         (self._position + 1) % 4)
            self._step(self.STEPS_PER_90)
            self._position = (self._position + 1) % 4
            # Small settle delay so platforms come to rest before camera fires
            time.sleep(0.15)

    def dispense(self, hold_s: float = 0.4):
        """
        Tilt the current dispense platform (POS_DISPENSE) to drop
        its brick into the pancake stack or gate tree below.

        Args:
            hold_s: seconds to hold the tilted position before returning flat
        """
        dispense_platform = (POS_DISPENSE - self._position) % 4
        logger.debug("Dispensing platform slot %d", dispense_platform)
        self._platform_tilt(dispense_platform)
        time.sleep(hold_s)
        self._platform_flat(dispense_platform)
        time.sleep(0.15)   # settle before next advance

    def imaging_ready(self) -> bool:
        """Return True when the carousel is stationary and a brick is
        at the imaging position (POS_IMAGE)."""
        # In production: check load sensor at pos-0 to confirm brick present
        # For now, assume a brick is always ready once homed.
        return True

    def wait_for_load(self, timeout_s: float = 10.0) -> bool:
        """
        Block until a brick is detected at the LOAD position (pos-0)
        by the step feeder's output sensor.

        Returns True if brick detected, False on timeout.
        """
        logger.debug("Waiting for brick at load position …")
        if not HW_AVAILABLE:
            time.sleep(0.05)   # simulate short load delay
            return True

        # Replace PIN_HOME with a separate IR proximity sensor for load detection
        # (GPIO pin configurable; use config['load_sensor_pin'])
        load_pin = self._cfg.get("load_sensor_pin", 23)
        deadline = time.monotonic() + timeout_s
        while time.monotonic() < deadline:
            if GPIO.input(load_pin) == GPIO.LOW:
                return True
            time.sleep(0.01)
        logger.warning("Timeout waiting for brick at load position")
        return False

    def status(self) -> dict:
        """Return current carousel state for Flask dashboard."""
        return {
            "position":    self._position,
            "tilt_state":  self._tilt_state.copy(),
            "position_names": {
                self._position % 4:             "LOAD",
                (self._position + 1) % 4:       "IMAGE",
                (self._position + 2) % 4:       "DISPENSE",
                (self._position + 3) % 4:       "CLEAR",
            },
        }

    def cleanup(self):
        """Release GPIO resources."""
        for i in range(4):
            self._platform_flat(i)
        self._disable()
        if HW_AVAILABLE:
            GPIO.cleanup()
        logger.info("CarouselFeeder cleaned up")
