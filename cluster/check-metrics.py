#!/usr/bin/env python3
"""Runs every query on the Grafana dashboard against Prometheus and checks the
gate panels show real data. Standard library only.

Usage: cluster/check-metrics.py <prometheus url> <dashboard.yaml>
"""

import json
import sys
import urllib.parse
import urllib.request

# Panels that must show more than zero once the checks have run.
MUST_BE_ABOVE_ZERO = {
    "Pods allowed by the gate",
    "Pods refused by the gate",
    "Kyverno admission controllers up",
}


def query(base, expr):
    url = f"{base}/api/v1/query?" + urllib.parse.urlencode({"query": expr})
    with urllib.request.urlopen(url, timeout=10) as response:
        body = json.load(response)
    if body.get("status") != "success":
        raise RuntimeError(f"{expr}: {body}")
    return body["data"]["result"]


def dashboard(path):
    # The JSON is the indented block after "ztb-gate.json: |".
    lines = open(path, encoding="utf-8").read().splitlines()
    start = next(i for i, line in enumerate(lines) if line.strip() == "ztb-gate.json: |") + 1
    return json.loads("\n".join(line[4:] for line in lines[start:]))


def main():
    base, path = sys.argv[1], sys.argv[2]
    failures = 0
    for panel in dashboard(path)["panels"]:
        for target in panel["targets"]:
            expr = target["expr"].replace("$__range", "1h")
            result = query(base, expr)
            values = [float(r["value"][1]) for r in result]
            shown = ", ".join(f"{r['metric'] or ''} {float(r['value'][1]):g}".strip() for r in result)
            print(f"{panel['title']}: {shown or 'no data'}")
            if panel["title"] in MUST_BE_ABOVE_ZERO and not any(v > 0 for v in values):
                print("  FAIL: expected more than 0")
                failures += 1
    sys.exit(failures)


if __name__ == "__main__":
    main()
