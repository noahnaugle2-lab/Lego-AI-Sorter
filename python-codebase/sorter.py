"""
LEGO AI Sorting Machine — Sorter (Binary Gate Tree)
Controls 31 servo gates via 2x PCA9685 boards to route bricks
through a 5-level binary tree into 32 output bins.

Supports multiple sort modes:
  - "part"     : Sort by part category (default)
  - "color"    : Sort by brick color
  - "set"      : Prioritize parts needed for a target set
  - "category" : Sort by broad category group
"""
import time
from typing import Dict, List, Optional, Set

from logger import get_logger

log = get_logger("sorter")

try:
    import board
    import busio
    from adafruit_pca9685 import PCA9685
    from adafruit_motor import servo as servo_lib
    HARDWARE_AVAILABLE = True
except ImportError:
    HARDWARE_AVAILABLE = False
    log.info("Adafruit PCA9685 library not available — simulation mode")


# ── COLOR-TO-BIN MAPPING ────────────────────────────────────
# Used by "color" sort mode. Maps common LEGO colors to bins 0-31.
COLOR_BIN_MAP: Dict[str, int] = {
    "white": 0, "black": 1, "light bluish gray": 2, "dark bluish gray": 3,
    "red": 4, "dark red": 5, "blue": 6, "dark blue": 7,
    "yellow": 8, "bright light orange": 9, "orange": 10, "dark orange": 11,
    "green": 12, "dark green": 13, "lime": 14, "bright green": 14,
    "tan": 15, "dark tan": 16, "reddish brown": 17, "brown": 18,
    "medium azure": 19, "dark azure": 19, "medium lavender": 20,
    "dark purple": 20, "bright pink": 21, "magenta": 21,
    "trans-clear": 22, "trans-red": 23, "trans-blue": 23,
    "trans-green": 24, "trans-yellow": 24, "trans-orange": 24,
    "pearl gold": 25, "flat silver": 26, "chrome silver": 26,
    "sand green": 27, "olive green": 27, "medium nougat": 28,
    "nougat": 28, "light nougat": 28,
}

# ── CATEGORY GROUP MAPPING ──────────────────────────────────
# Used by "category" sort mode. Groups related categories together.
CATEGORY_GROUP_MAP: Dict[str, int] = {
    "bricks": 0, "plates": 1, "tiles": 2, "slopes": 3,
    "technic": 4, "minifig": 5, "wheels_tires": 6, "windows_doors": 7,
    "round": 8, "modified": 9, "decorated": 10, "specialty": 11,
}

CATEGORY_TO_GROUP: Dict[str, str] = {
    "Brick 1 x": "bricks", "Brick 2 x": "bricks", "Brick 2 x 4": "bricks",
    "Brick 2 x 6": "bricks", "Brick 2 x 8": "bricks",
    "Plate 1 x": "plates", "Plate 2 x": "plates", "Plate 2 x 4": "plates",
    "Plate 2 x 6": "plates", "Plate 2 x 8": "plates",
    "Tile": "tiles", "Slope": "slopes",
    "Technic": "technic", "Technic Beam": "technic",
    "Technic Pin": "technic", "Technic Axle": "technic",
    "Minifig": "minifig",
    "Wheel": "wheels_tires", "Tire": "wheels_tires",
    "Window": "windows_doors", "Door": "windows_doors",
    "Round": "round", "Cone": "round", "Cylinder": "round",
    "Modified": "modified", "Hinge": "modified", "Clip": "modified",
    "Decorated": "decorated", "Flag": "decorated",
    "Arch": "specialty", "Wedge": "specialty", "Panel": "specialty",
    "Bar": "specialty", "Baseplate": "specialty",
}


class Sorter:
    """Binary gate tree controller with multiple sort modes.

    Attributes:
        num_bins: Total number of output bins (32).
        num_levels: Depth of binary tree (5).
        num_gates: Total servo gates (31).
        sort_mode: Current sort mode ('part', 'color', 'category', 'set').
    """

    def __init__(self, config: dict) -> None:
        cfg = config["sorter"]
        self.num_bins: int = cfg["num_bins"]
        self.num_levels: int = cfg["num_levels"]
        self.left_angle: float = cfg["left_angle"]
        self.right_angle: float = cfg["right_angle"]
        self.gate_settle_ms: int = cfg["gate_settle_ms"]
        self.servo_min: int = cfg["servo_min_pulse"]
        self.servo_max: int = cfg["servo_max_pulse"]

        # Metal-gear servo configuration
        self.mg_servo_levels: int = cfg.get("mg_servo_levels", 3)
        self.mg_servo_min_pulse: int = cfg.get("mg_servo_min_pulse", 500)
        self.mg_servo_max_pulse: int = cfg.get("mg_servo_max_pulse", 2400)

        self.mg_servo_gate_indices: Set[int] = set()
        for level in range(min(self.mg_servo_levels, self.num_levels)):
            start_idx = (2 ** level) - 1
            end_idx = (2 ** (level + 1)) - 1
            for idx in range(start_idx, end_idx):
                self.mg_servo_gate_indices.add(idx)

        self.bin_assignments: dict = config.get("bin_assignments", {})
        self.unknown_bin: int = config["classifier"]["unknown_bin"]

        # Sort mode
        self.sort_mode: str = cfg.get("sort_mode", "part")

        # Set-based sorting: maps part_id -> bin for target set parts
        self._set_priority_map: Dict[str, int] = {}
        self._set_priority_bin_start: int = cfg.get("set_priority_bin_start", 0)

        self.num_gates: int = (2 ** self.num_levels) - 1
        self._servos: list = []
        self._pca_boards: list = []

        # Bin count tracking
        self._bin_counts: Dict[int, int] = {i: 0 for i in range(self.num_bins)}
        self._gate_usage_counts: Dict[int, int] = {i: 0 for i in range(self.num_gates)}

        if HARDWARE_AVAILABLE:
            self._init_hardware(cfg)
        else:
            log.info(f"Simulation: {self.num_gates} virtual gates, "
                     f"{self.num_bins} bins, mode={self.sort_mode}")

    def _init_hardware(self, cfg: dict) -> None:
        """Initialize PCA9685 boards and servo objects."""
        i2c = busio.I2C(board.SCL, board.SDA)

        for addr in cfg["pca9685_addresses"]:
            pca = PCA9685(i2c, address=addr)
            pca.frequency = cfg["servo_freq"]
            self._pca_boards.append(pca)

        mg_count = 0
        sg_count = 0
        for i in range(self.num_gates):
            board_idx = 0 if i < 16 else 1
            channel = i if i < 16 else i - 16

            if i in self.mg_servo_gate_indices:
                min_pulse = self.mg_servo_min_pulse
                max_pulse = self.mg_servo_max_pulse
                mg_count += 1
            else:
                min_pulse = self.servo_min
                max_pulse = self.servo_max
                sg_count += 1

            s = servo_lib.Servo(
                self._pca_boards[board_idx].channels[channel],
                min_pulse=min_pulse,
                max_pulse=max_pulse,
            )
            self._servos.append(s)

        for s in self._servos:
            s.angle = 90

        log.info(f"Initialized {len(self._servos)} servos on "
                 f"{len(self._pca_boards)} PCA9685 boards")
        log.info(f"MG90S: {mg_count} gates (top {self.mg_servo_levels} levels), "
                 f"SG90: {sg_count} gates")

    # ── SORT MODE API ────────────────────────────────────────

    def set_sort_mode(self, mode: str) -> bool:
        """Change the active sort mode.

        Args:
            mode: One of 'part', 'color', 'category', 'set'.

        Returns:
            True if mode was set successfully.
        """
        valid_modes = ("part", "color", "category", "set")
        if mode not in valid_modes:
            log.warning(f"Invalid sort mode: {mode} (valid: {valid_modes})")
            return False
        self.sort_mode = mode
        log.info(f"Sort mode changed to: {mode}")
        return True

    def load_set_priority(self, set_parts: List[dict]) -> None:
        """Load a set's parts list for set-priority sorting.

        In 'set' mode, parts needed for the target set are routed to
        dedicated bins (starting at set_priority_bin_start). Other parts
        go to their normal category bin.

        Args:
            set_parts: List of dicts with 'part_id' and 'quantity' keys.
        """
        self._set_priority_map.clear()
        bin_idx = self._set_priority_bin_start
        for part in set_parts:
            if bin_idx >= self.num_bins - 2:  # Reserve last 2 for unknown/review
                break
            self._set_priority_map[part["part_id"]] = bin_idx
            bin_idx += 1
        log.info(f"Set priority loaded: {len(self._set_priority_map)} parts "
                 f"mapped to bins {self._set_priority_bin_start}-{bin_idx-1}")

    def get_bin_for_part(self, category: str, color: str = "",
                         part_id: str = "") -> int:
        """Look up which bin a part should go to based on current sort mode.

        Args:
            category: Category string from classifier.
            color: Color name (used in 'color' mode).
            part_id: Part ID (used in 'set' mode).

        Returns:
            Bin number (0 to num_bins-1).
        """
        if self.sort_mode == "color":
            return self._get_bin_by_color(color)
        elif self.sort_mode == "category":
            return self._get_bin_by_category_group(category)
        elif self.sort_mode == "set":
            return self._get_bin_by_set(part_id, category)
        else:  # "part" mode (default)
            return self._get_bin_by_part(category)

    def _get_bin_by_part(self, category: str) -> int:
        """Part-based bin assignment (original behavior)."""
        if not category:
            return self.unknown_bin
        if category in self.bin_assignments:
            return self.bin_assignments[category]
        for key, bin_num in self.bin_assignments.items():
            if category.startswith(key) or key in category:
                return bin_num
        return self.unknown_bin

    def _get_bin_by_color(self, color: str) -> int:
        """Color-based bin assignment."""
        if not color:
            return self.unknown_bin
        color_lower = color.lower().strip()
        if color_lower in COLOR_BIN_MAP:
            return COLOR_BIN_MAP[color_lower]
        # Fuzzy match: check if any key is a substring
        for key, bin_num in COLOR_BIN_MAP.items():
            if key in color_lower or color_lower in key:
                return bin_num
        return self.unknown_bin

    def _get_bin_by_category_group(self, category: str) -> int:
        """Broad category group bin assignment."""
        if not category:
            return self.unknown_bin
        group = CATEGORY_TO_GROUP.get(category, "")
        if group and group in CATEGORY_GROUP_MAP:
            return CATEGORY_GROUP_MAP[group]
        return self.unknown_bin

    def _get_bin_by_set(self, part_id: str, category: str) -> int:
        """Set-priority bin assignment: set parts get dedicated bins."""
        if part_id and part_id in self._set_priority_map:
            return self._set_priority_map[part_id]
        return self._get_bin_by_part(category)

    # ── GATE ROUTING ─────────────────────────────────────────

    def route_to_bin(self, bin_number: int) -> None:
        """Set all gates along the path to route a brick to the given bin.

        Args:
            bin_number: Output bin index (0 to num_bins-1).
        """
        if bin_number < 0 or bin_number >= self.num_bins:
            log.warning(f"Invalid bin number: {bin_number}")
            return

        self._bin_counts[bin_number] += 1

        path: List[str] = []
        for level in range(self.num_levels):
            bit = (bin_number >> (self.num_levels - 1 - level)) & 1
            path.append("R" if bit else "L")

        log.info(f"Routing to bin {bin_number}: {' -> '.join(path)}",
                 extra={"bin_number": bin_number})

        gate_index = 0
        for level in range(self.num_levels):
            direction = path[level]
            angle = self.right_angle if direction == "R" else self.left_angle
            self._set_gate(gate_index, angle)

            self._gate_usage_counts[gate_index] += 1
            if self._gate_usage_counts[gate_index] == 10000:
                log.warning(f"Gate {gate_index} reached 10000 actuations — "
                            f"consider maintenance",
                            extra={"gate_index": gate_index})

            if direction == "L":
                gate_index = 2 * gate_index + 1
            else:
                gate_index = 2 * gate_index + 2

        time.sleep(self.gate_settle_ms / 1000.0)

    def _set_gate(self, gate_index: int, angle: float) -> None:
        """Set a single gate servo to the given angle.

        Args:
            gate_index: Gate array index (0-30).
            angle: Servo angle in degrees.
        """
        if HARDWARE_AVAILABLE and gate_index < len(self._servos):
            self._servos[gate_index].angle = angle

    # ── BIN MONITORING ───────────────────────────────────────

    def get_bin_counts(self) -> Dict[int, int]:
        """Return copy of bin counts dictionary."""
        return self._bin_counts.copy()

    def get_bin_fill_warnings(self, threshold: int = 50) -> List[int]:
        """Return bin numbers that have exceeded the threshold count.

        Args:
            threshold: Count threshold for warning.

        Returns:
            Sorted list of bin numbers at or above threshold.
        """
        return sorted([
            bin_num for bin_num, count in self._bin_counts.items()
            if count >= threshold
        ])

    def reset_bin_count(self, bin_number: int) -> None:
        """Reset a specific bin's count (called when user empties a bin).

        Args:
            bin_number: Bin index to reset.
        """
        if 0 <= bin_number < self.num_bins:
            self._bin_counts[bin_number] = 0
            log.info(f"Reset count for bin {bin_number}")
        else:
            log.warning(f"Invalid bin number for reset: {bin_number}")

    def reset_all_bin_counts(self) -> None:
        """Reset all bin counts to zero."""
        self._bin_counts = {i: 0 for i in range(self.num_bins)}
        log.info("Reset all bin counts")

    # ── TESTING ──────────────────────────────────────────────

    def test_all_gates(self) -> None:
        """Sweep all gates left-right-center for testing."""
        log.info("Testing all gates...")
        for i in range(self.num_gates):
            self._set_gate(i, self.left_angle)
            time.sleep(0.05)
        time.sleep(0.5)
        for i in range(self.num_gates):
            self._set_gate(i, self.right_angle)
            time.sleep(0.05)
        time.sleep(0.5)
        for i in range(self.num_gates):
            self._set_gate(i, 90)
            time.sleep(0.05)
        log.info("Gate test complete")

    def test_bin(self, bin_number: int) -> None:
        """Route to a specific bin for testing, then reset to center.

        Args:
            bin_number: Bin to test.
        """
        self.route_to_bin(bin_number)
        time.sleep(2)
        for i in range(self.num_gates):
            self._set_gate(i, 90)

    def cleanup(self) -> None:
        """Release hardware resources."""
        for i in range(self.num_gates):
            self._set_gate(i, 90)
        if HARDWARE_AVAILABLE:
            for pca in self._pca_boards:
                pca.deinit()
        log.info("Cleaned up")
