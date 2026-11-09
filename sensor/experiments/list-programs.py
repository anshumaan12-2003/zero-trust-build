#!/usr/bin/env python3
"""Lists the programs and connections Tetragon recorded for each build container.

Usage: python3.12 sensor/experiments/list-programs.py <evidence folder>
The folder must contain sensor/tetragon.log and builds/*.cid.
"""
import json
import sys
from collections import Counter
from pathlib import Path


def main(evidence):
    evidence = Path(evidence)
    builds = {p.stem: p.read_text().strip() for p in sorted((evidence / "builds").glob("*.cid"))}
    lines = [line for path in sorted((evidence / "sensor").glob("tetragon*.log*"))
             for line in path.open() if line.strip()]
    events = [json.loads(line) for line in lines]
    print(f"Log: {len(events)} events, {sum(map(len, lines)) / 1024:.0f} KB\n")

    every_build = None
    for label, container_id in builds.items():
        programs, connections, count, size = Counter(), Counter(), 0, 0
        for line, event in zip(lines, events):
            body = event.get("process_exec") or event.get("process_kprobe") or event.get("process_exit")
            docker = (body or {}).get("process", {}).get("docker", "")
            if not docker or not container_id.startswith(docker):
                continue
            count += 1
            size += len(line)
            if "process_exec" in event:
                programs[body["process"]["binary"]] += 1
            kprobe = event.get("process_kprobe", {})
            if kprobe.get("function_name") == "security_socket_connect":
                for arg in kprobe.get("args", []):
                    address = arg.get("sockaddr_arg")
                    if address:
                        connections[f"{address.get('addr')}:{address.get('port')}"] += 1
        print(f"== {label}: {count} events, {size / 1024:.0f} KB")
        for binary, runs in sorted(programs.items()):
            print(f"   ran {runs:>3} x {binary}")
        for destination, attempts in sorted(connections.items()):
            print(f"   connected {attempts:>3} x {destination}")
        print()
        every_build = set(programs) if every_build is None else every_build & set(programs)

    if every_build:
        print("Programs seen in every build (a starting known list):")
        for binary in sorted(every_build):
            print(f"   {binary}")


if __name__ == "__main__":
    main(sys.argv[1])
