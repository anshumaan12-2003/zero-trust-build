#!/usr/bin/env python3
"""Turns one judged build's evidence folder into a small JSON record.

Usage: measure/record-run.py <evidence-dir> <run-label> <output.json>

Records the verdict, the failing and warning rules, the evidence size, the
number of sensor events, and every Tetragon counter whose name says events
were lost or missed. measure/summarize.py combines the records.
"""
import json
import sys
from pathlib import Path


def counters(metrics_text):
    """Sums Prometheus counters about lost or missed events, by metric name."""
    totals = {}
    for line in metrics_text.splitlines():
        if not line or line.startswith("#"):
            continue
        name_and_labels, _, value = line.rpartition(" ")
        name = name_and_labels.split("{")[0]
        if "lost" in name or "missed" in name:
            try:
                totals[name] = totals.get(name, 0) + float(value)
            except ValueError:
                continue
    return totals


def size(path):
    path = Path(path)
    if path.is_file():
        return path.stat().st_size
    return sum(f.stat().st_size for f in path.rglob("*") if f.is_file())


def main():
    evidence, label, output = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
    verdict = json.loads((evidence / "report" / "verdict.json").read_text())
    sensor = evidence / "sensor"
    events = sum(
        1 for log in sensor.glob("tetragon*.log*") for line in log.open(errors="replace") if line.strip()
    )
    metrics = sensor / "metrics.prom"
    record = {
        "run": label,
        "verdict": verdict["verdict"],
        "fail_rules": sorted({f["rule"] for f in verdict["findings"] if f["severity"] == "fail"}),
        "warnings": [f["detail"] for f in verdict["findings"] if f["severity"] == "warn"],
        "evidence_bytes": size(evidence) - size(evidence / "report"),
        "sensor_log_bytes": sum(size(log) for log in sensor.glob("tetragon*.log*")),
        "build_output_bytes": size(evidence / "dist.tar"),
        "sensor_events": events,
        "metrics_saved": metrics.exists(),
        "lost_or_missed": counters(metrics.read_text()) if metrics.exists() else {},
    }
    output.write_text(json.dumps(record, indent=2))
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    main()
