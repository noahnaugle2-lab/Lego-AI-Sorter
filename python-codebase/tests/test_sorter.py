"""
Tests for the Sorter module — binary gate tree routing and sort modes.
Run with: python -m pytest tests/ -v
"""
import sys
import os
import unittest

# Add parent dir to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class TestSorterRouting(unittest.TestCase):
    """Test binary tree routing logic."""

    def setUp(self):
        """Create a Sorter with a minimal config (no hardware)."""
        self.config = {
            "sorter": {
                "num_bins": 32,
                "num_levels": 5,
                "left_angle": 30,
                "right_angle": 150,
                "gate_settle_ms": 0,
                "servo_min_pulse": 150,
                "servo_max_pulse": 600,
                "pca9685_addresses": [0x40, 0x41],
                "servo_freq": 50,
                "mg_servo_levels": 3,
                "mg_servo_min_pulse": 500,
                "mg_servo_max_pulse": 2400,
                "servo_power_pin": 22,
                "bin_full_threshold": 50,
                "sort_mode": "part",
            },
            "classifier": {"unknown_bin": 31},
            "bin_assignments": {
                "Brick 1 x": 0,
                "Brick 2 x": 1,
                "Plate 1 x": 4,
                "Technic": 10,
                "Minifig": 14,
                "Other": 29,
            },
        }
        from sorter import Sorter
        self.sorter = Sorter(self.config)

    def test_num_gates(self):
        """31 gates for a 5-level tree."""
        self.assertEqual(self.sorter.num_gates, 31)

    def test_num_bins(self):
        """32 bins."""
        self.assertEqual(self.sorter.num_bins, 32)

    def test_route_increments_bin_count(self):
        """Routing to a bin increments its counter."""
        self.sorter.route_to_bin(5)
        self.sorter.route_to_bin(5)
        self.sorter.route_to_bin(10)
        counts = self.sorter.get_bin_counts()
        self.assertEqual(counts[5], 2)
        self.assertEqual(counts[10], 1)
        self.assertEqual(counts[0], 0)

    def test_route_invalid_bin(self):
        """Routing to invalid bins does nothing."""
        self.sorter.route_to_bin(-1)
        self.sorter.route_to_bin(32)
        self.sorter.route_to_bin(100)
        total = sum(self.sorter.get_bin_counts().values())
        self.assertEqual(total, 0)

    def test_bin_fill_warnings(self):
        """Bins above threshold appear in warnings list."""
        for _ in range(50):
            self.sorter.route_to_bin(3)
        for _ in range(49):
            self.sorter.route_to_bin(7)
        warnings = self.sorter.get_bin_fill_warnings(threshold=50)
        self.assertIn(3, warnings)
        self.assertNotIn(7, warnings)

    def test_reset_bin_count(self):
        """Resetting a bin count zeroes it out."""
        for _ in range(10):
            self.sorter.route_to_bin(2)
        self.sorter.reset_bin_count(2)
        self.assertEqual(self.sorter.get_bin_counts()[2], 0)

    def test_reset_all_bin_counts(self):
        """Resetting all bins zeroes everything."""
        self.sorter.route_to_bin(0)
        self.sorter.route_to_bin(15)
        self.sorter.reset_all_bin_counts()
        self.assertTrue(all(v == 0 for v in self.sorter.get_bin_counts().values()))

    def test_mg_servo_gate_indices(self):
        """Top 3 levels = gates 0-6 (7 gates) should use MG90S."""
        expected = {0, 1, 2, 3, 4, 5, 6}
        self.assertEqual(self.sorter.mg_servo_gate_indices, expected)


class TestSortModes(unittest.TestCase):
    """Test multi-sort-mode bin assignment."""

    def setUp(self):
        self.config = {
            "sorter": {
                "num_bins": 32, "num_levels": 5, "left_angle": 30,
                "right_angle": 150, "gate_settle_ms": 0,
                "servo_min_pulse": 150, "servo_max_pulse": 600,
                "pca9685_addresses": [0x40, 0x41], "servo_freq": 50,
                "mg_servo_levels": 3, "mg_servo_min_pulse": 500,
                "mg_servo_max_pulse": 2400, "servo_power_pin": 22,
                "bin_full_threshold": 50, "sort_mode": "part",
            },
            "classifier": {"unknown_bin": 31},
            "bin_assignments": {
                "Brick 1 x": 0, "Brick 2 x": 1,
                "Plate 1 x": 4, "Technic": 10,
                "Other": 29,
            },
        }
        from sorter import Sorter
        self.sorter = Sorter(self.config)

    def test_part_mode_default(self):
        """Default part mode uses bin_assignments."""
        self.assertEqual(self.sorter.get_bin_for_part("Brick 1 x"), 0)
        self.assertEqual(self.sorter.get_bin_for_part("Technic"), 10)
        self.assertEqual(self.sorter.get_bin_for_part("Unknown"), 31)

    def test_color_mode(self):
        """Color mode maps colors to bins."""
        self.sorter.set_sort_mode("color")
        self.assertEqual(self.sorter.get_bin_for_part("", color="red"), 4)
        self.assertEqual(self.sorter.get_bin_for_part("", color="white"), 0)
        self.assertEqual(self.sorter.get_bin_for_part("", color="black"), 1)

    def test_category_mode(self):
        """Category mode groups related categories."""
        self.sorter.set_sort_mode("category")
        # Brick -> bricks group -> bin 0
        self.assertEqual(self.sorter.get_bin_for_part("Brick 1 x"), 0)
        # Technic -> technic group -> bin 4
        self.assertEqual(self.sorter.get_bin_for_part("Technic"), 4)

    def test_set_mode(self):
        """Set mode routes matching part IDs to priority bins."""
        self.sorter.set_sort_mode("set")
        self.sorter.load_set_priority([
            {"part_id": "3001", "quantity": 4},
            {"part_id": "3022", "quantity": 2},
        ])
        # Matching part_id goes to set-priority bin
        self.assertEqual(self.sorter.get_bin_for_part("Brick 2 x", part_id="3001"), 0)
        # Non-matching falls back to part mode
        self.assertEqual(self.sorter.get_bin_for_part("Brick 1 x", part_id="9999"), 0)

    def test_invalid_sort_mode(self):
        """Invalid sort mode returns False."""
        self.assertFalse(self.sorter.set_sort_mode("invalid"))
        self.assertEqual(self.sorter.sort_mode, "part")  # Unchanged


class TestGateUsageTracking(unittest.TestCase):
    """Test gate actuation counting for predictive maintenance."""

    def setUp(self):
        self.config = {
            "sorter": {
                "num_bins": 32, "num_levels": 5, "left_angle": 30,
                "right_angle": 150, "gate_settle_ms": 0,
                "servo_min_pulse": 150, "servo_max_pulse": 600,
                "pca9685_addresses": [0x40, 0x41], "servo_freq": 50,
                "mg_servo_levels": 3, "mg_servo_min_pulse": 500,
                "mg_servo_max_pulse": 2400, "servo_power_pin": 22,
                "bin_full_threshold": 50, "sort_mode": "part",
            },
            "classifier": {"unknown_bin": 31},
            "bin_assignments": {},
        }
        from sorter import Sorter
        self.sorter = Sorter(self.config)

    def test_gate_usage_increments(self):
        """Routing to bin 0 (LLLLL) touches gates 0,1,3,7,15."""
        self.sorter.route_to_bin(0)
        counts = self.sorter._gate_usage_counts
        # Root gate always used
        self.assertEqual(counts[0], 1)
        # Gate 1 (left child of 0)
        self.assertEqual(counts[1], 1)
        # Gate 2 (right child of 0) — not used for bin 0
        self.assertEqual(counts[2], 0)


if __name__ == "__main__":
    unittest.main()
