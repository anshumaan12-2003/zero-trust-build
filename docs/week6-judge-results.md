# Week 6: the judge

Recorded on 2026-11-10. Runs: `pipeline.yml` run 42757250028 and `ci.yml` run 42757249555, on GitHub's `ubuntu-24.04` runner with Python 3.12.3.

## What the judge does

`ztb/judge.py` reads the evidence folder the build job uploads and checks it against `policy/build-policy.toml`. It uses only Python's standard library. It writes `verdict.json` and `predicate.json`, an in-toto runtime-trace v0.2 record that Week 7 will sign.

| Rule | Fails the build when |
|---|---|
| SENSOR-1 | The start or end canary is missing, so the sensor may have been off |
| SENSOR-2 | An evidence line can't be read |
| SENSOR-3 | The proxy log is empty or missing |
| SENSOR-4 | No events match the sandbox container |
| BUILD-1 | The build produced no output |
| NET-1 | The sandbox tried to connect anywhere except the proxy or loopback |
| NET-2 | The proxy refused a request |
| NET-3 | The proxy allowed a domain that isn't on the policy's list |
| PROC-1 | A denied program ran, such as `curl` |
| PROC-2 | A program not seen in clean builds ran. For now this only warns. |
| FILE-1 | A decoy credential file was read |
| MEM-1, MEM-2 | Something tried to read another process's memory or environment |

Every SENSOR rule exists so that missing evidence fails the build instead of passing it.

## Results

| Build | Verdict | Findings |
|---|---|---|
| Clean build, new run | Pass | None, not even a PROC-2 warning |
| Escape build | Fail | FILE-1 (decoy read), NET-1 (`203.0.113.10:443`), NET-2 (`example.com`) |

The judge job ran on a fresh machine in 9 seconds. The escape test now also checks that the findings are exactly these three.

## Tests

31 tests pass in CI. 22 use small made-up events, one per rule. 7 use real evidence from Week 5 (run 42665549829), cut down by `tests/fixtures/make-fixture.sh` to the sandbox's events, both canaries and 20 host events as noise. These real-evidence tests check that:

- the clean build passes, and only `registry.npmjs.org` and the proxy appear
- the escape build fails on exactly its three attempts
- removing the end canary fails the build, which is what a killed sensor looks like
- deleting any one of the nonce, container ID, proxy address or proxy log fails the build
- a missing build output fails the build
- adding `*/npm` to the denied list fails the clean build, so the policy really controls the verdict

Two more tests check `ztb/learn.py`. The `known` list it learns from the real clean build matches the policy exactly.

## A weakness found in real evidence

The start canary loop runs `sudo grep ztb-canary-start-<nonce>` to wait for the sensor. That grep's own exec event carries the nonce too, so the first judge would have counted a grep as the canary. Now only an `echo` whose arguments are exactly the canary counts. A test fails against the old logic and passes against the new.

The made-up events never showed this problem. It only appeared in real data.
