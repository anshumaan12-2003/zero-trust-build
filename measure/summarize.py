#!/usr/bin/env python3
"""Combines the raw measurements into results/summary.json.

Usage: measure/summarize.py <raw-dir> <summary.json>

<raw-dir> holds what measure.yml's jobs upload:
  build-times.csv     from measure/time-builds.sh
  gate-times.csv      from measure/time-gate.sh
  clean-*.json        one record per clean build, from measure/record-run.py
The attack-lab numbers come from lab/expected.toml, which the attack-lab
workflow checks scenario by scenario.

Small samples are reported as counts ("0 of 20"), not percentages.
"""
import csv
import json
import os
import statistics
import sys
import tomllib
from datetime import date
from pathlib import Path


def rows(path):
    with Path(path).open() as handle:
        return list(csv.DictReader(handle))


def median(values):
    return round(statistics.median(values), 2) if values else None


def build_times(path):
    data = rows(path)

    def part(kind, name):
        return [float(r["seconds"]) for r in data if r["kind"] == kind and r["part"] == name]

    runs = sorted({r["run"] for r in data})
    secured_totals = [
        sum(float(r["seconds"]) for r in data if r["kind"] == "secured" and r["run"] == run)
        for run in runs
    ]
    plain = part("plain", "build")
    return {
        "runs_each": len(plain),
        "method": "Plain and secured builds alternate on one runner. Plain is the same build "
                  "steps in an ordinary container. Secured is sensor start, the sandboxed build "
                  "through the proxy, and sensor stop. Medians, in seconds.",
        "plain_build_s": median(plain),
        "secured_sensor_start_s": median(part("secured", "sensor-start")),
        "secured_build_s": median(part("secured", "build")),
        "secured_sensor_stop_s": median(part("secured", "sensor-stop")),
        "secured_total_s": median(secured_totals),
        "added_s": round(median(secured_totals) - median(plain), 2),
        "raw_plain_s": [round(v, 2) for v in plain],
        "raw_secured_total_s": [round(v, 2) for v in secured_totals],
    }


def clean_runs(records):
    failed = [r for r in records if r["verdict"] != "pass"]
    warnings = sorted({w for r in records for w in r["warnings"]})
    with_metrics = [r for r in records if r["metrics_saved"]]
    counter_names = sorted({name for r in with_metrics for name in r["lost_or_missed"]})
    return {
        "false_alarms": {
            "clean_runs": len(records),
            "failed": len(failed),
            "summary": f"{len(failed)} of {len(records)} clean builds failed",
            "failed_runs": [{"run": r["run"], "rules": r["fail_rules"]} for r in failed],
            "runs_with_warnings": sum(1 for r in records if r["warnings"]),
            "warnings": warnings,
        },
        "evidence": {
            "median_bytes": median([r["evidence_bytes"] for r in records]),
            "max_bytes": max((r["evidence_bytes"] for r in records), default=None),
            "median_sensor_log_bytes": median([r["sensor_log_bytes"] for r in records]),
            "median_build_output_bytes": median([r["build_output_bytes"] for r in records]),
            "median_sensor_events": median([r["sensor_events"] for r in records]),
        },
        "events_lost": {
            "runs_with_metrics": len(with_metrics),
            "counters": {
                name: max(r["lost_or_missed"].get(name, 0) for r in with_metrics)
                for name in counter_names
            },
            "runs_with_any_loss": sum(
                1 for r in with_metrics if any(v > 0 for v in r["lost_or_missed"].values())
            ),
            "note": "Each counter shows the highest value seen in any run.",
        },
    }


def gate_times(path):
    data = rows(path)
    plain = [float(r["seconds"]) for r in data if r["kind"] == "no-policy"]
    gated = [float(r["seconds"]) for r in data if r["kind"] == "gated"]
    return {
        "runs_each": len(plain),
        "method": "Server-side dry-run pod creation with the image signed by main, on kind. "
                  "First with Kyverno installed but no image policy, then with the gate. "
                  "The first gated call is reported apart, because later calls can use "
                  "Kyverno's cache. Seconds, including kubectl's own start-up.",
        "no_policy_median_s": median(plain),
        "gated_first_call_s": round(gated[0], 2) if gated else None,
        "gated_median_after_first_s": median(gated[1:]),
        "added_median_s": round(median(gated[1:]) - median(plain), 2) if len(gated) > 1 else None,
    }


def attack_lab():
    expected = tomllib.loads(Path("lab/expected.toml").read_text())
    attacks = {k: v for k, v in expected.items() if k.startswith("M")}
    caught = sorted((k for k, v in attacks.items() if v["verdict"] == "fail"), key=lambda k: int(k[1:]))
    passed = sorted((k for k, v in attacks.items() if v["verdict"] == "pass"), key=lambda k: int(k[1:]))
    return {
        "source": "attack-lab workflow, each scenario asserted against lab/expected.toml",
        "scenarios": len(expected),
        "build_attacks": len(attacks),
        "caught": caught,
        "not_caught": passed,
        "summary": f"{len(caught)} of {len(attacks)} build attacks caught; "
                   f"{len(passed)} not caught (M8 has nothing to find, the rest are documented misses)",
        "tampering_caught": sorted(k for k, v in expected.items() if k.startswith("S") and v["verdict"] == "fail"),
        "clean_builds_passing": sorted(k for k, v in expected.items() if k.startswith("B")),
    }


def main():
    raw, output = Path(sys.argv[1]), Path(sys.argv[2])
    records = [json.loads(p.read_text()) for p in sorted(raw.glob("clean-*.json"))]
    repo = os.environ.get("GITHUB_REPOSITORY", "local/test")
    run_id = os.environ.get("GITHUB_RUN_ID", "0")
    summary = {
        "recorded": date.today().isoformat(),
        "source_run": f"https://github.com/{repo}/actions/runs/{run_id}",
        "runner": "GitHub-hosted ubuntu-24.04",
        "build_time": build_times(raw / "build-times.csv"),
        **clean_runs(records),
        "gate_time": gate_times(raw / "gate-times.csv"),
        "attack_lab": attack_lab(),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
