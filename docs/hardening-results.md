# Hardening after the review

Recorded on 2026-11-17. A review after Week 12 found gaps in what the sensor sees, what the gate checks and how `main` is protected. This pass closes most of them and measures the result.

**Runs:**
- `attack-lab` run 44035083408: 22 of 22 scenarios matched their written-down expectations.
- `gate-test` run 44035083317: 16 cases, all as designed.
- `cluster` run 44035083248: all checks passed.
- `measure` run 44033718418: false alarms and overhead with the new hooks.

## The sensor sees more

| Gap | Fix | Evidence |
|---|---|---|
| Opening `/proc/<pid>/mem` left no event, because the kernel refused the open before the read hook ran | A `security_file_open` hook with the same path filters. It runs before the file's own open handler, so refused attempts are recorded | Lab M5 now fails with MEM-2 on `/proc/1/mem` |
| A file opened and memory-mapped is never `read()`, so the read hook missed it | The same open hook | New lab M14 opens the decoy SSH key without reading it, and fails with FILE-1 |
| UDP can be sent without `connect()`, which the connect hook never sees | A `udp_sendmsg` and `udpv6_sendmsg` hook that leaves out loopback, plus a new judge rule, NET-4 | New lab M13 fails with NET-4: "sent UDP from a socket that never connected" |
| A build can replace `node_modules/.bin/tsc`, a program on the known list, with its own script | Not fixed. Measured as a documented miss | New lab M15 passes, as predicted |

For an unconnected UDP socket the hook can't see the destination, because it's only in the packet. So NET-4 reports that a send happened, not where it went.

**Attack lab:** 9 of 15 build attacks are now caught, up from 6 of 12. M5 moved from miss to caught, M13 and M14 are new catches, and M15 is a new documented miss.

**False alarms with the new hooks:** 0 of 20 clean builds failed, with no warnings. None of the 20 runs lost an event. The lab workflow now also runs when the sandbox, sensor, judge or policy changes, not only when `lab/` changes, so a sensor change can't skip the lab again.

## The gate checks more

| Gap | Fix | Gate test result |
|---|---|---|
| The checks read only normal containers | The Kyverno policy now checks normal, init and ephemeral containers | An unsigned image in an init container is refused |
| `kubectl debug` adds containers through a subresource the policy didn't match | `pods/ephemeralcontainers` is now matched | An unsigned debug container is refused |
| Only images named like the app were checked, so any other image was admitted | `gate/app-namespace-images.yaml`: a built-in ValidatingAdmissionPolicy. In namespaces labelled `ztb.dev/images=signed-app-only` it admits only the app image by digest, in every kind of container | Another image is refused in the app namespace, and the signed one is admitted |
| Scaling Kyverno to 0 removed its webhooks and opened the gate | `gate/guard-kyverno.yaml`: a built-in policy that refuses scaling Kyverno's admission controller below 1, or deleting it | Both refused |

Both new policies are built into the Kubernetes API server, so they keep working when Kyverno is down. That is what closes the Week 11 finding. With the guard removed and Kyverno at 0, Argo CD kept retrying the unsigned Deployment for 301 s, and the allow-list refused it every time. In Week 11 the same retry got the unsigned app running within about 2 minutes.

**One bug CI caught:** the first guard let `kubectl scale --replicas=0` through. `kubectl scale` sends a `Scale` object, and that object leaves `replicas` out when it is 0. The guard read a missing value as 1. It now reads a missing value on `Scale` as 0.

**What's left:** a cluster admin can remove the guard's binding. Then images outside the app namespaces are no longer checked, and the gate test still asserts that as a known gap. `ZTBGateDown` fired 120 s after the scale to 0. Refusals by the allow-list don't appear on the Kyverno dashboard, because the API server records them, not Kyverno.

## Who can sign

- **A `release` environment** now holds the signing job, and it accepts deployments only from `main`. A manual run on any other branch is refused before the job starts. Before, such a run could sign, though the gate refused its certificate.
- **The signed record names its commit.** `predicate.ztb.sourceCommit` holds the commit it was built from, so a verifier can tell an old release from a new one. The gate doesn't check freshness yet.

## Measurements with the new hooks

| Measure | Before (Week 10) | Now |
|---|---|---|
| False alarms | 0 of 20 (and 0 of 20 in a repeat) | 0 of 20 |
| Runs with lost events | 0 of 20 | 0 of 20 |
| Plain build | 3.0 s | 4.0 s |
| Secured build | 21.0 s | 24.1 s |
| Added time | +18.0 s | +20.1 s |
| Sensor events per build | about 1,140 | about 1,270 |
| Evidence per build | 6.5 MB | 6.6 MB |
| Gate time added | +1.1 s | +1.3 s |

The plain build got slower as well, so part of the change is the runner, not the hooks. The new hooks added about 130 events per build.

## Not done

- **Freshness at the gate.** The commit is now in the signed record, but the gate still admits any old signed image.
- **Program identity by hash.** This would close M15.
- **An SBOM, a vulnerability scan and SLSA provenance for the released image.**
