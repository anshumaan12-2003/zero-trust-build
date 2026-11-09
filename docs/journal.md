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
