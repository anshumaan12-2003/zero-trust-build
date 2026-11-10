# The connection my sensor couldn't see

*Draft blog post about the Week 3 finding. Evidence: `sensor-test.yml` run 42663736047, and [`docs/week3-sensor-results.md`](week3-sensor-results.md).*

I'm building a CI pipeline that watches builds with eBPF and fails any build that tries to reach the internet. The first sensor hook I tried would have missed exactly the attack it was meant to catch. This post explains why.

## The setup

The build runs in a Docker container on an internal network, with no route to the internet. Its only way out is a proxy that allows one domain. Outside the container, Tetragon records what processes in it ask the kernel to do.

A malicious install script that tries `connect()` to an attacker's server shouldn't get anywhere, because there's no route. But I still want a record of the attempt. A build that tries to phone home is a poisoned build, whether or not the call got through.

## The obvious hook

Tetragon ships an example policy that hooks `tcp_connect`, the kernel function that starts a TCP connection. Many eBPF network-monitoring examples use it. So I expected every outgoing connection to show up there.

## The test

I ran the same command, `wget http://203.0.113.10`, in three containers and recorded two hooks at once: `tcp_connect` and `security_socket_connect`. The address is a reserved documentation address that nothing answers.

| Case | Network | `security_socket_connect` | `tcp_connect` |
|---|---|---|---|
| A | Normal Docker network | ✅ seen | ✅ seen |
| B | `--network none` | ✅ seen | ❌ nothing |
| C | `--internal` network, like the real sandbox | ✅ seen | ❌ nothing |

With a route, both hooks fired. Without one, which is the sandbox's case, `tcp_connect` saw **nothing**.

## Why

On Linux, `connect()` on an IPv4 TCP socket goes roughly like this:

1. **The system call enters the kernel.**
2. **`security_socket_connect` runs.** It's a Linux Security Module hook that runs for every connect, before any networking happens. It sees the destination address.
3. **TCP gets ready.** `tcp_v4_connect` looks up a route to the destination.
4. **`tcp_connect` builds and sends the first SYN packet.**

In an internal network the container has an interface but no default route. So step 3 fails with "network unreachable", and the kernel never reaches step 4. The attempt really happened, and `security_socket_connect` recorded it with the full destination address. But a sensor built on `tcp_connect` would have reported a clean build.

The design choice that made the sandbox safer, having no route out, is the same one that blinded the obvious hook.

## What I changed

- **Switched the hook.** The pipeline hooks `security_socket_connect`, filtered to IPv4 and IPv6. The judge's NET-1 rule fails the build on any attempt to reach an address other than the proxy's. Loopback is the only exception.
- **Tested it in the attack lab.** In Week 9, the scenario that connects straight to an outside address (M1) was caught by NET-1 in the real sandbox.
- **Kept the evidence.** Real evidence from CI runs is cut into test fixtures, so the judge's unit tests run against what the kernel actually produced, not hand-written JSON.

## What I took from it

- **Test the hook against the environment it will run in.** The `tcp_connect` example is fine on a normal network. It failed only because of how my sandbox was built.
- **"Nothing happened" is a claim that needs proof.** Since then, a missing event never counts as a pass. Canaries prove the sensor was running from start to end, and lost-event counters prove nothing was dropped.
- **Earlier hooks see attempts, and later hooks see successes.** For security monitoring, the attempt is usually what matters.

The same test turned up two more blind spots, both still open. A DNS lookup with no network left no event at all. A read of another process's `/proc/<pid>/mem` was refused before the read hook ran. Both are documented misses in the project's [threat model](threat-model.md).
