"""
LEGO AI Sorting Machine — Classifier (Brickognize API)
Sends brick images to the Brickognize API and returns
part identification results.

Features:
  - Local cache (HSV histogram + aspect ratio signatures)
  - Confidence-based routing (review bin for uncertain parts)
  - Multi-angle support (primary + secondary camera)
  - Learning from dashboard corrections
"""
import io
import time
import json
import os
from typing import Optional, List

import requests
import numpy as np

from logger import get_logger

log = get_logger("classifier")

try:
    import cv2
    CV2_AVAILABLE = True
except ImportError:
    CV2_AVAILABLE = False


class LocalCache:
    """Maintains a learned dictionary of part signatures (color histogram + aspect ratio)
    mapped to part IDs. Stores signatures to JSON for persistence across sessions.

    Attributes:
        cache: Dict of signature_key -> part info with histogram and metadata.
    """

    def __init__(self, cache_path: str = "local_cache.json",
                 max_size: int = 200) -> None:
        self.cache_path: str = cache_path
        self.max_size: int = max_size
        self.cache: dict = {}
        self.histogram_bins: tuple = (8, 8, 4)  # H, S, V bins
        self._load_from_disk()

    def _compute_signature(self, image: np.ndarray,
                           bbox: Optional[tuple] = None) -> dict:
        """Compute color histogram and aspect ratio signature from image.

        Args:
            image: BGR numpy array.
            bbox: Optional bounding box (x, y, w, h) for ROI.

        Returns:
            Dictionary with 'histogram' (normalized 1D array) and 'aspect_ratio'.
        """
        if bbox is not None:
            x, y, w, h = bbox
            roi = image[y:y+h, x:x+w]
        else:
            roi = image

        if CV2_AVAILABLE:
            hsv = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV).astype(np.float32)
        else:
            hsv = roi.astype(np.float32)

        hist = np.histogramdd(
            hsv.reshape(-1, 3),
            bins=self.histogram_bins,
            range=[[0, 180], [0, 256], [0, 256]]
        )[0]

        hist = hist.astype(np.float32)
        hist_sum = np.sum(hist)
        if hist_sum > 0:
            hist = hist / hist_sum
        hist = hist.flatten()

        h, w = roi.shape[:2]
        aspect_ratio = float(w) / max(1, h)

        return {"histogram": hist, "aspect_ratio": aspect_ratio}

    def _histogram_correlation(self, hist1: np.ndarray,
                                hist2: np.ndarray) -> float:
        """Compute Bhattacharyya coefficient between two histograms.

        Args:
            hist1: First normalized histogram.
            hist2: Second normalized histogram.

        Returns:
            Similarity score in [0, 1].
        """
        h1 = hist1.flatten() if isinstance(hist1, np.ndarray) else np.array(hist1)
        h2 = hist2.flatten() if isinstance(hist2, np.ndarray) else np.array(hist2)

        if h1.size == 0 or h2.size == 0 or h1.size != h2.size:
            return 0.0

        h1_sum = np.sum(h1)
        h2_sum = np.sum(h2)
        if h1_sum == 0 or h2_sum == 0:
            return 0.0
        h1 = h1 / h1_sum
        h2 = h2 / h2_sum

        correlation = np.sum(np.sqrt(h1 * h2))
        return float(np.clip(correlation, 0, 1))

    def _compute_similarity(self, sig1: dict, sig2: dict) -> float:
        """Compute overall similarity between two signatures.

        Weighted: 0.7 * histogram_correlation + 0.3 * aspect_ratio_similarity.
        """
        hist_corr = self._histogram_correlation(sig1["histogram"], sig2["histogram"])
        ratio_diff = abs(sig1["aspect_ratio"] - sig2["aspect_ratio"])
        ratio_sim = 1.0 - min(1.0, ratio_diff)
        similarity = 0.7 * hist_corr + 0.3 * ratio_sim
        return float(np.clip(similarity, 0, 1))

    def find_match(self, image: np.ndarray, bbox: Optional[tuple] = None,
                   threshold: float = 0.90) -> Optional[dict]:
        """Check if the image signature matches any learned example.

        Args:
            image: BGR numpy array.
            bbox: Optional bounding box for ROI.
            threshold: Minimum similarity to consider a match.

        Returns:
            Matched part dict or None.
        """
        if not self.cache:
            return None

        current_sig = self._compute_signature(image, bbox)
        best_match = None
        best_similarity = 0.0

        for sig_key, part_info in self.cache.items():
            cached_hist = part_info.get("histogram", [])
            if not cached_hist:
                continue
            cached_sig = {
                "histogram": np.array(cached_hist, dtype=np.float32),
                "aspect_ratio": float(part_info.get("aspect_ratio", 1.0))
            }
            try:
                similarity = self._compute_similarity(current_sig, cached_sig)
            except (ValueError, TypeError):
                continue

            if similarity > best_similarity:
                best_similarity = similarity
                best_match = (part_info, similarity)

        if best_match and best_similarity >= threshold:
            return best_match[0]
        return None

    def learn(self, image: np.ndarray, part_id: str, part_name: str,
              color: str, confidence: float, bbox: Optional[tuple] = None) -> None:
        """Store a brick signature as a learned example.

        Args:
            image: BGR numpy array.
            part_id: Part ID from API.
            part_name: Part name from API.
            color: Color from API.
            confidence: API confidence score.
            bbox: Optional bounding box for ROI.
        """
        if len(self.cache) >= self.max_size:
            oldest_key = next(iter(self.cache))
            del self.cache[oldest_key]

        sig = self._compute_signature(image, bbox)
        sig_key = f"{part_id}_{len(self.cache)}"

        self.cache[sig_key] = {
            "part_id": part_id,
            "part_name": part_name,
            "color": color,
            "confidence": confidence,
            "histogram": sig["histogram"].tolist(),
            "aspect_ratio": sig["aspect_ratio"],
        }
        self._save_to_disk()

    def learn_from_correction(self, image: np.ndarray, part_id: str,
                               part_name: str, color: str) -> None:
        """Learn from a user correction on the dashboard.

        Stores the signature with boosted confidence (1.0) since the
        user manually verified the identity.

        Args:
            image: BGR numpy array of the brick.
            part_id: Corrected part ID.
            part_name: Corrected part name.
            color: Corrected color.
        """
        self.learn(image, part_id, part_name, color, confidence=1.0)
        log.info(f"Learned from correction: {part_name} ({part_id})")

    def _load_from_disk(self) -> None:
        """Load cached signatures from JSON file."""
        if os.path.exists(self.cache_path):
            try:
                with open(self.cache_path, 'r') as f:
                    self.cache = json.load(f)
                log.info(f"Loaded {len(self.cache)} cached signatures")
            except Exception as e:
                log.warning(f"Failed to load cache: {e}")
                self.cache = {}

    def _save_to_disk(self) -> None:
        """Save cached signatures to JSON file."""
        try:
            with open(self.cache_path, 'w') as f:
                json.dump(self.cache, f, indent=2)
        except Exception as e:
            log.warning(f"Failed to save cache: {e}")

    def clear(self) -> None:
        """Clear all cached signatures."""
        self.cache.clear()
        if os.path.exists(self.cache_path):
            try:
                os.remove(self.cache_path)
            except Exception as e:
                log.warning(f"Failed to delete cache file: {e}")


class ClassificationResult:
    """Holds the result of a brick classification.

    Attributes:
        part_id: Part identifier string (e.g. "3001").
        part_name: Human-readable part name.
        color: Color name from the API.
        confidence: Classification confidence 0.0-1.0.
        category: Broad category for bin assignment.
        is_confident: True if confidence exceeds threshold.
        needs_review: True if confidence is in the review zone.
    """

    def __init__(self, part_id: str = "", part_name: str = "",
                 color: str = "", confidence: float = 0.0,
                 category: str = "", image_url: str = "",
                 alternatives: Optional[list] = None,
                 raw_response: Optional[dict] = None,
                 needs_review: bool = False) -> None:
        self.part_id = part_id
        self.part_name = part_name
        self.color = color
        self.confidence = confidence
        self.category = category
        self.image_url = image_url
        self.alternatives = alternatives or []
        self.raw_response = raw_response or {}
        self.needs_review = needs_review

    @property
    def is_confident(self) -> bool:
        """True if classification confidence is above zero (passed threshold)."""
        return self.confidence > 0

    def to_dict(self) -> dict:
        """Serialize to dictionary."""
        return {
            "part_id": self.part_id,
            "part_name": self.part_name,
            "color": self.color,
            "confidence": self.confidence,
            "category": self.category,
            "image_url": self.image_url,
            "alternatives": self.alternatives,
            "needs_review": self.needs_review,
        }

    def __repr__(self) -> str:
        return (f"ClassificationResult('{self.part_id}' {self.part_name}, "
                f"color={self.color}, conf={self.confidence:.2f}"
                f"{', REVIEW' if self.needs_review else ''})")


class Classifier:
    """Brickognize API classifier with local cache and confidence routing.

    Attributes:
        api_url: Brickognize API endpoint URL.
        review_threshold: Confidence below this goes to review bin.
        stats: Dictionary of classification statistics.
    """

    def __init__(self, config: dict) -> None:
        cfg = config["classifier"]
        self.api_url: str = cfg["api_url"]
        self.confidence_threshold: float = cfg["confidence_threshold"]
        self.timeout: int = cfg["timeout_seconds"]
        self.retry_count: int = cfg["retry_count"]
        self.unknown_bin: int = cfg["unknown_bin"]

        # Confidence-based routing
        self.review_enabled: bool = cfg.get("review_bin_enabled", True)
        self.review_threshold: float = cfg.get("review_threshold", 0.45)
        self.review_bin: int = cfg.get("review_bin", 30)

        # Local cache configuration
        self.local_cache_enabled: bool = cfg.get("local_cache_enabled", True)
        self.local_cache_path: str = cfg.get("local_cache_path", "local_cache.json")
        self.local_cache_learn_threshold: float = cfg.get("local_cache_learn_threshold", 0.85)

        self._session = requests.Session()
        self._session.headers.update({"accept": "application/json"})

        if self.local_cache_enabled:
            self.local_cache = LocalCache(
                cache_path=self.local_cache_path,
                max_size=cfg.get("local_cache_max_size", 200)
            )
        else:
            self.local_cache = None

        # Stats
        self.total_classifications: int = 0
        self.successful_classifications: int = 0
        self.failed_classifications: int = 0
        self.review_classifications: int = 0
        self.cache_hits: int = 0
        self.cache_misses: int = 0

        log.info(f"Brickognize API: {self.api_url}")
        log.info(f"Confidence threshold: {self.confidence_threshold}")
        if self.review_enabled:
            log.info(f"Review bin: {self.review_bin} (threshold < {self.review_threshold})")
        if self.local_cache_enabled:
            log.info(f"Local cache enabled: {self.local_cache_path}")

    def classify(self, image: np.ndarray,
                 secondary_image: Optional[np.ndarray] = None) -> ClassificationResult:
        """Send an image to Brickognize and return the classification.

        Checks local cache first. If a secondary image is provided, it is
        sent as a supplementary classification and results are merged.

        Args:
            image: Primary BGR numpy array from the camera.
            secondary_image: Optional side-view BGR image for multi-angle.

        Returns:
            ClassificationResult with part info.
        """
        self.total_classifications += 1

        # Check local cache first
        if self.local_cache_enabled and self.local_cache:
            cached_part = self.local_cache.find_match(image, threshold=0.90)
            if cached_part:
                self.cache_hits += 1
                result = ClassificationResult(
                    part_id=cached_part.get("part_id", ""),
                    part_name=cached_part.get("part_name", ""),
                    color=cached_part.get("color", ""),
                    confidence=cached_part.get("confidence", 0.95),
                    category=self._extract_category(cached_part.get("part_name", "")),
                )
                self.successful_classifications += 1
                log.info(f"Local cache hit: {result.part_name}",
                         extra={"cache_hit": True, "part_id": result.part_id})
                return result
            else:
                self.cache_misses += 1

        # Encode and classify primary image
        result = self._classify_single(image)

        # If secondary image available and primary was uncertain, try multi-angle
        if (secondary_image is not None and
                result.confidence < self.confidence_threshold and
                result.confidence > 0):
            log.info("Primary uncertain — trying secondary camera")
            result_2 = self._classify_single(secondary_image)
            if result_2.confidence > result.confidence:
                log.info(f"Secondary camera improved: {result.confidence:.2f} → "
                         f"{result_2.confidence:.2f}")
                result = result_2

        # Apply confidence routing
        if result.confidence >= self.confidence_threshold:
            self.successful_classifications += 1
            log.info(f"Identified: {result}",
                     extra={"part_id": result.part_id,
                            "confidence": result.confidence})

            # Learn high-confidence results
            if (self.local_cache_enabled and self.local_cache and
                    result.confidence >= self.local_cache_learn_threshold):
                self.local_cache.learn(
                    image=image,
                    part_id=result.part_id,
                    part_name=result.part_name,
                    color=result.color,
                    confidence=result.confidence,
                )
        elif (self.review_enabled and
              result.confidence >= self.review_threshold):
            # In the "review zone" — not confident enough to auto-sort,
            # but enough info to show user for manual verification
            result.needs_review = True
            self.review_classifications += 1
            log.info(f"Needs review: {result.part_name} "
                     f"(conf={result.confidence:.2f})",
                     extra={"part_id": result.part_id,
                            "confidence": result.confidence})
        else:
            log.info(f"Low confidence ({result.confidence:.2f}): {result.part_name}",
                     extra={"confidence": result.confidence})
            self.failed_classifications += 1
            result.confidence = 0

        return result

    def _classify_single(self, image: np.ndarray) -> ClassificationResult:
        """Classify a single image via API with retries.

        Args:
            image: BGR numpy array.

        Returns:
            ClassificationResult (may have low confidence).
        """
        if CV2_AVAILABLE:
            _, jpeg_buf = cv2.imencode(".jpg", image,
                                        [cv2.IMWRITE_JPEG_QUALITY, 90])
            image_bytes = jpeg_buf.tobytes()
        else:
            image_bytes = b"\xff\xd8\xff\xe0"

        for attempt in range(self.retry_count + 1):
            try:
                response = self._send_request(image_bytes)
                if response is not None:
                    return self._parse_response(response)
            except Exception as e:
                log.warning(f"Attempt {attempt+1} failed: {e}",
                            extra={"error": str(e)})
                if attempt < self.retry_count:
                    time.sleep(1)

        log.warning("All API attempts failed")
        return ClassificationResult()

    def _send_request(self, image_bytes: bytes) -> Optional[dict]:
        """POST image to Brickognize API.

        Args:
            image_bytes: JPEG-encoded image bytes.

        Returns:
            Parsed JSON response dict, or None on error.
        """
        files = {
            "query_image": ("brick.jpg", io.BytesIO(image_bytes), "image/jpeg")
        }

        start_time = time.time()
        response = self._session.post(
            self.api_url, files=files, timeout=self.timeout
        )
        elapsed = time.time() - start_time
        log.debug(f"API response: {response.status_code} in {elapsed:.1f}s",
                  extra={"elapsed": round(elapsed, 2)})

        if response.status_code == 200:
            return response.json()
        else:
            log.warning(f"API error: {response.status_code} "
                        f"{response.text[:200]}")
            return None

    def _parse_response(self, data: dict) -> ClassificationResult:
        """Parse Brickognize API response into a ClassificationResult.

        Args:
            data: Raw API response JSON.

        Returns:
            Populated ClassificationResult.
        """
        items = data.get("items", [])
        if not items:
            return ClassificationResult(raw_response=data)

        top = items[0]
        return ClassificationResult(
            part_id=top.get("id", ""),
            part_name=top.get("name", ""),
            color=top.get("color", ""),
            confidence=float(top.get("score", 0)),
            category=self._extract_category(top.get("name", "")),
            image_url=top.get("img_url", ""),
            alternatives=[
                {
                    "part_id": item.get("id", ""),
                    "part_name": item.get("name", ""),
                    "confidence": float(item.get("score", 0)),
                }
                for item in items[1:4]
            ],
            raw_response=data,
        )

    def _extract_category(self, name: str) -> str:
        """Extract a broad category from the part name for bin assignment.

        Args:
            name: Full part name from Brickognize.

        Returns:
            Category string matching config.yaml bin_assignments keys.
        """
        name_lower = name.lower()

        category_keywords = [
            ("Technic Beam", ["technic beam", "technic liftarm"]),
            ("Technic Pin", ["technic pin"]),
            ("Technic Axle", ["technic axle"]),
            ("Technic", ["technic"]),
            ("Minifig", ["minifig", "mini fig"]),
            ("Baseplate", ["baseplate", "base plate"]),
            ("Wheel", ["wheel"]),
            ("Tire", ["tire", "tyre"]),
            ("Window", ["window"]),
            ("Door", ["door"]),
            ("Slope", ["slope"]),
            ("Arch", ["arch"]),
            ("Wedge", ["wedge"]),
            ("Hinge", ["hinge"]),
            ("Clip", ["clip"]),
            ("Bar", [" bar "]),
            ("Panel", ["panel"]),
            ("Tile", ["tile"]),
            ("Round", ["round"]),
            ("Cone", ["cone"]),
            ("Cylinder", ["cylinder"]),
            ("Plate 2 x 8", ["plate 2 x 8"]),
            ("Plate 2 x 6", ["plate 2 x 6"]),
            ("Plate 2 x 4", ["plate 2 x 4"]),
            ("Plate 2 x", ["plate 2 x"]),
            ("Plate 1 x", ["plate 1 x"]),
            ("Brick 2 x 8", ["brick 2 x 8"]),
            ("Brick 2 x 6", ["brick 2 x 6"]),
            ("Brick 2 x 4", ["brick 2 x 4"]),
            ("Brick 2 x", ["brick 2 x"]),
            ("Brick 1 x", ["brick 1 x"]),
            ("Decorated", ["decorated", "printed", "pattern"]),
            ("Modified", ["modified"]),
            ("Flag", ["flag"]),
        ]

        for category, keywords in category_keywords:
            for kw in keywords:
                if kw in name_lower:
                    return category

        return "Other"

    @property
    def stats(self) -> dict:
        """Classification statistics dictionary."""
        s: dict = {
            "total": self.total_classifications,
            "successful": self.successful_classifications,
            "failed": self.failed_classifications,
            "review": self.review_classifications,
            "accuracy": (self.successful_classifications /
                        max(1, self.total_classifications) * 100),
        }
        if self.local_cache_enabled:
            s["cache_hits"] = self.cache_hits
            s["cache_misses"] = self.cache_misses
            if self.cache_hits + self.cache_misses > 0:
                s["cache_hit_rate"] = (self.cache_hits /
                                      (self.cache_hits + self.cache_misses) * 100)
        return s
