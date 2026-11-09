# Week 4: recording a real build

Recorded on 2026-11-09. Run: `sensor-build.yml`, run 42664568807, on GitHub's `ubuntu-24.04` runner.
The build ran `npm ci`, `npm test` and `npm run build` in a plain `node:22-slim` container. Week 5 locks it down.
To repeat the analysis: `python3.12 sensor/experiments/list-programs.py <evidence>/sensor-build`.

## Time added by the sensor

| Builds | Run 1 | Run 2 | Run 3 | Median |
|---|---|---|---|---|
| Without the sensor | 4.54 s | 4.43 s | 4.41 s | 4.43 s |
| With the sensor | 4.61 s | 4.75 s | 4.52 s | 4.61 s |

The sensor added about 0.2 seconds, or 4%. With only 3 runs each, normal variation is about as large as the difference. Week 10 repeats this with 10 runs each.

## Programs: identical in every build

All three watched builds ran the same six programs, each the same number of times:

| Program | Runs per build |
|---|---|
| `/usr/local/bin/node` | 8 |
| `/usr/local/bin/npm` | 4 |
| `/usr/bin/sh` | 4 |
| `/tmp/work/node_modules/.bin/tsc` | 2 |
| `/usr/bin/cp` | 1 |
| `/usr/local/bin/docker-entrypoint.sh` | 1 |

These became the `known` list in `policy/build-policy.toml`.

## Connections: why the proxy must filter by domain

- `registry.npmjs.org` is served by Cloudflare. In every build, npm checked 12 addresses, from `104.16.0.34` to `104.16.11.34`, using port-less checks. Then it made 15 connections to just one of them on port 443.
- **The chosen address was different every time:** `104.16.1.34`, then `104.16.5.34`, then `104.16.7.34`. An allow list of IP addresses would keep breaking. The Week 5 proxy will allow the domain name instead.
- Each build looked up the name through Azure's DNS server, `168.63.129.16:53`. Here the lookup appeared as a `connect` event. In Week 3, busybox's `wget` made no such event, so whether DNS is recorded depends on the program.
- Each build also connected to itself on `127.0.0.1` at a random port. Loopback traffic stays inside the container.

## Evidence size

- About 64 events, or 68 KB, per build.
- The whole log for three builds plus everything else on the machine was 871 KB.
- `--export-file-max-size-mb 1024` is far above this, so log rotation can't lose evidence at this scale.

## Kill test: stopping the sensor halfway

The sensor was killed 5 seconds into a build. The start canary was in the log, and the end canary was missing. The build itself carried on, and only 38 of its events were recorded. So the judge's rule is correct: no end canary means the evidence is incomplete, and the build must fail.
