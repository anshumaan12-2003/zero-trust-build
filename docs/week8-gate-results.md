# Week 8: the Kubernetes gate

Recorded on 2026-11-10. Run: `gate-test.yml` run 42765257733, on kind v0.33.0 with Kubernetes 1.35.8 and Kyverno chart 3.9.2 (Kyverno v1.19.2), on GitHub's `ubuntu-24.04` runner.

## The policy

`gate/require-attestation.yaml` is a Kyverno `ImageValidatingPolicy`. A pod may use `ghcr.io/anshumaan12-2003/zero-trust-build-app` only if:

1. the image is signed by `pipeline.yml` running on `refs/heads/main`, through GitHub's OIDC issuer
2. a runtime-trace v0.2 attestation is signed by the same identity
3. that attestation's `predicate.ztb.verdict` is `pass`

Images are checked and pinned by digest (`mutateDigest`, `verifyDigest`). If Kyverno can't be called, the pod is refused (`failurePolicy: Fail`).

## The main known risk: cosign v3 bundles

cosign v3.1.4 stores signatures as new-format Sigstore bundles linked through OCI referrers. Kyverno's docs don't say whether it reads them, and the installed CRD has no format switch. **It does read them.** The image signed from `main` was admitted, and that requires all three checks to pass, including reading the verdict out of the bundle. No fallback was needed.

## Results

| Case | Image | Expected | Result |
|---|---|---|---|
| Signed by `main` | `@sha256:d5cd49a9…3a3a` | Admitted, and runs | ✅ Admitted, running, pinned by digest |
| Signed by a branch | `@sha256:cd9f82f3…fef7` (Week 7 test run) | Refused | ✅ "not signed by pipeline.yml on main" |
| Never signed | `:c482e9df…` (old `ci.yml` image job) | Refused | ✅ "not signed by pipeline.yml on main" |
| Not our app | `registry.k8s.io/pause:3.10` | Admitted (out of scope) | ✅ Admitted |
| Policy demands another verdict | the good image | Refused | ✅ "does not say pass" |
| Policy demands another attestation type | the good image | Refused | ✅ "no signed behaviour record" |
| Kyverno crashed (no pod, webhooks still registered) | the good image | Refused | ✅ "failed calling webhook" |
| Kyverno scaled to 0 | the good image | — | ⚠️ **Admitted. Known gap, below.** |

The two "policy demands" rows are mutation tests. The release job never signs a failing build, so there's no real failing attestation to try. Instead, each check is broken on purpose to prove it really runs and can refuse.

## Found: the gate opens when Kyverno is switched off

`failurePolicy: Fail` only helps while the webhook is registered. Kyverno **deletes its own webhooks** when its admission controller deployment is scaled to 0 or deleted (`IsGoingDown` in `pkg/utils/runtime/utils.go`, then `cleanup` in `pkg/webhooks/server.go`, v1.19.2). This is deliberate, so that turning Kyverno off can't lock up the cluster. But it means anyone allowed to scale that deployment can open the gate.

A crash is different. The deployment still wants a pod, so the webhooks stay registered, and the API server refuses every app pod until Kyverno is back.

What protects against the switch-off today: only cluster admins can scale deployments in the `kyverno` namespace. Possible backstops are a native `ValidatingAdmissionPolicy`, which runs inside the API server and can't be scaled away, that refuses scaling Kyverno to 0, and an alert when Kyverno's webhook configurations disappear.

## Two mistakes in my own tests

- **The first "Kyverno is down" test** scaled Kyverno to 0. The image got in, and I first read that as `failurePolicy` not working. Printing the webhook configurations showed they had been deleted, which led to the cause above.
- **The second test** pointed Kyverno's Service at no pods. The image still got in, because the Kyverno pod was alive and the API server kept using its open connection. The final test removes the pod itself, which is what a crash looks like.

## Also fixed this week

- **The first release from `main` failed twice before signing.** quay.io returned `504` and then `502` while pulling Tetragon, and the build stopped because the sensor couldn't start. Tetragon is now pinned by digest and its pull is retried. The build still never starts without the sensor.
- **A re-run judged the wrong evidence.** Re-running failed jobs keeps the earlier attempts' artifacts, so the run had three called `evidence`. The judge downloaded an empty one from a failed attempt and failed it on every SENSOR rule, which was the right answer for what it saw. Artifact names now carry the attempt number.
