"""
LEGO AI Sorting Machine — Web Dashboard
Flask web app for monitoring and controlling the sorting machine.

New in v3:
  - OTA configuration (change settings from dashboard)
  - Sort mode switching
  - Sort history analytics
  - Inventory export (BrickLink / Rebrickable CSV)
  - Review queue for uncertain parts
  - Secondary camera feed
  - Throughput stats
"""
from flask import Flask, render_template, jsonify, Response, request
import json
import time

from logger import get_logger

log = get_logger("web")


def create_app(machine):
    """Create Flask app with reference to the machine controller.

    Args:
        machine: SortingMachine instance.

    Returns:
        Configured Flask app.
    """
    app = Flask(__name__)

    @app.route("/")
    def index():
        return render_template("dashboard.html")

    # ── STATS & DATA ─────────────────────────────────────────

    @app.route("/api/stats")
    def stats():
        return jsonify({
            "inventory": machine.inventory.get_stats(),
            "classifier": machine.classifier.stats,
            "belt_running": machine.conveyor.is_running,
            "state": machine.state,
            "sort_mode": machine.sorter.sort_mode,
            "rescan_attempts": getattr(machine, "rescan_attempts", 0),
            "rescan_successes": getattr(machine, "rescan_successes", 0),
            "api_healthy": getattr(machine, "_api_healthy", True),
            "retry_queue_size": getattr(machine, "_retry_queue", None)
                                and machine._retry_queue.size or 0,
            "encoder_rpm": machine.conveyor.actual_rpm,
        })

    @app.route("/api/recent")
    def recent_parts():
        return jsonify(machine.inventory.get_recent_parts(30))

    @app.route("/api/review")
    def review_parts():
        return jsonify(machine.inventory.get_review_parts(50))

    @app.route("/api/sets")
    def set_progress():
        return jsonify(machine.inventory.get_set_progress())

    @app.route("/api/missing/<set_num>")
    def missing_parts(set_num):
        return jsonify(machine.inventory.get_missing_parts(set_num))

    @app.route("/api/missing/<set_num>/csv")
    def missing_csv(set_num):
        csv_data = machine.inventory.export_missing_csv(set_num)
        return Response(csv_data, mimetype="text/csv",
                       headers={"Content-Disposition":
                                f"attachment; filename=missing_{set_num}.csv"})

    @app.route("/api/sort_history")
    def sort_history():
        hours = request.args.get("hours", 24, type=int)
        return jsonify(machine.inventory.get_sort_history(hours))

    @app.route("/api/throughput")
    def throughput():
        return jsonify(machine.inventory.get_throughput_stats())

    # ── CONTROLS ─────────────────────────────────────────────

    @app.route("/api/control/start", methods=["POST"])
    def control_start():
        machine.start()
        return jsonify({"status": "started"})

    @app.route("/api/control/stop", methods=["POST"])
    def control_stop():
        machine.stop()
        return jsonify({"status": "stopped"})

    @app.route("/api/control/pause", methods=["POST"])
    def control_pause():
        machine.conveyor.pause()
        return jsonify({"status": "paused"})

    @app.route("/api/control/resume", methods=["POST"])
    def control_resume():
        machine.conveyor.resume()
        return jsonify({"status": "resumed"})

    @app.route("/api/control/speed", methods=["POST"])
    def control_speed():
        try:
            speed = float(request.json.get("speed", 35))
        except (TypeError, ValueError):
            return jsonify({"status": "error",
                           "message": "speed must be a number"}), 400
        speed = max(5.0, min(100.0, speed))
        machine.conveyor.set_speed(speed)
        return jsonify({"status": "ok", "speed": speed})

    @app.route("/api/control/sort_mode", methods=["POST"])
    def set_sort_mode():
        mode = request.json.get("mode", "part")
        if machine.sorter.set_sort_mode(mode):
            return jsonify({"status": "ok", "mode": mode})
        return jsonify({"status": "error",
                       "message": f"Invalid mode: {mode}"}), 400

    @app.route("/api/control/test_bin/<int:bin_num>", methods=["POST"])
    def test_bin(bin_num):
        if bin_num < 0 or bin_num >= machine.sorter.num_bins:
            return jsonify({"status": "error",
                           "message": "invalid bin number"}), 400
        machine.sorter.test_bin(bin_num)
        return jsonify({"status": "ok", "bin": bin_num})

    @app.route("/api/control/test_gates", methods=["POST"])
    def test_gates():
        machine.sorter.test_all_gates()
        return jsonify({"status": "ok"})

    @app.route("/api/control/update_background", methods=["POST"])
    def update_bg():
        machine.scanner.update_background()
        return jsonify({"status": "ok"})

    @app.route("/api/load_set", methods=["POST"])
    def load_set():
        set_num = request.json.get("set_num", "")
        success = machine.inventory.load_set(set_num)
        return jsonify({"status": "ok" if success else "error",
                       "set": set_num})

    # ── RECLASSIFY ───────────────────────────────────────────

    @app.route("/api/reclassify/<int:part_db_id>", methods=["POST"])
    def reclassify(part_db_id):
        new_bin = request.json.get("new_bin")
        if new_bin is None:
            return jsonify({"status": "error",
                           "message": "new_bin required"}), 400
        try:
            new_bin = int(new_bin)
        except (TypeError, ValueError):
            return jsonify({"status": "error",
                           "message": "new_bin must be an integer"}), 400
        if new_bin < 0 or new_bin >= machine.sorter.num_bins:
            return jsonify({"status": "error",
                           "message": f"new_bin must be 0-{machine.sorter.num_bins - 1}"}), 400
        try:
            original = machine.inventory.update_part_bin(part_db_id, new_bin)
            machine.sorter.route_to_bin(new_bin)

            # Feed correction back to local cache for learning
            if (machine.classifier.local_cache_enabled and
                    machine.classifier.local_cache and original):
                log.info(f"Correction feedback: part {part_db_id} -> bin {new_bin}")

            return jsonify({"status": "ok", "part_db_id": part_db_id,
                           "new_bin": new_bin})
        except Exception as e:
            return jsonify({"status": "error", "message": str(e)}), 500

    # ── CONFIDENCE & BINS ────────────────────────────────────

    @app.route("/api/confidence_histogram", methods=["GET"])
    def confidence_histogram():
        try:
            recent_parts = machine.inventory.get_recent_parts(200)
            buckets = ["0-10%", "10-20%", "20-30%", "30-40%", "40-50%",
                      "50-60%", "60-70%", "70-80%", "80-90%", "90-100%"]
            counts = [0] * 10
            for part in recent_parts:
                conf = part.get("confidence", 0)
                bucket_idx = min(int(conf * 10), 9)
                counts[bucket_idx] += 1
            return jsonify({"buckets": buckets, "counts": counts})
        except Exception as e:
            return jsonify({"status": "error", "message": str(e)}), 500

    @app.route("/api/bin_warnings", methods=["GET"])
    def bin_warnings():
        try:
            bin_counts = machine.sorter.get_bin_counts()
            warnings = machine.sorter.get_bin_fill_warnings(threshold=50)
            return jsonify({"bin_counts": bin_counts, "warnings": warnings})
        except Exception as e:
            return jsonify({"status": "error", "message": str(e)}), 500

    @app.route("/api/reset_bin/<int:bin_num>", methods=["POST"])
    def reset_bin(bin_num):
        try:
            machine.sorter.reset_bin_count(bin_num)
            return jsonify({"status": "ok", "bin": bin_num})
        except Exception as e:
            return jsonify({"status": "error", "message": str(e)}), 500

    # ── OTA CONFIGURATION ────────────────────────────────────

    @app.route("/api/config", methods=["GET"])
    def get_config():
        """Return current config (excluding sensitive keys)."""
        safe_config = {}
        for section, values in machine.config.items():
            if isinstance(values, dict):
                safe_config[section] = {
                    k: v for k, v in values.items()
                    if "key" not in k.lower() and "secret" not in k.lower()
                }
            else:
                safe_config[section] = values
        return jsonify(safe_config)

    @app.route("/api/config", methods=["POST"])
    def update_config():
        """Update a config value. Body: {section, key, value}."""
        data = request.json or {}
        section = data.get("section")
        key = data.get("key")
        value = data.get("value")

        if not section or not key:
            return jsonify({"status": "error",
                           "message": "section and key required"}), 400

        # Block editing sensitive keys via API
        if "key" in key.lower() or "secret" in key.lower():
            return jsonify({"status": "error",
                           "message": "Cannot edit sensitive keys via API"}), 403

        success = machine.update_config(section, key, value)
        return jsonify({"status": "ok" if success else "error",
                       "section": section, "key": key, "value": value})

    # ── EXPORT ───────────────────────────────────────────────

    @app.route("/api/export/inventory")
    def export_inventory():
        csv_data = machine.inventory.export_inventory_csv()
        return Response(csv_data, mimetype="text/csv",
                       headers={"Content-Disposition":
                                "attachment; filename=lego_inventory.csv"})

    @app.route("/api/export/rebrickable")
    def export_rebrickable():
        csv_data = machine.inventory.export_rebrickable_csv()
        return Response(csv_data, mimetype="text/csv",
                       headers={"Content-Disposition":
                                "attachment; filename=rebrickable_import.csv"})

    # ── VIDEO FEEDS ──────────────────────────────────────────

    @app.route("/video_feed")
    def video_feed():
        """Live MJPEG stream from the primary scanner camera."""
        def generate():
            while True:
                jpeg = machine.scanner.get_frame_jpeg()
                if jpeg:
                    yield (b"--frame\r\n"
                           b"Content-Type: image/jpeg\r\n\r\n" +
                           jpeg + b"\r\n")
                time.sleep(0.1)
        return Response(generate(),
                       mimetype="multipart/x-mixed-replace; boundary=frame")

    @app.route("/video_feed_secondary")
    def video_feed_secondary():
        """Live MJPEG stream from the secondary (side-view) camera."""
        def generate():
            while True:
                jpeg = machine.scanner.get_secondary_jpeg()
                if jpeg:
                    yield (b"--frame\r\n"
                           b"Content-Type: image/jpeg\r\n\r\n" +
                           jpeg + b"\r\n")
                time.sleep(0.1)
        return Response(generate(),
                       mimetype="multipart/x-mixed-replace; boundary=frame")

    return app
