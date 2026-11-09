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
