# Build journal

After every session, write what you did, what broke, and how you fixed it. These notes become your interview stories.

## 2026-11-09: Week 0

- **Did:** installed kind, helm, cosign, actionlint, shellcheck and zizmor. Created this public repo.
- **Broke:**
- **Fixed by:**
- **Learned:**
- **Next:** finish the Week 0 checklist, then start Week 1.

## 2026-11-09: Week 1

- **Did:** built the demo API (Express, TypeScript, 4 tests) and a multi-stage Dockerfile. Ran the `/proc` and container-locking experiments in Docker on the Mac.
- **Results:**
  - A process's secret shows in `/proc/<pid>/environ` to the same user. Another user gets "Permission denied".
  - A container sees only its own processes, starting at PID 1.
  - Root in a container has capabilities `a80425fb`. With `--user 1000 --cap-drop=ALL`, `CapEff` is all zeros.
  - `--network none`: the request failed at DNS (`EAI_AGAIN`) before any connection. Keep this in mind for the Week 3 network hook test.
  - `--user 1000` stopped writes to `/etc`. `--cap-drop=ALL` stopped root from using `chown`. `--read-only` stopped all writes except a `--tmpfs` folder.
  - With all flags together, the app still served `/health`.
  - Final image: 355 MB, but our layers add only about 7 MB. TypeScript and `src/` are not in it.
- **Broke:**
- **Fixed by:**
- **Learned (write this in your own words):**
- **Next:** Week 2, GitHub Actions and Kubernetes basics.

## 2026-11-09: Week 2

- **Did:** added a CI workflow (tests, workflow linting, image push to GitHub's registry from `main`). Deployed the app to a kind cluster. Broke it four ways and practised a rollout and an undo. Details are in `docs/kubernetes-failures.md`.
- **Broke:** zizmor's strict mode found 5 small issues: no job names, uncommented permissions, and no concurrency limit. Old pods also took 30 seconds to stop.
- **Fixed by:** named the jobs, commented each permission, and added a concurrency group. Made the app handle `SIGTERM`, which cut shutdown from 30 seconds to 2.
- **Learned (write this in your own words):**
- **Next:** Week 3, run Tetragon on a GitHub runner.

## 2026-11-09: Week 3

- **Did:** ran Tetragon on a GitHub runner with eight harmless test cases. Results are in `docs/week3-sensor-results.md`.
- **Broke:** my first filter matched almost no events, because I assumed the container ID field was 15 characters long. It's 31.
- **Fixed by:** checking the real field length in the evidence, not trusting the schema comment.
- **Proved:** `tcp_connect` misses blocked connections, while `security_socket_connect` catches them.
- **Found:** DNS lookups and refused `/proc/<pid>/mem` reads leave no event with the current policies.
- **Learned (write this in your own words):**
- **Next:** Week 4, run the demo build with the sensor on.

## 2026-11-09: Week 4

- **Did:** recorded three builds with the sensor and three without, and killed the sensor halfway through one build. Results are in `docs/week4-build-results.md`. Started `policy/build-policy.toml` and wrote decision record 001.
- **Broke:** downloading the evidence failed with GitHub's "Egress is over the account limit" error.
- **Fixed by:** waiting 20 seconds and retrying. It was a temporary GitHub storage problem.
- **Found:** every build ran the same 6 programs. npm reached the registry through a different Cloudflare IP address each time, so the proxy must allow domains, not IP addresses.
- **Learned (write this in your own words):**
- **Next:** Week 5, the sandbox and the proxy.

## 2026-11-09: Week 5

- **Did:** locked the build in a sandbox with no route out and a Squid proxy as the only exit. Added fake decoy credentials and an escape test. Pinned both images to digests. Results are in `docs/week5-sandbox-results.md`.
- **Broke:** before the first run, I noticed that copying the decoys into `$HOME` would read them, so every clean build would set off the decoy alarm. The first escape checker also used `eval`, which was fragile.
- **Fixed by:** mounting the decoys read-only as `$HOME`, and rewriting the checker with plain functions.
- **Found:** a clean build talks only to the proxy and Docker's DNS. The escape test's direct connection, other domain and decoy read were all blocked or recorded.
- **Learned (write this in your own words):**
- **Next:** Week 6, the judge.

## 2026-11-10: Week 6

- **Did:** moved the judge into `ztb/judge.py`, added `ztb/learn.py`, and gave the judge its own job that never runs build code. Wrote 31 tests, 7 of them on real Week 5 evidence. Wrote decision record 002. Results are in `docs/week6-judge-results.md`.
- **Broke:** the fixture script exited with code 141, because `head` closed the pipe early and `pipefail` turned jq's SIGPIPE into a failure.
- **Fixed by:** letting jq stop after 20 events itself with `limit`.
- **Found:** the start canary loop's `grep` carries the nonce, so the old judge could count it as the canary. Only an exact `echo` counts now.
- **Learned (write this in your own words):**
- **Next:** Week 7, sign the verdict and the image.

## 2026-11-10: Week 7

- **Did:** added the release job. It checks the judged hash, unpacks the build output safely, assembles the image with COPY only, smoke tests it, then signs it and attaches the behaviour record with cosign, keyless. Removed the old image job. Results are in `docs/week7-release-results.md`.
- **Broke:** Docker Desktop wasn't running on the Mac, so I couldn't test the image locally.
- **Fixed by:** adding a smoke test to the release job itself, so every release is tested before it's signed.
- **Found:** a check that requires `main` refuses an image signed from a branch, because the certificate names the branch. The GHCR package is public, since verifying worked without logging in.
- **Learned (write this in your own words):**
- **Next:** Week 8, the Kubernetes gate.

## 2026-11-10: Week 8

- **Did:** wrote the Kyverno gate and a test workflow that tries 8 cases on kind. Results are in `docs/week8-gate-results.md`.
- **Broke:** quay.io returned 504 and 502 errors, so the first release from `main` couldn't start the sensor. A re-run then judged an empty evidence artifact left by a failed attempt.
- **Fixed by:** pinning Tetragon by digest and retrying the pull, and naming artifacts with the run attempt.
- **Found:** Kyverno reads cosign v3 bundles. Kyverno deletes its own webhooks when scaled to 0, so the gate opens. A crash keeps the webhooks, so the gate stays shut. My first two "Kyverno is down" tests were wrong, and printing the webhook configurations showed why.
- **Learned (write this in your own words):**
- **Next:** Week 9, the attack lab.

## 2026-11-10: Week 9

- **Did:** built the attack lab under `lab/`: 19 harmless, labelled scenarios that run through the real sandbox, sensor and judge, with the expected verdict for each written in `lab/expected.toml` before the run and checked by `lab/assert.py`. One CI job per scenario; the release job is never involved. Results are in `docs/week9-attack-lab-results.md`.
- **Broke:** nothing — every scenario matched its written-down expectation on the first run.
- **Fixed by:** n/a.
- **Found:** 6 of the build attacks are caught, 5 get through, and each miss is documented. Reading another process's `/environ` is caught (MEM-2) but reading its `/mem` is not, because the kernel refuses that read before the sensor's hook fires — I predicted that miss in advance and it held. DNS tunnelling, exfil through the allowed npm domain, an extra file in the output, and dormant runtime-only code are all misses by design: the pipeline proves what the build did, not what the artifact is or does later.
- **Learned (write this in your own words):**
- **Next:** Week 10, measure — false-alarm rate, added build time, evidence size — and switch `unknown_action` to `fail`.
