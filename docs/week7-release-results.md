# Week 7: signing only what passed

Recorded on 2026-11-10. Run: `pipeline.yml` run 42758206566, started by hand on the `week-7-release` branch.

## The release job

It runs only after the judge passes, and only on `main` or a manual run. Pull requests never reach it. It is the only job with `id-token: write`.

| Step | Why |
|---|---|
| Check `verdict.json` says pass | A second check, besides `needs: judge` |
| Compare the hash of `dist.tar` with the one in the judged record | The image must come from exactly the output that was judged |
| Unpack with Python's `tarfile` "data" filter | The build wrote this archive. The filter refuses absolute paths, `../` paths, links outside the folder, device files and setuid bits. |
| Assemble with `release/Dockerfile`, which only has COPY | No code from the build runs on the machine that can sign |
| Smoke test `/health` with a read-only filesystem and no capabilities | Don't sign an image that doesn't start |
| Push, then sign and attest **by digest** | A tag can be moved later. A digest can't. |
| Verify both with the expected identity | Checks the same thing the gate will check |

Signing is keyless. GitHub gives the job a short-lived identity token, and Sigstore swaps it for a certificate that lasts about 10 minutes and names the exact workflow and branch. Every signature is also recorded in Sigstore's public transparency log.

## Results

| Check | Result |
|---|---|
| Judged hash against actual hash | Equal: `f4c228fa…0fba` |
| Unpack | 718 files |
| Smoke test | `{"status":"ok"}` |
| Image | `ghcr.io/anshumaan12-2003/zero-trust-build-app@sha256:cd9f82f3…fef7` |
| Signature and attestation | Created and verified in CI |
| Verified again from a Mac, without logging in | Passed. The GHCR package is public. |
| Signed verdict inside the attestation | `pass`, network `registry.npmjs.org` only |
| Verify while requiring `refs/heads/main` | **Refused**: the certificate names `refs/heads/week-7-release` |

That last row is the important one for Week 8. A manual run on a branch can sign, but its certificate says which branch it came from, so a gate that accepts only `main` refuses it.

## Unpacking tested against bad archives

Before the first run, `release/unpack.py` was tested on the real Week 5 output and two crafted archives:

| Archive | Result |
|---|---|
| Real build output | 718 files unpacked |
| A link to `/etc/passwd` | Refused: `AbsoluteLinkError` |
| A file named `../../escape.txt` | Refused: `OutsideDestinationError`, and nothing was written outside the folder |

## Removed: the old image job

`ci.yml` had an `image` job since Week 2. It ran `npm ci` inside `docker build` on a machine that could push packages. That broke the main rule, because build code ran next to a credential. It is gone, and `app/Dockerfile` is now for local use only.

## Where cosign stored things

cosign v3.1.4 stored the signature and the attestation as new-format Sigstore bundles, linked to the image through OCI referrers. Week 8 starts by checking that Kyverno can read this format. If it can't, the fallback is `--new-bundle-format=false`.
