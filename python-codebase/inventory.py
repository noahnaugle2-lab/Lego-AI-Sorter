"""
LEGO AI Sorting Machine — Inventory Tracker
SQLite database for tracking sorted parts + Rebrickable API
for set completion tracking.

Includes sort history analytics and BrickLink/Rebrickable CSV export.
"""
import sqlite3
import time
import csv
import io
from typing import Optional, List, Dict
from pathlib import Path

import requests

from logger import get_logger

log = get_logger("inventory")


class Inventory:
    """SQLite-backed inventory with Rebrickable integration and analytics.

    Attributes:
        db_path: Path to the SQLite database file.
        target_sets: List of Rebrickable set numbers to track.
    """

    def __init__(self, config: dict, db_path: str = "inventory.db") -> None:
        self.db_path: str = db_path
        self.rebrickable_key: str = config.get("rebrickable", {}).get("api_key", "")
        self.target_sets: list = config.get("rebrickable", {}).get("target_sets", [])
        self._conn: Optional[sqlite3.Connection] = None
        self._init_db()
        log.info(f"Database: {db_path}")

    def _init_db(self) -> None:
        """Create tables if they don't exist."""
        self._conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        c = self._conn.cursor()

        c.execute("""
            CREATE TABLE IF NOT EXISTS sorted_parts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                part_id TEXT NOT NULL,
                part_name TEXT,
                color TEXT,
                category TEXT,
                confidence REAL,
                bin_number INTEGER,
                timestamp REAL,
                image_url TEXT,
                needs_review INTEGER DEFAULT 0,
                sort_mode TEXT DEFAULT 'part'
            )
        """)

        c.execute("""
            CREATE TABLE IF NOT EXISTS set_inventories (
                set_num TEXT NOT NULL,
                part_id TEXT NOT NULL,
                color TEXT,
                quantity INTEGER DEFAULT 1,
                found INTEGER DEFAULT 0,
                PRIMARY KEY (set_num, part_id, color)
            )
        """)

        c.execute("""
            CREATE TABLE IF NOT EXISTS sets (
                set_num TEXT PRIMARY KEY,
                name TEXT,
                year INTEGER,
                num_parts INTEGER,
                image_url TEXT
            )
        """)

        # Sort history for analytics (hourly aggregates)
        c.execute("""
            CREATE TABLE IF NOT EXISTS sort_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                hour_ts INTEGER NOT NULL,
                total_count INTEGER DEFAULT 0,
                identified_count INTEGER DEFAULT 0,
                review_count INTEGER DEFAULT 0,
                avg_confidence REAL DEFAULT 0,
                UNIQUE(hour_ts)
            )
        """)

        # Correction log for learning feedback
        c.execute("""
            CREATE TABLE IF NOT EXISTS corrections (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                part_db_id INTEGER,
                old_bin INTEGER,
                new_bin INTEGER,
                timestamp REAL,
                FOREIGN KEY(part_db_id) REFERENCES sorted_parts(id)
            )
        """)

        self._conn.commit()

    def log_part(self, part_id: str, part_name: str, color: str,
                 category: str, confidence: float, bin_number: int,
                 image_url: str = "", needs_review: bool = False,
                 sort_mode: str = "part") -> int:
        """Log a sorted part to the database.

        Args:
            part_id: Brickognize part ID.
            part_name: Human-readable part name.
            color: Part color.
            category: Category for bin assignment.
            confidence: Classification confidence 0-1.
            bin_number: Assigned bin.
            image_url: URL to part image.
            needs_review: True if part was routed to review bin.
            sort_mode: Active sort mode when classified.

        Returns:
            Database row ID of the inserted record.
        """
        c = self._conn.cursor()
        c.execute("""
            INSERT INTO sorted_parts
            (part_id, part_name, color, category, confidence, bin_number,
             timestamp, image_url, needs_review, sort_mode)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (part_id, part_name, color, category, confidence, bin_number,
              time.time(), image_url, int(needs_review), sort_mode))
        row_id = c.lastrowid
        self._conn.commit()

        self._update_set_tracking(part_id, color)
        self._update_hourly_stats(confidence, needs_review)

        log.info(f"Logged: {part_id} '{part_name}' -> bin {bin_number}",
                 extra={"part_id": part_id, "bin_number": bin_number,
                        "confidence": confidence})
        return row_id

    def _update_set_tracking(self, part_id: str, color: str) -> None:
        """Mark a part as found in any tracked sets."""
        c = self._conn.cursor()
        c.execute("""
            UPDATE set_inventories
            SET found = MIN(found + 1, quantity)
            WHERE part_id = ? AND (color = ? OR color = '')
            AND found < quantity
        """, (part_id, color))
        self._conn.commit()

    def _update_hourly_stats(self, confidence: float,
                              needs_review: bool) -> None:
        """Update hourly aggregate statistics for sort history."""
        hour_ts = int(time.time()) // 3600 * 3600  # Round to hour
        c = self._conn.cursor()
        c.execute("""
            INSERT INTO sort_history (hour_ts, total_count, identified_count,
                                      review_count, avg_confidence)
            VALUES (?, 1, ?, ?, ?)
            ON CONFLICT(hour_ts) DO UPDATE SET
                total_count = total_count + 1,
                identified_count = identified_count + ?,
                review_count = review_count + ?,
                avg_confidence = (avg_confidence * total_count + ?) / (total_count + 1)
        """, (hour_ts,
              1 if confidence > 0 else 0,
              1 if needs_review else 0,
              confidence,
              1 if confidence > 0 else 0,
              1 if needs_review else 0,
              confidence))
        self._conn.commit()

    # ── STATISTICS ───────────────────────────────────────────

    def get_stats(self) -> dict:
        """Get overall sorting statistics.

        Returns:
            Dictionary with total_sorted, identified, unique_parts,
            avg_confidence, parts_per_minute, top_categories, etc.
        """
        c = self._conn.cursor()

        c.execute("SELECT COUNT(*) FROM sorted_parts")
        total = c.fetchone()[0]

        c.execute("SELECT COUNT(*) FROM sorted_parts WHERE confidence > 0")
        identified = c.fetchone()[0]

        c.execute("SELECT COUNT(DISTINCT part_id) FROM sorted_parts")
        unique = c.fetchone()[0]

        c.execute("""
            SELECT category, COUNT(*) as count
            FROM sorted_parts
            GROUP BY category
            ORDER BY count DESC
            LIMIT 10
        """)
        top_categories = [dict(row) for row in c.fetchall()]

        c.execute("SELECT AVG(confidence) FROM sorted_parts WHERE confidence > 0")
        avg_conf = c.fetchone()[0] or 0

        c.execute("SELECT COUNT(*) FROM sorted_parts WHERE needs_review = 1")
        review_count = c.fetchone()[0]

        # Parts per minute (last 10 minutes)
        ten_min_ago = time.time() - 600
        c.execute("SELECT COUNT(*) FROM sorted_parts WHERE timestamp > ?",
                  (ten_min_ago,))
        recent = c.fetchone()[0]
        parts_per_min = recent / 10.0

        # Top colors
        c.execute("""
            SELECT color, COUNT(*) as count
            FROM sorted_parts WHERE color != ''
            GROUP BY color ORDER BY count DESC LIMIT 10
        """)
        top_colors = [dict(row) for row in c.fetchall()]

        return {
            "total_sorted": total,
            "identified": identified,
            "unknown": total - identified,
            "unique_parts": unique,
            "avg_confidence": round(avg_conf, 2),
            "parts_per_minute": round(parts_per_min, 1),
            "top_categories": top_categories,
            "top_colors": top_colors,
            "review_count": review_count,
        }

    def get_sort_history(self, hours: int = 24) -> List[dict]:
        """Get hourly sort history for analytics charts.

        Args:
            hours: Number of hours of history to return.

        Returns:
            List of hourly aggregate dicts sorted by timestamp.
        """
        cutoff = int(time.time()) - (hours * 3600)
        c = self._conn.cursor()
        c.execute("""
            SELECT hour_ts, total_count, identified_count, review_count,
                   avg_confidence
            FROM sort_history
            WHERE hour_ts > ?
            ORDER BY hour_ts ASC
        """, (cutoff,))
        return [dict(row) for row in c.fetchall()]

    def get_throughput_stats(self) -> dict:
        """Get throughput metrics for the analytics dashboard.

        Returns:
            Dictionary with hourly, daily rates and peak throughput.
        """
        c = self._conn.cursor()
        now = time.time()

        # Last hour
        c.execute("SELECT COUNT(*) FROM sorted_parts WHERE timestamp > ?",
                  (now - 3600,))
        last_hour = c.fetchone()[0]

        # Last 24 hours
        c.execute("SELECT COUNT(*) FROM sorted_parts WHERE timestamp > ?",
                  (now - 86400,))
        last_day = c.fetchone()[0]

        # Peak hour
        c.execute("""
            SELECT MAX(total_count) FROM sort_history
        """)
        peak = c.fetchone()[0] or 0

        # Session duration (time from first to last sorted part)
        c.execute("SELECT MIN(timestamp), MAX(timestamp) FROM sorted_parts")
        row = c.fetchone()
        session_minutes = 0
        if row[0] and row[1]:
            session_minutes = round((row[1] - row[0]) / 60, 1)

        return {
            "last_hour": last_hour,
            "last_24h": last_day,
            "peak_hour": peak,
            "session_minutes": session_minutes,
            "avg_per_hour": round(last_day / max(1, min(24, session_minutes / 60)), 1),
        }

    def get_recent_parts(self, limit: int = 20) -> List[dict]:
        """Get the most recently sorted parts.

        Args:
            limit: Maximum number of parts to return.

        Returns:
            List of part dictionaries ordered by most recent first.
        """
        c = self._conn.cursor()
        c.execute("""
            SELECT * FROM sorted_parts
            ORDER BY timestamp DESC
            LIMIT ?
        """, (limit,))
        return [dict(row) for row in c.fetchall()]

    def get_review_parts(self, limit: int = 50) -> List[dict]:
        """Get parts that need manual review.

        Args:
            limit: Maximum number of parts to return.

        Returns:
            List of part dictionaries marked for review.
        """
        c = self._conn.cursor()
        c.execute("""
            SELECT * FROM sorted_parts
            WHERE needs_review = 1
            ORDER BY timestamp DESC
            LIMIT ?
        """, (limit,))
        return [dict(row) for row in c.fetchall()]

    # ── REBRICKABLE INTEGRATION ──────────────────────────────

    def load_set(self, set_num: str) -> bool:
        """Fetch a set's parts inventory from Rebrickable and store it.

        Args:
            set_num: Rebrickable set number (e.g. "42100-1").

        Returns:
            True if set was loaded successfully.
        """
        if not self.rebrickable_key:
            log.warning("No Rebrickable API key configured")
            return False

        base_url = "https://rebrickable.com/api/v3"
        headers = {"Authorization": f"key {self.rebrickable_key}"}

        try:
            r = requests.get(f"{base_url}/lego/sets/{set_num}/",
                           headers=headers, timeout=10)
            if r.status_code != 200:
                log.warning(f"Set {set_num} not found: {r.status_code}",
                           extra={"set_num": set_num})
                return False

            set_data = r.json()
            c = self._conn.cursor()
            c.execute("""
                INSERT OR REPLACE INTO sets (set_num, name, year, num_parts, image_url)
                VALUES (?, ?, ?, ?, ?)
            """, (set_num, set_data.get("name", ""),
                  set_data.get("year", 0),
                  set_data.get("num_parts", 0),
                  set_data.get("set_img_url", "")))

            page = 1
            while True:
                r = requests.get(
                    f"{base_url}/lego/sets/{set_num}/parts/",
                    headers=headers,
                    params={"page": page, "page_size": 100},
                    timeout=10
                )
                if r.status_code != 200:
                    break

                data = r.json()
                for item in data.get("results", []):
                    part = item.get("part", {})
                    c.execute("""
                        INSERT OR REPLACE INTO set_inventories
                        (set_num, part_id, color, quantity, found)
                        VALUES (?, ?, ?, ?,
                                COALESCE((SELECT found FROM set_inventories
                                         WHERE set_num=? AND part_id=? AND color=?), 0))
                    """, (set_num, part.get("part_num", ""),
                          str(item.get("color", {}).get("id", "")),
                          item.get("quantity", 1),
                          set_num, part.get("part_num", ""),
                          str(item.get("color", {}).get("id", ""))))

                if not data.get("next"):
                    break
                page += 1

            self._conn.commit()
            log.info(f"Loaded set {set_num}: {set_data.get('name')}",
                     extra={"set_num": set_num})
            return True

        except Exception as e:
            log.error(f"Error loading set: {e}", extra={"error": str(e)})
            return False

    def get_set_progress(self) -> List[dict]:
        """Get completion progress for all tracked sets.

        Returns:
            List of set progress dictionaries.
        """
        c = self._conn.cursor()
        c.execute("SELECT * FROM sets")
        sets_info = [dict(row) for row in c.fetchall()]

        results = []
        for s in sets_info:
            set_num = s["set_num"]
            c.execute("""
                SELECT
                    SUM(quantity) as total_needed,
                    SUM(found) as total_found,
                    COUNT(*) as unique_parts,
                    SUM(CASE WHEN found >= quantity THEN 1 ELSE 0 END) as complete_parts
                FROM set_inventories
                WHERE set_num = ?
            """, (set_num,))
            progress = dict(c.fetchone())
            results.append({**s, **progress})

        return results

    def get_missing_parts(self, set_num: str) -> List[dict]:
        """Get list of parts still missing from a set.

        Args:
            set_num: Rebrickable set number.

        Returns:
            List of missing part dictionaries.
        """
        c = self._conn.cursor()
        c.execute("""
            SELECT part_id, color, quantity, found, (quantity - found) as missing
            FROM set_inventories
            WHERE set_num = ? AND found < quantity
            ORDER BY missing DESC
        """, (set_num,))
        return [dict(row) for row in c.fetchall()]

    def export_missing_csv(self, set_num: str) -> str:
        """Export missing parts as a BrickLink-compatible CSV.

        Args:
            set_num: Rebrickable set number.

        Returns:
            CSV string with header row.
        """
        missing = self.get_missing_parts(set_num)
        output = io.StringIO()
        writer = csv.writer(output)
        writer.writerow(["Part ID", "Color", "Quantity Needed"])
        for part in missing:
            writer.writerow([part["part_id"], part["color"], part["missing"]])
        return output.getvalue()

    def export_inventory_csv(self) -> str:
        """Export full sorted inventory as CSV (for BrickLink upload).

        Returns:
            CSV string with all sorted parts.
        """
        c = self._conn.cursor()
        c.execute("""
            SELECT part_id, part_name, color, category, COUNT(*) as quantity,
                   AVG(confidence) as avg_confidence
            FROM sorted_parts
            WHERE confidence > 0
            GROUP BY part_id, color
            ORDER BY quantity DESC
        """)
        rows = c.fetchall()

        output = io.StringIO()
        writer = csv.writer(output)
        writer.writerow(["Part ID", "Part Name", "Color", "Category",
                        "Quantity", "Avg Confidence"])
        for row in rows:
            writer.writerow([row["part_id"], row["part_name"], row["color"],
                           row["category"], row["quantity"],
                           f"{row['avg_confidence']:.2f}"])
        return output.getvalue()

    def export_rebrickable_csv(self) -> str:
        """Export inventory in Rebrickable import format.

        Format: Part,Color,Quantity (for bulk import at rebrickable.com).

        Returns:
            CSV string in Rebrickable format.
        """
        c = self._conn.cursor()
        c.execute("""
            SELECT part_id, color, COUNT(*) as quantity
            FROM sorted_parts
            WHERE confidence > 0
            GROUP BY part_id, color
            ORDER BY part_id
        """)
        rows = c.fetchall()

        output = io.StringIO()
        writer = csv.writer(output)
        writer.writerow(["Part", "Color", "Quantity"])
        for row in rows:
            writer.writerow([row["part_id"], row["color"], row["quantity"]])
        return output.getvalue()

    # ── RECLASSIFY / CORRECTIONS ─────────────────────────────

    def update_part_bin(self, part_db_id: int, new_bin: int) -> dict:
        """Update the bin assignment for a previously sorted part.

        Also logs the correction for the feedback learning system.

        Args:
            part_db_id: Database row ID of the part.
            new_bin: New bin number to assign.

        Returns:
            The original part record (for learning feedback).
        """
        c = self._conn.cursor()

        # Get original record for learning feedback
        c.execute("SELECT * FROM sorted_parts WHERE id = ?", (part_db_id,))
        original = c.fetchone()
        original_dict = dict(original) if original else {}

        old_bin = original_dict.get("bin_number", -1)

        c.execute("UPDATE sorted_parts SET bin_number = ?, needs_review = 0 WHERE id = ?",
                  (new_bin, part_db_id))

        # Log correction
        c.execute("""
            INSERT INTO corrections (part_db_id, old_bin, new_bin, timestamp)
            VALUES (?, ?, ?, ?)
        """, (part_db_id, old_bin, new_bin, time.time()))

        self._conn.commit()
        log.info(f"Reclassified part {part_db_id}: bin {old_bin} -> {new_bin}",
                 extra={"bin_number": new_bin})
        return original_dict

    def get_confidence_histogram(self, limit: int = 200) -> dict:
        """Get confidence distribution for the last N classifications.

        Args:
            limit: Number of recent classifications to analyze.

        Returns:
            Dictionary with 'buckets' and 'counts' lists.
        """
        c = self._conn.cursor()
        c.execute("""
            SELECT confidence FROM sorted_parts
            ORDER BY timestamp DESC LIMIT ?
        """, (limit,))
        rows = c.fetchall()

        buckets = [f"{i*10}-{(i+1)*10}%" for i in range(10)]
        counts = [0] * 10

        for row in rows:
            conf = row[0] or 0
            idx = min(int(conf * 10), 9)
            counts[idx] += 1

        return {"buckets": buckets, "counts": counts}

    def cleanup(self) -> None:
        """Close database connection."""
        if self._conn:
            self._conn.close()
        log.info("Database closed")
