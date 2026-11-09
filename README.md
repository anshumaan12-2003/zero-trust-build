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

Week 0: setting up. Nothing works yet.

## Related work

Existing tools already cover parts of this, including [cicd-sensor](https://cicd-sensor.github.io/), [Harden-Runner](https://github.com/step-security/harden-runner) and [zizmor](https://docs.zizmor.sh/). This project explores the full path from a locked sandbox to Kubernetes admission, and will publish what it fails to catch.

## Security note

This repo is public. It contains only fake, clearly labelled test secrets. Attack scenarios are harmless and use reserved addresses such as `203.0.113.10`.
