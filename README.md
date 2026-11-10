# Zero Trust Build Pipeline

A CI/CD pipeline that records what a software build really does, judges that record against written rules, signs it, and makes Kubernetes refuse any image without a signed record.

## The problem

In May 2026, attackers published malicious versions of 42 TanStack npm packages. The packages still carried valid build provenance, because the malicious code ran inside the project's real release workflow. A signature shows where software was built. It doesn't show what happened during the build.

## The main rule

Code that might be poisoned never gets a key, and code that holds a key never runs poisoned code.

## Planned design

| Stage | What it does |
|---|---|
| Sandbox | Runs the untrusted build as a non-root user, with one way out: a proxy with an approved list of domains |
| Record | Tetragon (eBPF) records programs, connections and file reads from the sandbox |
| Judge | A separate, clean job compares the record against `policy/` and decides pass or fail |
| Seal | A third job pushes the image and signs it, plus the behaviour record, with keyless Sigstore signing |
| Gate | Kyverno refuses any pod whose image has no valid signed record from this workflow |

## Status

Weeks 0–10 work end to end on GitHub's runners:

1. **Sandbox** (Week 5): the build runs as a normal user, with no special powers and no route out except a proxy that allows only `registry.npmjs.org`.
2. **Record** (Weeks 3–4): Tetragon watches the build from the kernel. Canaries prove it was running.
3. **Judge** (Week 6): `ztb/judge.py` checks the evidence against `policy/build-policy.toml`, on a machine that never runs build code.
4. **Seal** (Week 7): only after a pass, a separate job assembles the image with COPY only, signs it with cosign (no stored keys), and attaches the behaviour record as an in-toto attestation.

5. **Gate** (Week 8): Kyverno admits the app image only with a signature and a passing behaviour record from `main`. Tested on kind with 8 cases. Known gap: scaling Kyverno to 0 removes its webhooks and opens the gate (`docs/week8-gate-results.md`).
6. **Attack lab** (Week 9): 19 harmless, labelled scenarios run through the real sandbox, sensor and judge, with each verdict checked against an expectation written in advance. Of the build attacks, 6 are caught and 5 get through, each miss documented — DNS tunnelling, exfil through the allowed domain, an unreviewed output file, dormant runtime-only code, and a memory read the kernel refuses before the sensor sees it (`docs/week9-attack-lab-results.md`).

7. **Measure and harden** (Week 10): the numbers below, a lost-events rule in the judge, unknown programs now fail the build, and a [threat model](docs/threat-model.md).

## Measured results

From `measure.yml` run [42798034833](https://github.com/anshumaan12-2003/zero-trust-build/actions/runs/42798034833) on GitHub's `ubuntu-24.04` runners. These are small samples, so they're given as counts. Raw data: [`results/summary.json`](results/summary.json) and [`results/raw/`](results/raw/). Method: [`docs/week10-measure-results.md`](docs/week10-measure-results.md).

| Measure | Result |
|---|---|
| False alarms | 0 of 20 clean builds failed |
| Lost sensor events | 0 of 20 runs |
| Build attacks caught | 6 of 12, each miss documented ([attack lab](docs/week9-attack-lab-results.md)) |
| Added build time | +18.0 s (3.0 s plain, 21.0 s secured; median of 10 each) |
| Evidence per build | 6.5 MB (median of 20) |
| Gate time per pod | +1.1 s (2.2 s on the first call) |

Next: Weeks 11–12, a real cluster and finishing.

## Related work

Existing tools already cover parts of this, including [cicd-sensor](https://cicd-sensor.github.io/), [Harden-Runner](https://github.com/step-security/harden-runner) and [zizmor](https://docs.zizmor.sh/). This project explores the full path from a locked sandbox to Kubernetes admission, and will publish what it fails to catch.

## Security note

This repo is public. It contains only fake, clearly labelled test secrets. Attack scenarios are harmless and use reserved addresses such as `203.0.113.10`.
