# Kubernetes failures, reproduced on purpose

Recorded on 2026-11-09 on a kind cluster running Kubernetes 1.35.8.

## ImagePullBackOff

- **Cause:** the image tag `ztb-app:does-not-exist` exists nowhere.
- **Symptom:** the pod stays `Pending`, waiting with reason `ImagePullBackOff`, and has 0 restarts. The container never started, so there are no logs.
- **Found with:** `kubectl get events` showed `Failed to pull image "ztb-app:does-not-exist"`. Kubernetes had expanded the short name to `docker.io/library/ztb-app:does-not-exist`.
- **Fix:** correct the image name or tag, or load the image into the cluster. For a private registry, add an image pull secret.
- **Lesson:** a short image name means Docker Hub. Always write the full registry path.

## CrashLoopBackOff

- **Cause:** the container command points to a file that doesn't exist, `dist/missing.js`.
- **Symptom:** the pod shows `Running`, but the container waits in `CrashLoopBackOff`. Its last exit reason was `Error`, with 3 restarts in 50 seconds. Kubernetes waits longer between each restart.
- **Found with:** `kubectl logs <pod> --previous` showed `Error: Cannot find module '/app/dist/missing.js'`. The `--previous` flag shows logs from the crashed run.
- **Fix:** correct the command, or the missing file or configuration it needs.

## OOMKilled

- **Cause:** a 12 Mi memory limit, and a process that keeps allocating memory.
- **Symptom:** `CrashLoopBackOff` again, but the last exit reason was `OOMKilled`, with exit code 137 (128 + signal 9).
- **Found with:** `kubectl get pod -o jsonpath='{.status.containerStatuses[0].lastState.terminated}'`, or the "Last State" section of `kubectl describe pod`.
- **Fix:** find the memory leak, or raise the limit to fit real usage. Measure usage with `kubectl top pod`, which needs metrics-server.
- **Lesson:** CrashLoopBackOff names a pattern, not a cause. The last exit reason tells you which problem it is.

## Failing readiness probe

- **Cause:** the readiness probe checks `/wrong`, which returns 404.
- **Symptom:** the pod is `Running` with 0 restarts, but it is never ready. The Service has an endpoint, but it is marked not ready, so no traffic is sent to the pod.
- **Found with:** events showed `Readiness probe failed: HTTP probe failed with statuscode: 404`. The EndpointSlice showed `ready: false`.
- **Fix:** point the probe at a working health route.
- **Lesson:** a failing readiness probe removes the pod from traffic but doesn't restart it. A failing liveness probe restarts it.

## A bad rollout, then an undo

- **What I did:** updated the image to `ztb-app:oops`, a tag that doesn't exist.
- **What happened:** one new pod hit `ImagePullBackOff`, and the old pods kept running. With 2 replicas, the default rolling update allows 0 pods to be unavailable, so the app kept serving `/health` throughout.
- **Fix:** `kubectl rollout undo deployment/ztb-app` restored the previous image.
- **Lesson:** a rolling update only removes old pods after new ones are ready, so a broken image doesn't take the app down. `kubectl rollout status` timing out is the warning sign.

## Slow shutdown: a real bug found while testing

- **Symptom:** after a rollout, old pods lingered. Deleting a pod took exactly 30 seconds, which is the full grace period.
- **Cause:** Node runs as process 1 in the container. Process 1 ignores `SIGTERM` unless the program handles it, so Kubernetes waited 30 seconds and then force-killed the app with `SIGKILL`. Any open requests would have been cut off.
- **Fix:** `app/src/server.ts` now handles `SIGTERM` by closing the server and exiting.
- **Result:** deleting a pod went from 30 seconds to 2 seconds.
