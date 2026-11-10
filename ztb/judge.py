#!/usr/bin/env python3
"""Zero Trust Build Pipeline judge: turns raw build evidence into a pass or fail verdict.

The evidence folder is what the build job uploads:
  sensor/tetragon.log*   Tetragon events, including rotated files
  proxy/access.log       Squid's log of every request through the proxy
  nonce.txt              the random value both canaries carry
  builds/sandbox.cid     the sandbox container's full ID
  proxy.ip               the proxy's address on the sandbox network
  dist.tar               the build output
  sensor/metrics.prom    Tetragon's counters, saved just before it stopped
"""
import argparse
import fnmatch
import hashlib
import json
import os
import sys
import tomllib
from pathlib import Path

MEMORY_CALLS = ("sys_ptrace", "sys_process_vm_readv")


def read_events(log_dir):
    """Yield Tetragon JSON events, including rotated log files."""
    for path in sorted(Path(log_dir).glob("tetragon*.log*")):
        with path.open(errors="replace") as handle:
            for line in handle:
                if line.strip():
                    try:
                        yield json.loads(line)
                    except json.JSONDecodeError:
                        yield {"corrupt": True}


def read_proxy_log(path):
    """Yield (result, host) pairs from a Squid access log."""
    log = Path(path)
    if not log.exists():
        return
    for line in log.read_text(errors="replace").splitlines():
        fields = line.split()
        if len(fields) >= 7:
            host = fields[6].split("://")[-1].split("/")[0].split(":")[0]
            yield fields[3], host


def in_sandbox(process, container_id):
    """Tetragon stores the first 31 characters of the container ID."""
    short_id = process.get("docker", "")
    return bool(short_id) and container_id.startswith(short_id)


def matches(value, patterns):
    return any(fnmatch.fnmatch(value, pattern) for pattern in patterns)


def judge(events, proxy_lines, policy, nonce, container_id, proxy_ip):
    findings = []
    canaries = set()
    binaries = set()
    destinations = set()

    def add(rule, severity, detail):
        finding = {"rule": rule, "severity": severity, "detail": detail}
        if finding not in findings:
            findings.append(finding)

    for event in events:
        if event.get("corrupt"):
            add("SENSOR-2", "fail", "Evidence contains an unreadable line")
            continue

        if "process_exec" in event:
            process = event["process_exec"].get("process", {})
            binary = process.get("binary", "")
            arguments = process.get("arguments", "")
            # Only echo counts. The start loop's grep carries the nonce too.
            if binary.endswith("/echo"):
                for stage in ("start", "end"):
                    if arguments == f"ztb-canary-{stage}-{nonce}":
                        canaries.add(stage)
            if not in_sandbox(process, container_id):
                continue
            binaries.add(binary)
            if matches(binary, policy["processes"]["denied"]):
                add("PROC-1", "fail", f"Denied program ran: {binary}")
            elif not matches(binary, policy["processes"]["known"]):
                add("PROC-2", policy["processes"]["unknown_action"],
                    f"Program not seen in clean builds: {binary}")

        kprobe = event.get("process_kprobe")
        if kprobe is None or not in_sandbox(kprobe.get("process", {}), container_id):
            continue
        function = kprobe.get("function_name", "")
        binary = kprobe.get("process", {}).get("binary", "")
        if any(name in function for name in MEMORY_CALLS):
            add("MEM-1", "fail", f"{binary} tried to read another process: {function}")
        for argument in kprobe.get("args", []):
            address = argument.get("sockaddr_arg")
            if address and function == "security_socket_connect":
                ip, port = address.get("addr", ""), address.get("port", 0)
                if ip.startswith("127.") or ip == "::1":
                    continue
                destinations.add(f"{ip}:{port}")
                if ip != proxy_ip:
                    add("NET-1", "fail", f"{binary} tried to connect to {ip}:{port}")
            path = argument.get("file_arg", {}).get("path", "")
            if path and matches(path, policy["files"]["decoys"]):
                add("FILE-1", "fail", f"{binary} read a decoy file: {path}")
            elif path and matches(path, policy["files"]["process_secrets"]):
                add("MEM-2", "fail", f"{binary} read process data: {path}")

    for stage in ("start", "end"):
        if stage not in canaries:
            add("SENSOR-1", "fail", f"The {stage} canary is missing, so the sensor may have been off")

    if not binaries:
        add("SENSOR-4", "fail", "No events matched the sandbox, so the evidence cannot be trusted")

    domains = set()
    proxy_requests = 0
    for result, host in proxy_lines:
        proxy_requests += 1
        domains.add(host)
        if "DENIED" in result:
            add("NET-2", "fail", f"The proxy blocked a request to {host}")
        elif host not in policy["network"]["allowed_domains"]:
            add("NET-3", "fail", f"The proxy allowed an unlisted domain: {host}")
    if proxy_requests == 0:
        add("SENSOR-3", "fail", "The proxy log is empty or missing")

    failed = any(finding["severity"] == "fail" for finding in findings)
    return {
        "verdict": "fail" if failed else "pass",
        "findings": findings,
        "binaries": sorted(binaries),
        "destinations": sorted(destinations),
        "domains": sorted(domains),
    }


def lost_events(metrics_text, counter_names):
    """Fails the build if the sensor may have dropped events.

    counter_names lists the Tetragon counters that count dropped events. If the
    metrics are missing, or none of those counters is in them, the judge can't
    tell, so it fails closed.
    """
    if not counter_names:
        return []
    if not metrics_text:
        return [{"rule": "SENSOR-5", "severity": "fail",
                 "detail": "Tetragon's metrics are missing, so lost events can't be ruled out"}]
    totals = {}
    for line in metrics_text.splitlines():
        if not line or line.startswith("#"):
            continue
        name_and_labels, _, value = line.rpartition(" ")
        name = name_and_labels.split("{")[0]
        if name in counter_names:
            try:
                totals[name] = totals.get(name, 0) + float(value)
            except ValueError:
                totals[name] = float("inf")
    if not totals:
        return [{"rule": "SENSOR-5", "severity": "fail",
                 "detail": "None of the lost-event counters is in Tetragon's metrics"}]
    return [{"rule": "SENSOR-5", "severity": "fail",
             "detail": f"The sensor lost events: {name} = {total:g}"}
            for name, total in sorted(totals.items()) if total > 0]


def read_text(path):
    """Missing small files become empty strings, so the rules above fail closed."""
    file = Path(path)
    return file.read_text().strip() if file.exists() else ""


def sha256(path):
    file = Path(path)
    return hashlib.sha256(file.read_bytes()).hexdigest() if file.exists() else None


def build_predicate(report, policy_path, dist_path):
    """Follows the in-toto runtime-trace v0.2 predicate."""
    repo = os.environ.get("GITHUB_REPOSITORY", "local/test")
    run_id = os.environ.get("GITHUB_RUN_ID", "0")
    attempt = os.environ.get("GITHUB_RUN_ATTEMPT", "1")
    network = [{"hostname": domain, "protocol": "tcp"} for domain in report["domains"]]
    return {
        "monitor": {"type": "https://github.com/cilium/tetragon/v1.8.0"},
        "monitoredProcess": {
            "hostID": "https://github.com",
            "type": "https://actions.github.io/buildtypes/workflow/v1",
            "event": f"https://github.com/{repo}/actions/runs/{run_id}/attempts/{attempt}",
        },
        "monitorLog": {
            "process": [{"processBinary": binary} for binary in report["binaries"]],
            "network": network,
        },
        "ztb": {
            "verdict": report["verdict"],
            "findings": report["findings"],
            "policySha256": sha256(policy_path),
            "distSha256": sha256(dist_path),
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--evidence", required=True, help="evidence folder from the build job")
    parser.add_argument("--policy", required=True)
    parser.add_argument("--output", required=True, help="folder for verdict.json and predicate.json")
    args = parser.parse_args()

    evidence = Path(args.evidence)
    dist = evidence / "dist.tar"
    policy = tomllib.loads(Path(args.policy).read_text())
    nonce = read_text(evidence / "nonce.txt")
    report = judge(
        read_events(evidence / "sensor"),
        read_proxy_log(evidence / "proxy" / "access.log"),
        policy,
        # An empty nonce would make "ztb-canary-start-" match anything.
        nonce or "missing-nonce",
        read_text(evidence / "builds" / "sandbox.cid") or "missing-container-id",
        read_text(evidence / "proxy.ip"),
    )

    for finding in lost_events(read_text(evidence / "sensor" / "metrics.prom"),
                               policy.get("sensor", {}).get("lost_event_counters", [])):
        report["verdict"] = "fail"
        report["findings"].append(finding)

    if not dist.exists():
        report["verdict"] = "fail"
        report["findings"].append(
            {"rule": "BUILD-1", "severity": "fail", "detail": "The build produced no output"})

    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    (output / "verdict.json").write_text(json.dumps(report, indent=2))
    predicate = build_predicate(report, args.policy, dist)
    (output / "predicate.json").write_text(json.dumps(predicate, indent=2))

    print(f"Verdict: {report['verdict'].upper()}")
    for finding in report["findings"]:
        print(f"  [{finding['severity']}] {finding['rule']}: {finding['detail']}")
    sys.exit(0 if report["verdict"] == "pass" else 1)


if __name__ == "__main__":
    main()
