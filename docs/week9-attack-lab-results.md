# Week 9: the attack lab

Recorded on 2026-11-10. Run: `lab.yml` (attack-lab) run 42783381402 on GitHub's `ubuntu-24.04` runner. Every scenario ran through the real sandbox (`sandbox/run-build.sh`), the real sensor (Tetragon v1.8.0) and the real judge (`ztb/judge.py`), against `policy/build-policy.toml`.

## What the lab is

It attacks the pipeline on purpose, so the project can state what it catches **and** what it misses. Each scenario is a small, clearly-labelled test fixture under `lab/scenarios/`. `lab/expected.toml` records the verdict and the failing rules expected of each one, written before the run; `lab/assert.py` checks the judge's real verdict against it. The workflow runs one CI job per scenario, so a miss in one never hides a miss in another. The release job is never involved, so nothing is ever signed or published from the lab.

### Safety

All addresses are reserved (`203.0.113.0/24` TEST-NET-3, the cloud-metadata address `169.254.169.254`), all domains end in `.invalid`, and all credentials are the fake decoys the repo already ships. Nothing reaches a real system. Payloads stay in this repo and are never published to a registry.

## Headline result

**All 19 scenarios behaved exactly as written down in advance** — including the two that were predicted to be misses. The lab is green not because the pipeline catches everything (it does not), but because its real behaviour matches the documented expectation in every case.

- **6 of the build attacks are caught** by a specific rule.
- **5 build attacks get through**, each for a reason that is now documented.
- **1 "attack" finds nothing**, because the sandbox holds no secrets to steal.
- **4 clean builds pass** with no failing rule.
- **3 evidence-tampering cases are caught** by the judge.

## Normal builds — these must pass

| ID | Build | Result |
|---|---|---|
| B1 | Clean build (baseline) | ✅ pass |
| B3 | A new ordinary dependency (`is-odd`) | ✅ pass (an unknown program is a PROC-2 *warning*, not a failure) |
| B4 | A dependency with a harmless install script | ✅ pass (an install script is not a failure by itself) |
| B5 | A larger dependency tree (`lodash`, `chalk`, `commander`) | ✅ pass |

## Attacks inside the build

| ID | The fake attack | Expected | Result |
|---|---|---|---|
| M1 | Connects straight to `203.0.113.10` | NET-1 | ✅ caught, NET-1 |
| M2 | Asks the proxy for `evil.invalid` | NET-2 | ✅ caught, NET-2 (proxy denied it) |
| M3 | Reads the decoy AWS credentials | FILE-1 | ✅ caught, FILE-1 |
| M4 | Reads another process's `/proc/<pid>/environ` | MEM-2 | ✅ caught, MEM-2 |
| M5 | Reads another process's `/proc/<pid>/mem` | **miss** | ⚠️ **missed, as predicted** |
| M6 | Connects to the metadata address `169.254.169.254` | NET-1 | ✅ caught, NET-1 |
| M7 | Hides data in a DNS lookup | **miss** | ⚠️ **missed** |
| M8 | Searches the environment for tokens | pass | ✅ pass (nothing to find) |
| M9 | Fires only when `CI=true` | NET-1 | ✅ caught, NET-1 (the sandbox sets `CI=true`) |
| M10 | Slips an extra file into the build output | **miss** | ⚠️ **missed** |
| M11 | Sends data out through the allowed npm domain | **miss** | ⚠️ **missed** |
| M12 | Dormant: acts only when the app runs later | **miss** | ⚠️ **missed** |

## Attacks on the pipeline itself (evidence tampering)

| ID | What is tampered with | Expected | Result |
|---|---|---|---|
| S3 | The build output is deleted from the evidence | BUILD-1 | ✅ caught, BUILD-1 |
| S4 | A line in the sensor log is corrupted | SENSOR-2 | ✅ caught, SENSOR-2 |
| S5 | The recorded container ID is swapped | SENSOR-4 | ✅ caught, SENSOR-4 |

Two more pipeline attacks are covered elsewhere: **S1** (the sensor never starts) and **S2** (the sensor is stopped halfway) are the `sensor-build` *kill-test* job, which checks that the end canary is missing so the judge fails the build (SENSOR-1).

## Attacks on the gate

These are the Week 8 gate test (`gate/test-gate.sh`), not the build lab, because they belong to Kubernetes admission:

| ID | What you try | Result (Week 8) |
|---|---|---|
| G1 | Deploy the attested image | ✅ admitted |
| G2 | Deploy an image pushed by hand | ✅ refused |
| G3 | Deploy a signed image with no behaviour record | ✅ refused (type-mutation test) |
| G4 | Use an attestation signed by a different identity | ✅ refused (branch-signed image) |
| G5 | Move a trusted tag to an unattested image | ✅ refused (checked by digest) |
| G6 | Stop Kyverno, then create a pod | ⚠️ known gap (scale-to-0 removes the webhooks) |

## The five misses, and why they matter

A security tool that claims to catch everything is not believable. These are the gaps, stated plainly:

1. **M5 — reading another process's memory (`/proc/<pid>/mem`).** Predicted as a miss, and it missed. The Week 9 sensor work found that the kernel refuses this read before Tetragon's `security_file_permission` hook runs, so no event is recorded. Reading `/environ` (M4) *is* caught, because that read is permitted and the hook fires. A hook on the file *open* would surface the refused attempt too.
2. **M7 — DNS tunnelling.** The sandbox's resolver is Docker's at `127.0.0.11`, a loopback address the judge ignores (loopback is normal and high-volume). Data encoded in DNS labels to an allowed-looking resolver is not seen. Catching it would need to parse DNS payloads, not just connections.
3. **M10 — an extra file in the build output.** The judge attests *behaviour*, not the contents of the output. An install script that writes an unreviewed file into `node_modules` ships it in the image. The signature still covers it; it is just not reviewed.
4. **M11 — exfiltration through the allowed domain.** The proxy permits `registry.npmjs.org`. Anything tunnelled through that one allowed host looks like a normal dependency fetch. An allow-list limits *where* traffic can go, not *what* it carries.
5. **M12 — dormant code.** Code that stays quiet during the build and wakes up only when the app runs later is invisible to a build-time sensor. This is the fundamental limit: the pipeline records the *build*, not the *running app*.

Misses 3–5 are the same shape: the system proves what the build *did*, not what the shipped artifact *is* or what it will *do later*. That boundary is the honest scope of the project.

## What is not yet measured

The catch table is done. The numbers in the roadmap's "What to measure" section — false-alarm rate over 20+ clean runs, added build time, evidence size, lost events — are Week 10 work. The `flakiness` job in `lab.yml` (B1 repeated, manual trigger) produces the false-alarm rate once the workflow is on `main`.

## One tuning decision left

`policy/build-policy.toml` still has `unknown_action = "warn"`, so a program not seen in clean builds is a warning. B3 and B5 stayed quiet, which is the signal the roadmap asks for before switching to `"fail"`. That switch is deferred to Week 10, alongside the false-alarm measurement, because flipping it changes the clean-build baseline and should be measured, not guessed.
