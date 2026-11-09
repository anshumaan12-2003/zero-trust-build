# Week 5: the sandbox and side-door guard

Recorded on 2026-11-09. Run: `pipeline.yml`, run 42665549829, on GitHub's `ubuntu-24.04` runner.

## How the sandbox is locked

| Setting | Effect |
|---|---|
| `--network ztb-sandbox` (internal) | No route to the internet |
| Squid proxy on both networks | The only way out. It allows `registry.npmjs.org` and refuses everything else. |
| `--user 1000:1000` | Not root |
| `--cap-drop=ALL` | No special powers (`CapEff` and `CapBnd` are both zero) |
| `--security-opt no-new-privileges` | Programs can't gain powers through setuid |
| Decoys mounted read-only as `$HOME` | Fake credentials that nothing legitimate reads |
| Images pinned to digests | The build can't change if someone replaces an image tag |

## Clean build

- The build passed: `npm ci`, 4 of 4 tests, and the TypeScript compile.
- **Connections:** 16 to the proxy (`172.18.0.2:3128`), 16 DNS lookups to Docker's internal DNS (`127.0.0.11:53`) to find the proxy by name, and 2 on loopback. Nothing else.
- **Proxy log:** 16 tunnels to `registry.npmjs.org:443`, all allowed.
- **File and memory hooks:** no events, so the decoys stayed untouched.
- **Programs:** the six from Week 4, plus `grep` and `id` from the sandbox's own check lines. Both were added to the known list.

## Escape test

A copy of the app got an install script that tried three things:

| Attempt | Outcome | Recorded by |
|---|---|---|
| Connect directly to `203.0.113.10:443` | Blocked: `ENETUNREACH` | `security_socket_connect`, with no `tcp_connect` |
| Ask the proxy for `example.com:443` | Refused: HTTP 403 | Proxy log: `TCP_DENIED/403` |
| Read `~/.aws/credentials` | **Read succeeded** (it's a fake decoy) | `security_file_permission` |

The sandbox stops network escapes. It doesn't stop reading files the build can see, which is why the decoys exist: the read itself becomes the evidence.

## A design flaw caught before it ran

The first version of `build-steps.sh` copied the decoys into `$HOME`. Copying a file means reading it, so every clean build would have set off the decoy alarm. The decoys are now mounted read-only as `$HOME` instead, and the clean build shows no file events.
