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

Weeks 0–7 work end to end on GitHub's runners:

1. **Sandbox** (Week 5): the build runs as a normal user, with no special powers and no route out except a proxy that allows only `registry.npmjs.org`.
2. **Record** (Weeks 3–4): Tetragon watches the build from the kernel. Canaries prove it was running.
3. **Judge** (Week 6): `ztb/judge.py` checks the evidence against `policy/build-policy.toml`, on a machine that never runs build code.
4. **Seal** (Week 7): only after a pass, a separate job assembles the image with COPY only, signs it with cosign (no stored keys), and attaches the behaviour record as an in-toto attestation.

Next: the Kubernetes gate (Week 8), which refuses images without a passing attestation from `main`.

## Related work

Existing tools already cover parts of this, including [cicd-sensor](https://cicd-sensor.github.io/), [Harden-Runner](https://github.com/step-security/harden-runner) and [zizmor](https://docs.zizmor.sh/). This project explores the full path from a locked sandbox to Kubernetes admission, and will publish what it fails to catch.

## Security note

This repo is public. It contains only fake, clearly labelled test secrets. Attack scenarios are harmless and use reserved addresses such as `203.0.113.10`.
