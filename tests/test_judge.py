"""Tests for the judge and learn commands. Run: python3 -m unittest discover -s tests -v"""
import json
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "tests" / "fixtures"
POLICY_PATH = ROOT / "policy" / "build-policy.toml"
sys.path.insert(0, str(ROOT / "ztb"))

import judge as J  # noqa: E402
import learn as L  # noqa: E402

POLICY = tomllib.loads(POLICY_PATH.read_text())
NONCE = "abc123"
CID = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
SHORT = CID[:31]
PROXY = "172.18.0.2"
# What stop-sensor.sh saves from a sensor that dropped nothing. The Week 5
# fixtures predate the metrics snapshot, so tests add this to them.
CLEAN_METRICS = """# HELP tetragon_observer_ringbuf_events_lost_total Number of perf events Tetragon ringbuf lost.
# TYPE tetragon_observer_ringbuf_events_lost_total counter
tetragon_observer_ringbuf_events_lost_total 0
tetragon_observer_ringbuf_queue_events_lost_total 0
tetragon_missed_prog_probes_total{attach="security_socket_connect",policy="security-socket-connect"} 0
tetragon_missed_link_probes_total 0
"""


def exec_event(binary, docker=SHORT, arguments=""):
    return {"process_exec": {"process": {"binary": binary, "docker": docker, "arguments": arguments}}}


def canary(stage, binary="/bin/echo"):
    return exec_event(binary, docker="", arguments=f"ztb-canary-{stage}-{NONCE}")


def kprobe(function, args, binary="/usr/local/bin/node", docker=SHORT):
    return {"process_kprobe": {"process": {"binary": binary, "docker": docker},
                               "function_name": function, "args": args}}


def connect(ip, port=443, docker=SHORT):
    address = {"sockaddr_arg": {"family": "AF_INET", "addr": ip, "port": port}}
    return kprobe("security_socket_connect", [address, {"int_arg": 16}], docker=docker)


def file_read(path):
    return kprobe("security_file_permission", [{"file_arg": {"path": path}}, {"int_arg": 4}])


CLEAN = [canary("start"), exec_event("/usr/local/bin/node"), exec_event("/usr/bin/sh"),
         connect(PROXY, 3128), connect("127.0.0.11", 53), canary("end")]
OK_PROXY = [("TCP_TUNNEL/200", "registry.npmjs.org")]


def run(events, proxy=OK_PROXY, policy=POLICY, container_id=CID):
    return J.judge(iter(events), iter(proxy), policy, NONCE, container_id, PROXY)


def rules(report):
    return {finding["rule"] for finding in report["findings"]}


def run_cli(evidence, policy=POLICY_PATH):
    output = Path(evidence) / "report"
    result = subprocess.run(
        [sys.executable, str(ROOT / "ztb" / "judge.py"), "--evidence", str(evidence),
         "--policy", str(policy), "--output", str(output)],
        capture_output=True, text=True)
    return result, output


class RulesTest(unittest.TestCase):
    """Each rule on small made-up events."""

    def test_clean_passes(self):
        report = run(CLEAN)
        self.assertEqual(report["verdict"], "pass")
        self.assertEqual(report["findings"], [])

    def test_missing_start_canary(self):
        self.assertIn("SENSOR-1", rules(run(CLEAN[1:])))

    def test_missing_end_canary(self):
        self.assertIn("SENSOR-1", rules(run(CLEAN[:-1])))

    def test_grep_carrying_the_nonce_is_not_a_canary(self):
        events = [canary("start", "/usr/bin/grep")] + CLEAN[1:-1] + [canary("end", "/usr/bin/sudo")]
        self.assertIn("SENSOR-1", rules(run(events)))

    def test_empty_evidence_fails(self):
        self.assertEqual(run([], [])["verdict"], "fail")

    def test_corrupt_line(self):
        self.assertIn("SENSOR-2", rules(run(CLEAN + [{"corrupt": True}])))

    def test_direct_connect(self):
        report = run(CLEAN + [connect("203.0.113.10")])
        self.assertIn("NET-1", rules(report))
        self.assertEqual(report["verdict"], "fail")

    def test_cloud_metadata_address(self):
        self.assertIn("NET-1", rules(run(CLEAN + [connect("169.254.169.254", 80)])))

    def test_proxy_denied(self):
        self.assertIn("NET-2", rules(run(CLEAN, OK_PROXY + [("TCP_DENIED/403", "evil.invalid")])))

    def test_proxy_allowed_unlisted_domain(self):
        self.assertIn("NET-3", rules(run(CLEAN, [("TCP_TUNNEL/200", "other.example")])))

    def test_denied_program(self):
        self.assertIn("PROC-1", rules(run(CLEAN + [exec_event("/usr/bin/curl")])))

    def test_unknown_program_fails(self):
        report = run(CLEAN + [exec_event("/usr/bin/python3")])
        self.assertIn("PROC-2", rules(report))
        self.assertEqual(report["verdict"], "fail")

    def test_unknown_program_only_warns_when_set_to_warn(self):
        policy = {**POLICY, "processes": {**POLICY["processes"], "unknown_action": "warn"}}
        report = run(CLEAN + [exec_event("/usr/bin/python3")], policy=policy)
        self.assertIn("PROC-2", rules(report))
        self.assertEqual(report["verdict"], "pass")

    def test_decoy_read(self):
        self.assertIn("FILE-1", rules(run(CLEAN + [file_read("/tmp/home/.aws/credentials")])))

    def test_proc_mem_read(self):
        self.assertIn("MEM-2", rules(run(CLEAN + [file_read("/proc/4242/mem")])))

    def test_proc_environ_with_stripped_path(self):
        self.assertIn("MEM-2", rules(run(CLEAN + [file_read("/4242/environ")])))

    def test_ptrace_with_arch_prefix(self):
        self.assertIn("MEM-1", rules(run(CLEAN + [kprobe("__x64_sys_ptrace", [{"int_arg": 1}])])))

    def test_process_vm_readv(self):
        self.assertIn("MEM-1", rules(run(CLEAN + [kprobe("__arm64_sys_process_vm_readv", [])])))

    def test_host_events_ignored(self):
        report = run(CLEAN + [exec_event("/usr/bin/curl", docker=""), connect("1.1.1.1", docker="")])
        self.assertEqual(report["verdict"], "pass")

    def test_other_container_ignored(self):
        report = run(CLEAN + [exec_event("/usr/bin/curl", docker="f" * 31)])
        self.assertEqual(report["verdict"], "pass")

    def test_missing_proxy_log_fails_closed(self):
        report = run(CLEAN, J.read_proxy_log("/nonexistent/access.log"))
        self.assertIn("SENSOR-3", rules(report))

    def test_no_sandbox_events_fails_closed(self):
        self.assertIn("SENSOR-4", rules(run([canary("start"), canary("end")])))

    def test_wrong_container_id_fails_closed(self):
        self.assertIn("SENSOR-4", rules(run(CLEAN, container_id="ffff" + CID[4:])))


class RealEvidenceTest(unittest.TestCase):
    """The judge on real evidence from Week 5's pipeline run 42665549829."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)

    def evidence(self, name, with_dist=True, metrics=CLEAN_METRICS):
        folder = self.tmp / name
        shutil.copytree(FIXTURES / name, folder)
        if with_dist:
            (folder / "dist.tar").write_bytes(b"build output")
        if metrics is not None:
            (folder / "sensor" / "metrics.prom").write_text(metrics)
        return folder

    def test_clean_build_passes(self):
        result, output = run_cli(self.evidence("week5-clean"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads((output / "verdict.json").read_text())
        self.assertEqual(report["findings"], [])
        self.assertEqual(report["domains"], ["registry.npmjs.org"])
        self.assertEqual(report["destinations"], ["172.18.0.2:3128"])

    def test_escape_build_fails_on_exactly_its_three_attempts(self):
        result, output = run_cli(self.evidence("week5-escape"))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        report = json.loads((output / "verdict.json").read_text())
        self.assertEqual(rules(report), {"FILE-1", "NET-1", "NET-2"})
        self.assertIn("203.0.113.10:443", report["destinations"])

    def test_killed_sensor_fails(self):
        folder = self.evidence("week5-clean")
        log = folder / "sensor" / "tetragon.log"
        lines = [line for line in log.read_text().splitlines() if "ztb-canary-end" not in line]
        log.write_text("\n".join(lines) + "\n")
        result, _ = run_cli(folder)
        self.assertEqual(result.returncode, 1)
        self.assertIn("SENSOR-1: The end canary is missing", result.stdout)

    def test_missing_files_fail_closed(self):
        for name in ("nonce.txt", "builds/sandbox.cid", "proxy.ip", "proxy/access.log",
                     "sensor/metrics.prom"):
            with self.subTest(missing=name):
                folder = self.evidence("week5-clean")
                (folder / name).unlink()
                result, _ = run_cli(folder)
                self.assertEqual(result.returncode, 1, f"passed without {name}")
                shutil.rmtree(folder)

    def test_missing_build_output_fails(self):
        result, output = run_cli(self.evidence("week5-clean", with_dist=False))
        self.assertEqual(result.returncode, 1)
        self.assertIn("BUILD-1", result.stdout)
        self.assertIsNone(json.loads((output / "predicate.json").read_text())["ztb"]["distSha256"])

    def test_lost_events_fail(self):
        metrics = CLEAN_METRICS.replace("events_lost_total 0", "events_lost_total 12", 1)
        result, output = run_cli(self.evidence("week5-clean", metrics=metrics))
        self.assertEqual(result.returncode, 1)
        self.assertIn("SENSOR-5: The sensor lost events: "
                      "tetragon_observer_ringbuf_events_lost_total = 12", result.stdout)
        self.assertEqual(rules(json.loads((output / "verdict.json").read_text())), {"SENSOR-5"})

    def test_missed_probes_with_labels_are_added_up(self):
        metrics = CLEAN_METRICS + 'tetragon_missed_prog_probes_total{attach="x",policy="y"} 3\n'
        result, _ = run_cli(self.evidence("week5-clean", metrics=metrics))
        self.assertEqual(result.returncode, 1)
        self.assertIn("tetragon_missed_prog_probes_total = 3", result.stdout)

    def test_metrics_without_the_counters_fail_closed(self):
        result, _ = run_cli(self.evidence("week5-clean", metrics="other_metric_total 0\n"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("None of the lost-event counters", result.stdout)

    def test_missing_metrics_fail_closed(self):
        result, _ = run_cli(self.evidence("week5-clean", metrics=None))
        self.assertEqual(result.returncode, 1)
        self.assertIn("SENSOR-5: Tetragon's metrics are missing", result.stdout)

    def test_stricter_policy_changes_the_verdict(self):
        policy = POLICY_PATH.read_text().replace('"*/socat"]', '"*/socat", "*/npm"]')
        policy_file = self.tmp / "strict.toml"
        policy_file.write_text(policy)
        result, _ = run_cli(self.evidence("week5-clean"), policy_file)
        self.assertEqual(result.returncode, 1)
        self.assertIn("PROC-1: Denied program ran: /usr/local/bin/npm", result.stdout)

    def test_predicate_shape(self):
        _, output = run_cli(self.evidence("week5-clean"))
        predicate = json.loads((output / "predicate.json").read_text())
        for key in ("monitor", "monitoredProcess", "monitorLog", "ztb"):
            self.assertIn(key, predicate)
        self.assertEqual(predicate["ztb"]["verdict"], "pass")
        self.assertEqual(len(predicate["ztb"]["policySha256"]), 64)


class LearnTest(unittest.TestCase):
    def test_policy_known_list_matches_the_real_clean_build(self):
        always, sometimes = L.learn([L.programs_in(FIXTURES / "week5-clean")])
        self.assertEqual(always, sorted(POLICY["processes"]["known"]))
        self.assertEqual(sometimes, [])

    def test_programs_in_only_some_builds_are_kept_apart(self):
        always, sometimes = L.learn([{"/a", "/b"}, {"/a", "/c"}])
        self.assertEqual(always, ["/a"])
        self.assertEqual(sometimes, ["/b", "/c"])


if __name__ == "__main__":
    unittest.main()
