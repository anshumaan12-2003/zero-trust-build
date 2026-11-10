# Week 11: a real cluster

PLACEHOLDER_RUNLINE

## What was built

| Part | Where | Checked how |
|---|---|---|
| Azure VM with k3s, written in Terraform | `terraform/` | `terraform fmt`, `init` with a committed provider lock file, and `validate` in CI. **Not applied**: no Azure account is connected yet |
| One setup script for any cluster | `cluster/install.sh` | Run in CI on kind. The same script is meant for the k3s VM |
| GitOps with Argo CD | `cluster/argocd/`, `deploy/` | Argo CD pulls `deploy/` from this repo at the PR's commit |
| Monitoring | `cluster/monitoring/`, `cluster/values/` | Prometheus scrapes Kyverno, Grafana loads a gate dashboard, two alert rules |
| Checks | `cluster/check-cluster.sh`, `cluster/check-metrics.py` | 9 checks, all passing, plus the known gap recorded as it happens |

**Versions** (each at least two weeks old): Terraform 1.16.7, azurerm provider 5.11.0, k3s v1.35.9+k3s1 (the same Kubernetes minor as kind's node), kube-prometheus-stack chart 92.14.0, Kyverno chart 3.9.2 (Kyverno v1.19.2), and Argo CD chart 10.11.6 (Argo CD v3.5.6).

## The checks

| Check | Result |
|---|---|
| Argo CD syncs `deploy/` and the app is healthy | PASS: 2 of 2 pods ready, running the signed image by digest |
| The signed image is admitted | PASS |
| An unsigned image is refused | PASS |
| An unsigned image arriving **through Git** is refused | PASS: the gate refused the Deployment, so Argo CD's sync failed |
| Every gate panel on the dashboard has data | PASS |
| Grafana loaded the dashboard | PASS |
| `ZTBUnprovenImageRefused` fires after a refusal | PASS |
| `ZTBGateDown` fires when Kyverno is scaled to 0 | PASS, after 120 s (141 s in the first run) |

Setup took 114 s on a fresh kind cluster.

## What the first run got wrong

I expected Argo CD to create the unsigned Deployment and the gate to refuse its pods. So the first check waited for "FailedCreate" events on the ReplicaSet. None came, and the check failed.

Kyverno applies an `ImageValidatingPolicy` to pod controllers too, such as Deployments, StatefulSets and Jobs, not just to pods. So the gate refused **the Deployment itself**. Argo CD's sync failed with:

> admission webhook "ivpol.validate.kyverno.svc-fail-finegrained-require-build-attestation" denied the request: Policy require-build-attestation failed: The image is not signed by pipeline.yml on main.

No ReplicaSet or pod was ever created. That is a better result than I planned for: a bad image in Git never becomes a Deployment, and Argo CD shows the reason. The check now looks for the refusal in Argo CD's sync result.

## The scale-to-0 gap, seen for real

In Week 8 the gap was a single test: scale Kyverno to 0, and a pod created by hand gets in. This week it happened by itself:

1. Argo CD kept retrying the refused sync of the unsigned Deployment.
2. Kyverno was scaled to 0, and it removed its own webhooks.
3. Argo CD's next retry got through, and **the unsigned app was running 120 s later**.
4. Kyverno was scaled back to 1. **The unsigned pod kept running**, because admission only checks new pods.

**What helps now:** `ZTBGateDown` fired 120 s after the scale to 0, at about the same time the unsigned pod started. It doesn't prevent anything, but someone gets told.

**What would close it:**
- A `ValidatingAdmissionPolicy`, built into Kubernetes, that refuses scaling Kyverno's admission controller to 0. It doesn't depend on Kyverno running.
- Treating the Argo CD Application as a risk too. An Application that keeps failing to sync an unsigned image is an attack waiting for the gate to drop. `ZTBUnprovenImageRefused` already fires on those refusals.
- Kyverno's background scans, which could report pods that are running without a valid record.

## What the dashboard counts

Kyverno's metric `kyverno_image_validating_policy_results_total` is labelled by policy, result, resource kind and namespace. Two things surprised me:
- **It counts pod controllers as well as pods.** One Deployment and its pods produce several results.
- **Images other than the app pass without a check**, and they still count as "pass". Argo CD's own pods and Deployments show up in the allowed count.

So the panels say "Allowed by the gate" and "Refused by the gate", not "app pods". The refusal table splits by namespace and kind.

**Counts are a lower bound.** Prometheus's `increase()` can't count decisions made before it first scraped a series. A third CI run, 42834459913, showed this: every "allowed" decision happened during setup, before Prometheus picked up Kyverno, so the panel read 0 even though the app was running. The check now keeps making fresh dry-run decisions while it waits for the panels. On a long-running cluster this only affects the first scrape, but a dashboard total is never the full history.

## Memory

Measured from Prometheus on kind, with everything running:

| Namespace | MiB |
|---|---|
| kube-system (kind's control plane) | 1,424 |
| monitoring | 642 |
| argocd | 293 |
| kyverno | 202 |
| ztb (the app) | 21 |

That's about 2.6 GiB. k3s's control plane is lighter than kind's, but the OS needs room too. So the Terraform default is `Standard_B2ms` with 8 GB, and a 4 GB VM might just fit.

## Not done, and why

- **`terraform apply` on Azure.** This needs your Azure account and spends credit. The runbook is in [`terraform/README.md`](../terraform/README.md): set a subscription budget first, apply, run the same two scripts, then `terraform destroy`. Until someone runs it, the "bad image refused on a real machine" condition is met on kind in CI, not on Azure.
- **Alert delivery.** Alertmanager is off, so alerts show in Prometheus but go nowhere. Sending them somewhere is a one-line receiver once there's a place to send them.
- **Closing the scale-to-0 gap.** The alert detects it. A `ValidatingAdmissionPolicy` to prevent it is the next step.
