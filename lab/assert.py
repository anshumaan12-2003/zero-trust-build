#!/usr/bin/env python3
"""Checks one scenario's verdict against what lab/expected.toml says to expect.

Usage: lab/assert.py <scenario-id> <verdict.json> <expected.toml>

Exit 0 if the verdict and the set of failing rules match the expectation,
1 otherwise. A scenario the lab expects to miss still has to come out exactly
as written down: a documented miss is a result, but a surprise is a bug.
"""
import json
import sys
import tomllib
from pathlib import Path


def main():
    scenario_id, verdict_path, expected_path = sys.argv[1:4]
    expected = tomllib.loads(Path(expected_path).read_text())[scenario_id]
    report = json.loads(Path(verdict_path).read_text())

    want_verdict = expected["verdict"]
    got_verdict = report["verdict"]
    # Only "fail" findings decide the verdict; "warn" findings are noise here.
    got_rules = sorted({f["rule"] for f in report["findings"] if f["severity"] == "fail"})
    want_rules = sorted(expected.get("rules", []))

    ok = got_verdict == want_verdict and got_rules == want_rules
    mark = "PASS" if ok else "FAIL"
    print(f"{mark}: {scenario_id} — {expected.get('note', '')}")
    print(f"      expected verdict={want_verdict} rules={want_rules}")
    print(f"      got      verdict={got_verdict} rules={got_rules}")
    if not ok:
        print(f"      This scenario did not behave as documented. Update the rule "
              f"or the expectation in lab/expected.toml.")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
