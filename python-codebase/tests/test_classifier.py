"""
Tests for the Classifier module — local cache, confidence routing, categories.
Run with: python -m pytest tests/ -v
"""
import sys
import os
import json
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from classifier import LocalCache, ClassificationResult, Classifier


class TestLocalCache(unittest.TestCase):
    """Test the HSV histogram local cache."""

    def setUp(self):
        self.tmpfile = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
        self.tmpfile.close()
        self.cache = LocalCache(cache_path=self.tmpfile.name, max_size=5)

    def tearDown(self):
        try:
            os.unlink(self.tmpfile.name)
        except OSError:
            pass

    def _make_image(self, color=(128, 128, 128), size=(50, 50)):
        """Create a solid-color test image."""
        img = np.zeros((size[1], size[0], 3), dtype=np.uint8)
        img[:, :] = color
        return img

    def test_empty_cache_returns_none(self):
        """No match when cache is empty."""
        img = self._make_image()
        self.assertIsNone(self.cache.find_match(img))

    def test_learn_and_match(self):
        """Learned images should match themselves."""
        img = self._make_image(color=(0, 0, 255))
        self.cache.learn(img, "3001", "Brick 2x4", "Red", 0.95)
        match = self.cache.find_match(img, threshold=0.80)
        self.assertIsNotNone(match)
        self.assertEqual(match["part_id"], "3001")

    def test_different_image_no_match(self):
        """Very different images should not match."""
        img_red = self._make_image(color=(0, 0, 255))
        img_blue = self._make_image(color=(255, 0, 0))
        self.cache.learn(img_red, "3001", "Brick 2x4", "Red", 0.95)
        # Blue image should not match red
        match = self.cache.find_match(img_blue, threshold=0.95)
        self.assertIsNone(match)

    def test_max_size_eviction(self):
        """Cache respects max_size by evicting oldest."""
        for i in range(6):  # Max size is 5
            img = self._make_image(color=(i * 40, 0, 0))
            self.cache.learn(img, f"part_{i}", f"Part {i}", "Red", 0.9)
        self.assertLessEqual(len(self.cache.cache), 5)

    def test_persistence(self):
        """Cache saves to disk and loads back."""
        img = self._make_image(color=(100, 200, 50))
        self.cache.learn(img, "3002", "Brick 2x3", "Blue", 0.88)

        # Create new cache from same file
        cache2 = LocalCache(cache_path=self.tmpfile.name, max_size=5)
        self.assertEqual(len(cache2.cache), 1)
        entry = list(cache2.cache.values())[0]
        self.assertEqual(entry["part_id"], "3002")

    def test_clear(self):
        """Clear empties cache and removes file."""
        img = self._make_image()
        self.cache.learn(img, "3001", "Test", "Red", 0.9)
        self.cache.clear()
        self.assertEqual(len(self.cache.cache), 0)

    def test_histogram_correlation_empty(self):
        """Empty histograms return 0."""
        self.assertEqual(self.cache._histogram_correlation(
            np.array([]), np.array([])), 0.0)

    def test_histogram_correlation_mismatched(self):
        """Mismatched histogram sizes return 0."""
        self.assertEqual(self.cache._histogram_correlation(
            np.array([1, 2, 3]), np.array([1, 2])), 0.0)

    def test_histogram_correlation_zero_sum(self):
        """Zero-sum histograms return 0."""
        self.assertEqual(self.cache._histogram_correlation(
            np.array([0, 0, 0]), np.array([1, 2, 3])), 0.0)


class TestClassificationResult(unittest.TestCase):
    """Test ClassificationResult properties."""

    def test_is_confident(self):
        result = ClassificationResult(confidence=0.75)
        self.assertTrue(result.is_confident)

    def test_not_confident(self):
        result = ClassificationResult(confidence=0.0)
        self.assertFalse(result.is_confident)

    def test_needs_review_flag(self):
        result = ClassificationResult(confidence=0.5, needs_review=True)
        self.assertTrue(result.needs_review)
        self.assertTrue(result.is_confident)  # confidence > 0

    def test_to_dict(self):
        result = ClassificationResult(
            part_id="3001", part_name="Brick 2x4",
            color="Red", confidence=0.92
        )
        d = result.to_dict()
        self.assertEqual(d["part_id"], "3001")
        self.assertEqual(d["confidence"], 0.92)
        self.assertIn("needs_review", d)


class TestCategoryExtraction(unittest.TestCase):
    """Test the _extract_category method."""

    def setUp(self):
        self.config = {
            "classifier": {
                "api_url": "https://api.brickognize.com/predict/",
                "confidence_threshold": 0.65,
                "timeout_seconds": 10,
                "retry_count": 2,
                "unknown_bin": 31,
                "local_cache_enabled": False,
            },
        }
        self.clf = Classifier(self.config)

    def test_brick_category(self):
        self.assertEqual(self.clf._extract_category("Brick 2 x 4"), "Brick 2 x 4")

    def test_plate_category(self):
        self.assertEqual(self.clf._extract_category("Plate 1 x 2"), "Plate 1 x")

    def test_technic_beam(self):
        self.assertEqual(self.clf._extract_category("Technic Beam 5"), "Technic Beam")

    def test_technic_pin(self):
        self.assertEqual(self.clf._extract_category("Technic Pin with Friction"), "Technic Pin")

    def test_minifig(self):
        self.assertEqual(self.clf._extract_category("Minifig Torso"), "Minifig")

    def test_unknown(self):
        self.assertEqual(self.clf._extract_category("Something Weird"), "Other")


if __name__ == "__main__":
    unittest.main()
