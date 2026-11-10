# Threat model

What the Zero Trust Build Pipeline protects, who it protects against, and where it stops. Every "caught" or "missed" claim below links to a test that shows it.

## What we protect

1. **The release identity.** Only `pipeline.yml` running on `main` can produce an image Kubernetes will admit. That identity lives only in the release job, as a short-lived Sigstore certificate.
2. **The truth of the behaviour record.** A signed record must describe what the build really did, recorded from outside the build.
3. **The cluster.** No app pod runs without a signature and a passing record from that identity.

## Who we defend against

| Attacker | Example | In scope |
|---|---|---|
| A poisoned dependency | An npm package with a malicious install script (the TanStack pattern) | Yes, the main case |
| A malicious or careless contributor | A pull request that changes build steps | Partly: pull requests never reach the release job, but code merged to `main` is trusted |
| Someone with registry write access | Pushes or retags an image by hand | Yes |
| Someone with cluster access below admin | Creates pods directly | Yes |
| A cluster admin, GitHub, Sigstore or the registry | Turns off the gate, or forges identity at the source | No: these are trusted |

## Trust boundaries

| Zone | Runs build code | Holds a signing identity | Trusted |
|---|---|---|---|
| Sandbox container | Yes | No | No |
| Build job host (sensor, proxy) | No | No | Yes, but treated as able to fail |
| Judge job | No | No | Yes |
| Release job | No | Yes | Yes |
| Kyverno and the API server | No | No (verifies only) | Yes |

The main rule: code that might be poisoned never gets a key, and code that holds a key never runs poisoned code (`docs/decisions/002-why-three-jobs.md`).

## Designed to stop or catch

| Threat | Control | Evidence |
|---|---|---|
| Connections outside the allow list | The sandbox network has no route out; the sensor records every connect (NET-1); the proxy refuses other domains (NET-2, NET-3) | Lab M1, M2, M6, M9 |
| Reading the fake decoy credentials | File hooks on the decoys (FILE-1) | Lab M3 |
| Reading another process's environment | File hook on `/proc/*/environ` (MEM-2) | Lab M4 |
| Reading memory with `ptrace` or `process_vm_readv` | Syscall hooks (MEM-1) | Judge unit tests |
| A sensor that is off, stopped or broken | Secret-nonce canaries at start and end (SENSOR-1); empty or corrupt evidence fails (SENSOR-2 to 4) | sensor-build kill-test, lab S4, S5 |
| Lost sensor events | The judge reads Tetragon's lost-event counters from the evidence | Week 10 measurements |
| Missing or swapped build output | The judge requires output, and the release job checks its hash against the judged one | Lab S3, Week 7 |
| Images that skipped the pipeline | The gate requires a keyless signature from `pipeline.yml@refs/heads/main` | Week 8 gate test |
| An unsigned image committed to `deploy/` | The gate refuses the Deployment itself, so Argo CD's sync fails and no pod is created | Week 11 cluster check |
| A record signed by another branch or workflow | The certificate identity must match exactly | Week 8 gate test |
| Moved tags | The gate checks and pins images by digest | Week 8 gate test |
| A record that says fail | The gate reads the verdict out of the signed record | Week 8 mutation test |

## Reduces the risk

- **Token theft.** The build job holds no token that can write anything, so there is nothing to steal unless a workflow mistake adds one. Lab M8 searched and found nothing.
- **Container escape.** The build runs as a normal user with every capability dropped, `no-new-privileges` and a process limit. A kernel bug could still break out.
- **Evidence tampering.** The sandbox can't write the evidence, and the judge runs on a separate machine. Someone who takes over the build host could still change it before upload.

## Can't catch: the documented misses

These are measured, not guessed. Each is a scenario in `lab/` that the pipeline lets through, as predicted in `lab/expected.toml`.

| Miss | Why | What would close it |
|---|---|---|
| Reading `/proc/<pid>/mem` (lab M5) | The kernel refuses the open before the read hook fires, so no event exists | A hook on file opens, which would record refused attempts |
| Data hidden in DNS lookups (lab M7) | Lookups go to Docker's resolver on loopback, which the judge ignores | Logging DNS queries at the resolver, or no DNS in the sandbox |
| Data sent through the allowed npm domain (lab M11) | The allow list controls where traffic goes, not what it carries | An npm-aware proxy that allows only package downloads |
| An extra file slipped into the output (lab M10) | The record covers behaviour, not the contents of the output | Comparing the output against a reproducible build |
| Code that waits until the app runs (lab M12) | The sensor watches the build only | Runtime monitoring in the cluster (out of scope) |
| Bad logic in our own source code | The pipeline trusts the source on `main` | Code review and tests |
| A compromise of GitHub, Sigstore or the registry | They are the root of trust | Out of scope |
| A reviewer approving a harmful policy change | Policy changes are ordinary commits | Required reviews on `policy/` and `gate/` |

## Known gaps in the controls themselves

- **Kyverno scaled to 0 opens the gate.** Kyverno deletes its own webhooks when its deployment is scaled to 0 or deleted, so `failurePolicy: Fail` no longer applies. A crash keeps the webhooks and refuses everything. Only cluster admins can scale Kyverno today. In Week 11 this happened without anyone creating a pod by hand: Argo CD kept retrying a refused unsigned Deployment, and once Kyverno was off, a retry got the unsigned app running. It kept running after Kyverno came back. The `ZTBGateDown` alert now fires about 2 minutes after the scale to 0, so the gap is detected but not prevented. A `ValidatingAdmissionPolicy` that refuses scaling Kyverno to 0 would close it (`docs/week8-gate-results.md`, `docs/week11-cluster-results.md`).
- **Unknown programs.** Until Week 10, a program never seen in clean builds was only a warning (PROC-2). See `docs/week10-measure-results.md` for the switch to fail.
- **Argo CD can deploy whatever is on `main`.** Its project (`cluster/argocd/project.yaml`) limits it to Deployments and Services in the app namespaces from this repo, so a bad commit can't create cluster roles or change the gate. The gate still checks every image it deploys.
- **Third-party actions.** Every action and its own dependencies are locked to exact commits in `.github/workflows/actions.lock`. GitHub's runner refuses an action whose tag no longer points at the locked commit, and CI runs `gh actions-lock --verify`. zizmor and actionlint also check the workflows. A locked action is still trusted code.

## Assumptions

- GitHub's hosted runners are fresh for every job and don't share state between jobs.
- The fake decoys look worth stealing to an attacker, though a careful one might skip them.
- Builds are deterministic enough that a clean build's programs stay the same from run to run. The false-alarm measurement tests this.
