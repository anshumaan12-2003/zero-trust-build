# Week 3: what the camera saw

Recorded on 2026-11-09 with Tetragon v1.8.0 on a GitHub `ubuntu-24.04` runner with kernel `7.0.0-1017-azure`.
Run: `sensor-test.yml`, run 42663736047. To repeat the analysis, download the evidence and run `python3.12 sensor/experiments/summarize.py evidence`.

## Results

| Case | What it did | Hook events recorded |
|---|---|---|
| A | Connect to `203.0.113.10` on a normal network | `security_socket_connect` and `tcp_connect` |
| B | Same connection with `--network none` | `security_socket_connect` only |
| C | Same connection on an `--internal` network | `security_socket_connect` only |
| D | Look up `example.invalid` with `--network none` | None |
| E | Write and read a fake `/root/.aws/credentials` | `security_file_permission`: 2 writes and 5 reads |
| F | Read another process's `/proc/7/environ` | `security_file_permission`: 3 reads |
| G | Read another process's `/proc/7/mem` | None |
| H | Run `strace` | 62 `ptrace` calls and 2 `process_vm_readv` calls |

## What this means

1. **The blind spot is real.** When there's no route, the kernel refuses the connection before it reaches `tcp_connect`, so cases B and C left no `tcp_connect` event. `security_socket_connect` runs earlier and caught all three. The sandbox uses an internal network, so the pipeline must use `security_socket_connect`.
2. **DNS lookups are a gap (case D).** `wget` ran, but it made no connection attempt the policy could see. The lookup either used a call other than `connect`, or had no DNS server to try. Week 9's DNS-tunnelling scenario (M7) needs a hook that covers this.
3. **A refused read leaves no trace (case G).** `head` tried to read `/proc/7/mem`, but no read was recorded. The most likely explanation is that the kernel refused to open the file, so the read hook never ran. This isn't confirmed yet. Adding a hook on file opens would show refused attempts as well.
4. **Syscall hooks carry an architecture prefix.** Tetragon reports `__x64_sys_ptrace`, not `sys_ptrace`. The judge must match on part of the name.

## Details the judge depends on

- `process.docker` holds the **first 31 characters** of the container ID, not the 15 that Tetragon's schema comment says. Match by prefix so both lengths work.
- Host processes have no `docker` field, so the judge ignores them.
- The start and end canaries both appear in `process_exec` events.
- Real samples are saved in `tests/fixtures/week3-real-events.jsonl` (106 events from cases A, B, E, F and H, plus the canaries).

## Not yet done

- Confirm why case G was refused.
- Choose a hook for DNS lookups.
