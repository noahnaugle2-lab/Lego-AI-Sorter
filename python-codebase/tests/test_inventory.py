"""
Tests for the Inventory module — database operations, stats, export.
Run with: python -m pytest tests/ -v
"""
import sys
import os
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from inventory import Inventory


class TestInventory(unittest.TestCase):
    """Test SQLite inventory operations."""

    def setUp(self):
        self.tmpdb = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
        self.tmpdb.close()
        self.config = {
            "rebrickable": {"api_key": "", "target_sets": []},
        }
        self.inv = Inventory(self.config, db_path=self.tmpdb.name)

    def tearDown(self):
        self.inv.cleanup()
        try:
            os.unlink(self.tmpdb.name)
        except OSError:
            pass

    def test_log_part(self):
        """Logging a part returns a row ID."""
        row_id = self.inv.log_part(
            part_id="3001", part_name="Brick 2x4", color="Red",
            category="Brick 2 x 4", confidence=0.92, bin_number=2
        )
        self.assertIsInstance(row_id, int)
        self.assertGreater(row_id, 0)

    def test_get_stats_empty(self):
        """Stats on empty database."""
        stats = self.inv.get_stats()
        self.assertEqual(stats["total_sorted"], 0)
        self.assertEqual(stats["identified"], 0)
        self.assertEqual(stats["unique_parts"], 0)

    def test_get_stats_after_logging(self):
        """Stats update after logging parts."""
        self.inv.log_part("3001", "Brick 2x4", "Red", "Brick", 0.92, 2)
        self.inv.log_part("3001", "Brick 2x4", "Blue", "Brick", 0.88, 2)
        self.inv.log_part("3022", "Plate 2x2", "White", "Plate", 0.95, 5)

        stats = self.inv.get_stats()
        self.assertEqual(stats["total_sorted"], 3)
        self.assertEqual(stats["identified"], 3)
        self.assertEqual(stats["unique_parts"], 2)

    def test_get_recent_parts(self):
        """Recent parts returns most recent first."""
        self.inv.log_part("3001", "Brick 2x4", "Red", "Brick", 0.9, 2)
        self.inv.log_part("3022", "Plate 2x2", "Blue", "Plate", 0.85, 5)
        recent = self.inv.get_recent_parts(10)
        self.assertEqual(len(recent), 2)
        self.assertEqual(recent[0]["part_id"], "3022")  # Most recent first

    def test_update_part_bin(self):
        """Reclassification updates bin and logs correction."""
        row_id = self.inv.log_part("3001", "Brick 2x4", "Red", "Brick", 0.9, 2)
        original = self.inv.update_part_bin(row_id, 5)
        self.assertEqual(original["bin_number"], 2)

        recent = self.inv.get_recent_parts(1)
        self.assertEqual(recent[0]["bin_number"], 5)

    def test_review_parts(self):
        """Parts logged with needs_review appear in review query."""
        self.inv.log_part("3001", "Brick", "Red", "Brick", 0.5, 30,
                         needs_review=True)
        self.inv.log_part("3022", "Plate", "Blue", "Plate", 0.9, 5,
                         needs_review=False)
        reviews = self.inv.get_review_parts()
        self.assertEqual(len(reviews), 1)
        self.assertEqual(reviews[0]["part_id"], "3001")

    def test_confidence_histogram(self):
        """Histogram buckets have correct counts."""
        self.inv.log_part("a", "A", "", "X", 0.92, 0)
        self.inv.log_part("b", "B", "", "X", 0.95, 0)
        self.inv.log_part("c", "C", "", "X", 0.45, 0)

        hist = self.inv.get_confidence_histogram(100)
        self.assertEqual(len(hist["buckets"]), 10)
        # 0.92 and 0.95 go to bucket 9 (90-100%)
        self.assertEqual(hist["counts"][9], 2)
        # 0.45 goes to bucket 4 (40-50%)
        self.assertEqual(hist["counts"][4], 1)

    def test_export_inventory_csv(self):
        """CSV export contains header and data rows."""
        self.inv.log_part("3001", "Brick 2x4", "Red", "Brick", 0.9, 2)
        csv_data = self.inv.export_inventory_csv()
        lines = csv_data.strip().split("\n")
        self.assertEqual(len(lines), 2)  # Header + 1 data row
        self.assertIn("Part ID", lines[0])
        self.assertIn("3001", lines[1])

    def test_export_rebrickable_csv(self):
        """Rebrickable export has correct format."""
        self.inv.log_part("3001", "Brick 2x4", "Red", "Brick", 0.9, 2)
        self.inv.log_part("3001", "Brick 2x4", "Red", "Brick", 0.88, 2)
        csv_data = self.inv.export_rebrickable_csv()
        lines = csv_data.strip().split("\n")
        self.assertEqual(len(lines), 2)
        self.assertIn("Part,Color,Quantity", lines[0])
        # Quantity should be 2
        self.assertIn("2", lines[1])

    def test_sort_history_tracking(self):
        """Hourly aggregate updates when parts are logged."""
        self.inv.log_part("3001", "Brick", "Red", "Brick", 0.9, 2)
        history = self.inv.get_sort_history(hours=1)
        self.assertGreaterEqual(len(history), 1)
        self.assertEqual(history[0]["total_count"], 1)


if __name__ == "__main__":
    unittest.main()
