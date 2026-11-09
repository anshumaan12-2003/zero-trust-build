#!/usr/bin/env python3
"""Summarizes what Tetragon recorded for each Week 3 test case.

Usage: python3.12 sensor/experiments/summarize.py evidence
"""
import json
import sys
from collections import Counter
from pathlib import Path


def short_args(args):
    """Turns Tetragon's typed argument list into one readable string."""
    parts = []
    for arg in args:
        for kind, value in arg.items():
            if kind == "sockaddr_arg":
                parts.append(f"{value.get('family')} {value.get('addr')}:{value.get('port')}")
            elif kind == "sock_arg":
                parts.append(f"{value.get('protocol')} {value.get('saddr')}->{value.get('daddr')}:{value.get('dport')}")
            elif kind == "file_arg":
                parts.append(value.get("path", ""))
            elif kind in ("int_arg", "size_arg"):
                parts.append(f"{kind}={value}")
    return ", ".join(parts)


def main(evidence):
    evidence = Path(evidence)
    cases = {p.stem: p.read_text().strip() for p in sorted((evidence / "cases").glob("*.cid"))}
    events = [json.loads(line) for path in sorted((evidence / "sensor").glob("tetragon*.log*"))
              for line in path.open() if line.strip()]

    kinds = Counter(next(iter(k for k in e if k.startswith("process_")), "other") for e in events)
    print(f"{len(events)} events: {dict(kinds)}\n")

    for name, container_id in cases.items():
        print(f"== {name}")
        found = Counter()
        for event in events:
            kprobe = event.get("process_kprobe")
            if not kprobe:
                continue
            docker = kprobe.get("process", {}).get("docker", "")
            if docker and container_id.startswith(docker):
                binary = kprobe["process"].get("binary", "").rsplit("/", 1)[-1]
                found[(kprobe.get("function_name"), binary, short_args(kprobe.get("args", [])))] += 1
        if not found:
            print("   (no hook events)")
        for (function, binary, args), count in sorted(found.items()):
            print(f"   {count:>3} x {function:<28} {binary:<8} {args[:90]}")
        print()


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "evidence")
