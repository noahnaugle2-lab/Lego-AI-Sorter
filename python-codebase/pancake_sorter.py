"""
pancake_sorter.py — Pancake Stack + Mini Gate Tree Controller
==============================================================

Implements the two-stage distribution system for the v4 Hybrid design:

  Stage 1 — Pancake Stack (primary sort by category, 8 bins)
      One stepper rotates the central chute to face the correct
      bin-level.  A trap-door servo releases the brick.

  Stage 2 — Mini Gate Tree (sub-sort by part, 3 levels, 8 sub-bins)
      Identical to the existing BinaryGateTree in sorter.py but
      only 3 levels deep (7 servos) feeding into 8 output bins.

Together these give up to 8 × 8 = 64 unique sort destinations while
using fewer total servos than the original 5-level tree (15 vs 31).

Sort mapping:
    Category → pancake level (0–7)
    Part type → mini-tree bin (0–7) within that level

Hardware:
    Pancake chute stepper : NEMA 17 + TMC2209 on GPIO pins 5,6,13
    Pancake trap-door     : 1× SG90 on PCA9685 (addr 0x42) channel 0
    Mini gate servos      : 7× SG90/MG90S on PCA9685 (addr 0x42) ch 1–7

Usage:
    ps = PancakeSorter(config)
    ps.route("Brick 2 x 4", color="Red")  # routes to correct destination
"""

from __future__ import annotations

import time
import logging
import math
import threading
from typing import Optional

try:
    import RPi.GPIO as GPIO
    from adafruit_pca9685 import PCA9685
    import board
    import busio
    HW_AVAILABLE = True
except ImportError:
    HW_AVAILABLE = False

logger = logging.getLogger(__name__)

# ── Pancake stack geometry ─────────────────────────────────
NUM_STACK_BINS  = 8          # number of levels in the pancake stack
DEGREES_PER_BIN = 360 / NUM_STACK_BINS   # 45° per level

# ── Mini gate tree ─────────────────────────────────────────
NUM_MINI_LEVELS = 3          # 3 levels → 8 output bins
NUM_MINI_BINS   = 2 ** NUM_MINI_LEVELS   # 8

# ── Servo pulse widths (µs) ────────────────────────────────
_TRAP_CLOSED_PW = 1500       # trap-door closed
_TRAP_OPEN_PW   = 2000       # trap-door open (release brick)
_GATE_LEFT_PW   = 750        # mini-gate left position
_GATE_RIGHT_PW  = 2250       # mini-gate right position
_GATE_CENTRE_PW = 1500       # mini-gate neutral

_SERVO_FREQ = 50
_PW_TO_DC = lambda pw: int(pw / (1_000_000 / _SERVO_FREQ) * 0xFFFF)

# ── Category → pancake level mapping ──────────────────────
# Each of the 8 levels holds one broad LEGO category.
CATEGORY_TO_LEVEL: dict[str, int] = {
    "Brick":      0,
    "Plate":      1,
    "Tile":       2,
    "Technic":    3,
    "Minifig":    4,
    "Slope":      5,
    "Special":    6,
    "Unknown":    7,   # review / unknown parts
}

# ── Part subtype → mini-tree bin mapping ──────────────────
# Within each category level, the mini gate tree sub-sorts by size/variant.
PART_TO_MINIBIN: dict[str, int] = {
    # Brick sub-bins (0 = small, 7 = large)
    "1 x 1":  0, "1 x 2":  1, "1 x 4":  2, "2 x 2":  3,
    "2 x 4":  4, "2 x 6":  5, "2 x 8":  6, "Other":  7,
}

# Stepper GPIO for pancake chute rotation (separate from carousel stepper)
CHUTE_PIN_STEP   = 5
CHUTE_PIN_DIR    = 6
CHUTE_PIN_ENABLE = 13

# Stepper calibration
CHUTE_STEPS_PER_REV  = 200
CHUTE_MICROSTEPS     = 4
CHUTE_GEAR_RATIO     = 3.0    # worm gear
CHUTE_STEPS_PER_DEG  = (CHUTE_STEPS_PER_REV * CHUTE_MICROSTEPS
                         * CHUTE_GEAR_RATIO / 360)
CHUTE_STEP_DELAY_S   = 0.001


class PancakeSorter:
    """
    Two-stage sorter: pancake stack (category) + mini gate tree (part).
    """

    def __init__(self, config: dict):
        self._cfg   = config
        self._lock  = threading.Lock()
        self._chute_angle = 0.0   # current chute angle (degrees)

        pca_addr = config.get("pancake_pca9685_address", 0x42)
        if HW_AVAILABLE:
            GPIO.setmode(GPIO.BCM)
            for pin in [CHUTE_PIN_STEP, CHUTE_PIN_DIR, CHUTE_PIN_ENABLE]:
                GPIO.setup(pin, GPIO.OUT, initial=GPIO.LOW)
            GPIO.output(CHUTE_PIN_ENABLE, GPIO.HIGH)  # disabled until needed

            i2c = busio.I2C(board.SCL, board.SDA)
            self._pca = PCA9685(i2c, address=pca_addr)
            self._pca.frequency = _SERVO_FREQ
        else:
            self._pca = None
            logger.warning("PancakeSorter running in simulation mode")

        # Mini-gate settle time (ms)
        self._gate_settle_s = config.get("mini_gate_settle_ms", 120) / 1000

        logger.info("PancakeSorter initialised (%d stack + %d mini-tree)",
                    NUM_STACK_BINS, NUM_MINI_BINS)

    # ── Chute stepper ─────────────────────────────────────────

    def _chute_enable(self):
        if HW_AVAILABLE:
            GPIO.output(CHUTE_PIN_ENABLE, GPIO.LOW)

    def _chute_disable(self):
        if HW_AVAILABLE:
            GPIO.output(CHUTE_PIN_ENABLE, GPIO.HIGH)

    def _rotate_chute(self, target_angle: float):
        """
        Rotate the central chute to target_angle (0–360°).
        Always takes the shorter arc (≤180° movement).
        """
        delta = target_angle - self._chute_angle
        # Normalise to −180 … +180
        while delta >  180: delta -= 360
        while delta < -180: delta += 360

        steps = int(abs(delta) * CHUTE_STEPS_PER_DEG)
        direction = 1 if delta >= 0 else -1
        logger.debug("Chute rotate %.1f° → %.1f° (%d steps)",
                     self._chute_angle, target_angle, steps * direction)

        if HW_AVAILABLE:
            GPIO.output(CHUTE_PIN_DIR,
                        GPIO.HIGH if direction > 0 else GPIO.LOW)
            self._chute_enable()
            for _ in range(steps):
                GPIO.output(CHUTE_PIN_STEP, GPIO.HIGH)
                time.sleep(CHUTE_STEP_DELAY_S / 2)
                GPIO.output(CHUTE_PIN_STEP, GPIO.LOW)
                time.sleep(CHUTE_STEP_DELAY_S / 2)
            self._chute_disable()

        self._chute_angle = target_angle % 360

    # ── Trap-door servo ───────────────────────────────────────

    def _set_servo(self, channel: int, pw: int):
        if self._pca:
            self._pca.channels[channel].duty_cycle = _PW_TO_DC(pw)

    def _open_trap(self, hold_s: float = 0.35):
        self._set_servo(0, _TRAP_OPEN_PW)
        time.sleep(hold_s)
        self._set_servo(0, _TRAP_CLOSED_PW)
        time.sleep(0.1)

    # ── Mini gate tree ─────────────────────────────────────────

    def _set_mini_gate(self, gate_index: int, direction: str):
        """Set one mini-gate (PCA9685 channels 1–7)."""
        channel = gate_index + 1   # channels 1–7
        pw = _GATE_RIGHT_PW if direction == "R" else _GATE_LEFT_PW
        self._set_servo(channel, pw)

    def _route_mini_tree(self, bin_number: int):
        """Route through the 3-level mini gate tree to bin 0–7."""
        gate_index = 0
        for level in range(NUM_MINI_LEVELS):
            bit = (bin_number >> (NUM_MINI_LEVELS - 1 - level)) & 1
            direction = "R" if bit else "L"
            self._set_mini_gate(gate_index, direction)
            gate_index = 2 * gate_index + (2 if direction == "R" else 1)

        time.sleep(self._gate_settle_s)
        logger.debug("Mini-tree routed to sub-bin %d", bin_number)

    # ── Category and part lookup ──────────────────────────────

    @staticmethod
    def _get_stack_level(category: str) -> int:
        """Map a category name to a pancake stack level (0–7)."""
        for key, level in CATEGORY_TO_LEVEL.items():
            if key.lower() in category.lower():
                return level
        return CATEGORY_TO_LEVEL["Unknown"]

    @staticmethod
    def _get_mini_bin(part_description: str) -> int:
        """Map a part description to a mini-tree bin (0–7)."""
        for key, bin_n in PART_TO_MINIBIN.items():
            if key in part_description:
                return bin_n
        return PART_TO_MINIBIN["Other"]

    # ── Public API ────────────────────────────────────────────

    def route(self, category: str, part_description: str = "",
              color: str = "") -> tuple[int, int]:
        """
        Route a classified brick to its destination.

        Args:
            category         : broad LEGO category (e.g. "Brick", "Plate")
            part_description : part sub-type (e.g. "2 x 4", "1 x 2")
            color            : brick color (reserved for future color-bin mode)

        Returns:
            (stack_level, mini_bin) — two-part address of the destination
        """
        with self._lock:
            stack_level = self._get_stack_level(category)
            mini_bin    = self._get_mini_bin(part_description)

            target_angle = stack_level * DEGREES_PER_BIN

            logger.info("Routing '%s %s' → stack level %d (%.0f°), mini-bin %d",
                        category, part_description, stack_level,
                        target_angle, mini_bin)

            # 1. Rotate chute to correct stack level
            self._rotate_chute(target_angle)

            # 2. Pre-set mini gate tree for the sub-bin
            self._route_mini_tree(mini_bin)

            # 3. Open trap-door; brick falls through chute into level tray
            self._open_trap()

            return stack_level, mini_bin

    def status(self) -> dict:
        """Return current sorter state for Flask dashboard."""
        return {
            "chute_angle_deg": round(self._chute_angle, 1),
            "current_stack_level": round(self._chute_angle / DEGREES_PER_BIN),
            "stack_bin_labels": list(CATEGORY_TO_LEVEL.keys()),
            "mini_bin_labels":  list(PART_TO_MINIBIN.keys()),
        }

    def cleanup(self):
        """Release resources."""
        self._set_servo(0, _TRAP_CLOSED_PW)
        for ch in range(1, 8):
            self._set_servo(ch, _GATE_CENTRE_PW)
        self._chute_disable()
        if HW_AVAILABLE:
            GPIO.cleanup()
        logger.info("PancakeSorter cleaned up")
