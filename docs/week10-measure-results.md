# Week 10: measure and harden

Recorded on 2026-11-10. Run: `measure.yml` run 42798034833 on GitHub's `ubuntu-24.04` runners. Raw data: [`results/raw/`](../results/raw/). Summary: [`results/summary.json`](../results/summary.json).

## The numbers

| Measure | Result | Sample |
|---|---|---|
| False alarms | **0 of 20** clean builds failed, and none raised a warning | 20 builds, each on a fresh runner |
| Lost sensor events | **0 of 20** runs lost or missed any event | 4 Tetragon counters per run |
| Build attacks caught | **6 of 12**, with each miss documented | The Week 9 attack lab |
| Added build time | **+18.0 s** (3.0 s plain, 21.0 s secured) | Median of 10 each |
| Evidence per build | **6.5 MB** (1.1 MB of it is the sensor log, about 1,140 events) | Median of 20 |
| Gate time per pod | **+1.1 s**, and 2.2 s on the first call | Median of 9 warm calls, plus 1 cold |

These are small samples from one small app. They are reported as counts, not percentages.

## Build time

| Part | Median |
|---|---|
| Plain build | 3.0 s |
| Sensor start | 3.9 s |
| Sandboxed build with the sensor on | 13.6 s |
| Sensor stop | 3.3 s |
| **Secured total** | **21.0 s** |

**Method:** `measure/time-builds.sh` alternates plain and secured builds on one runner, so a runner that slows down affects both sides alike. All images are pulled first.
- **Plain** runs the same build steps in an ordinary container: root user, default network, no proxy, no sensor.
- **Secured** starts the sensor, builds in the sandbox through the proxy, then stops the sensor.

The 10 raw values on each side are close together (plain 2.9 to 3.2 s, secured 20.3 to 21.4 s), so the medians are stable.

**Reading it honestly:**
- **Absolute, not relative.** 18 s on top of 3 s looks like a 7× slowdown, but the demo app builds in 3 s. A real build that takes minutes would pay roughly the same fixed cost, so the absolute number is the useful one.
- **Most of the cost is probably setup, not watching.** In Week 4 the sensor alone added about 4% to the same build. The other 10.6 s in the sandboxed build is network and proxy setup, plus npm going through Squid. This is an inference. I haven't timed each part inside `run-build.sh`.
- **A deliberate wait.** Sensor stop includes a 3-second pause so the end canary reaches the log before Tetragon stops.

## False alarms

All 20 clean builds passed with no failing rule and no warning. Each ran on its own fresh runner, as a real pipeline run would.

So the roadmap's condition for the switch is met. **`unknown_action` is now `"fail"`:** a program not seen in clean builds fails the build (PROC-2). To use a new build tool, someone changes `policy/build-policy.toml`, and that change is reviewed like code.

## Lost events: a new judge rule

A dropped event is a blind spot that looks exactly like good behaviour. Two changes close this:
- **Saving the counters:** Tetragon now serves metrics on the runner's loopback, and `sensor/stop-sensor.sh` saves a snapshot into the evidence as `sensor/metrics.prom`.
- **Judging them:** the judge's new rule **SENSOR-5** fails the build if any of these counters is above zero.
  - `tetragon_observer_ringbuf_events_lost_total`: events the kernel buffer dropped
  - `tetragon_observer_ringbuf_queue_events_lost_total`: events dropped after the buffer, in Tetragon's queue
  - `tetragon_missed_prog_probes_total`, `tetragon_missed_link_probes_total`: probe runs the kernel skipped

SENSOR-5 also fails closed: if the metrics are missing, or none of these counters is in them, the build fails. Four new tests cover this.

I read the counter names from a live Tetragon v1.8.0 instead of trusting documentation. Older docs use different names, such as `tetragon_ringbuf_perf_event_lost_total`, which v1.8.0 doesn't export.

Across the 20 runs, all four counters stayed at 0. Watching this small build doesn't come close to filling the buffer. A large build or a busy shared runner might, and the judge would now catch it.

## Evidence size

The median evidence upload is 6.5 MB per build:
- **Sensor log:** 1.1 MB (about 1,140 events)
- **Build output tarball:** 2.9 MB
- **Everything else:** mostly a second, unpacked copy of the output

Uploading only `dist.tar` would cut the evidence by about 40%. I haven't made that change, because the unpacked copy is handy when debugging.

## Gate time

| Call | Time |
|---|---|
| Creating a pod with no image policy (median) | 0.06 s |
| With the gate, first call | 2.2 s |
| With the gate, later calls (median of 9) | 1.2 s |

**Method:** `measure/time-gate.sh` creates pods as server-side dry runs on kind. Admission runs in full, but nothing gets scheduled. The image is the one signed from `main`.
- **Without the gate:** Kyverno is installed but has no image policy.
- **With the gate:** `gate/require-attestation.yaml` is applied.

Later calls are still about 1.2 s each, so in this setup Kyverno appears to check the registry and the transparency log on every pod, not just once. That cost is only paid when a pod is created, not for traffic to pods already running.

## Hardening

- **Workflow linting:** zizmor (pedantic, online mode) and actionlint are clean on all 8 workflows. Online mode adds checks for known-vulnerable actions.
- **Action pinning:** every action is pinned to a full commit SHA of a release at least two weeks old. The new Pages workflow uses `actions/upload-pages-artifact` v5.0.0 and `actions/deploy-pages` v5.0.1.
- **Threat model:** written as [`docs/threat-model.md`](threat-model.md). Every caught or missed claim in it links to a test.
- **Results page:** `site/index.html` shows `results/summary.json`, and `pages.yml` publishes both from `main`.

## Not done, and why

- **Workflow lockfiles:** these became generally available on 28 October 2026, through the `gh actions-lock` extension. The pin is v0.4.0, because v0.4.1 is under two weeks old. My attempt to install the extension on the Mac was blocked, since that runs outside code, so the lockfile isn't generated yet.
- **Comparison with cicd-sensor:** not run. It means installing and tuning a second eBPF agent, and a rushed comparison would be unfair to it. This is left for later.
- **GitHub's native egress firewall:** this is still a technical preview, used through the `ubuntu-24.04-firewall` runner label. GitHub's roadmap from March 2026 aimed at general availability 6 to 9 months later. It hasn't arrived yet, so the comparison table stays as it is.
