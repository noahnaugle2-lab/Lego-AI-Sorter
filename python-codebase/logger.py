"""
LEGO AI Sorting Machine — Structured Logging
Provides a centralized, structured logger with:
  - Console output (colored by level)
  - Rotating file output (logs/sorter.log, max 5MB x 5 files)
  - Per-module child loggers
  - JSON-formatted file entries for easy parsing

Usage:
    from logger import get_logger
    log = get_logger("classifier")
    log.info("Identified part", extra={"part_id": "3001", "confidence": 0.92})
"""
import os
import sys
import json
import logging
import logging.handlers
from datetime import datetime, timezone
from typing import Optional


# ── LOG DIRECTORY ────────────────────────────────────────────
LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
LOG_FILE = os.path.join(LOG_DIR, "sorter.log")
MAX_BYTES = 5 * 1024 * 1024  # 5 MB per file
BACKUP_COUNT = 5              # Keep 5 rotated files


# ── JSON FORMATTER (for file output) ────────────────────────
class JSONFormatter(logging.Formatter):
    """Formats log records as single-line JSON objects."""

    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "ts": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
            "level": record.levelname,
            "module": record.name,
            "msg": record.getMessage(),
        }
        # Include any extra fields passed via extra={}
        for key in ("part_id", "part_name", "confidence", "bin_number",
                     "category", "gate_index", "speed", "error", "elapsed",
                     "cache_hit", "set_num", "sort_mode", "encoder_rpm"):
            val = getattr(record, key, None)
            if val is not None:
                entry[key] = val
        if record.exc_info and record.exc_info[0]:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry)


# ── COLORED CONSOLE FORMATTER ───────────────────────────────
class ColorFormatter(logging.Formatter):
    """Adds ANSI color codes to console log output."""

    COLORS = {
        "DEBUG": "\033[36m",     # Cyan
        "INFO": "\033[32m",      # Green
        "WARNING": "\033[33m",   # Yellow
        "ERROR": "\033[31m",     # Red
        "CRITICAL": "\033[1;31m",  # Bold Red
    }
    RESET = "\033[0m"

    def format(self, record: logging.LogRecord) -> str:
        color = self.COLORS.get(record.levelname, self.RESET)
        prefix = f"{color}[{record.name}]{self.RESET}"
        return f"{prefix} {record.getMessage()}"


# ── SINGLETON SETUP ─────────────────────────────────────────
_initialized = False


def _setup_root_logger(level: int = logging.DEBUG) -> None:
    """Configure root logger with console + rotating file handlers (once)."""
    global _initialized
    if _initialized:
        return
    _initialized = True

    # Create log directory
    os.makedirs(LOG_DIR, exist_ok=True)

    root = logging.getLogger("sorter")
    root.setLevel(level)
    root.propagate = False

    # Console handler (INFO+)
    console = logging.StreamHandler(sys.stdout)
    console.setLevel(logging.INFO)
    console.setFormatter(ColorFormatter())
    root.addHandler(console)

    # Rotating file handler (DEBUG+)
    try:
        file_handler = logging.handlers.RotatingFileHandler(
            LOG_FILE, maxBytes=MAX_BYTES, backupCount=BACKUP_COUNT,
            encoding="utf-8"
        )
        file_handler.setLevel(logging.DEBUG)
        file_handler.setFormatter(JSONFormatter())
        root.addHandler(file_handler)
    except OSError as e:
        console.stream.write(f"[logger] WARNING: Could not create log file: {e}\n")


def get_logger(module_name: str) -> logging.Logger:
    """Get a child logger for a specific module.

    Args:
        module_name: Short name like 'classifier', 'conveyor', 'sorter', etc.

    Returns:
        A logging.Logger instance with structured output.
    """
    _setup_root_logger()
    return logging.getLogger(f"sorter.{module_name}")
