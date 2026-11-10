# 002: Split building, judging and signing into three jobs

Date: 2026-11-10

## What I needed to decide

Where the judge runs, and where signing will run in Week 7. The build runs code I don't trust. The judge and the signer must not be affected by it.

## Options I considered

| Option | Why not, or why |
|---|---|
| One job does everything | The build's code would run on the same machine as the judge and, later, the signing key. A poisoned install script could edit the evidence or the judge before it runs. |
| Two jobs: build, then judge and sign together | Better, but the signing permission (`id-token: write`) would sit on a machine that also parses evidence written during an untrusted build. A bug in the judge would then be one step from the key. |
| **Three jobs: build, judge, release** | Each job is a fresh GitHub machine. The build job has no secrets. The judge job reads only the uploaded evidence and has only `contents: read`. The release job, in Week 7, gets the signing permission and runs only after the judge passes. |

## What I chose, and why

Three jobs. This follows the project's main rule: code that might be poisoned never gets a key, and code that holds a key never runs poisoned code.

Inside the build job, the build itself is also locked in a sandbox container (Week 5). It can write only `out/dist`. The sensor's log, the nonce and the proxy log are written outside the sandbox, so the build can't edit its own evidence.

## What this costs me

- **Time.** Each extra job starts a new machine and downloads the evidence again, adding roughly 10–20 seconds.
- **Pull requests test their own judge.** On a pull request, the judge and policy come from the pull request's code, so a pull request could weaken them. This is acceptable because only `main` will be signed (Week 7), and changes reach `main` only through a reviewed pull request. A later step could load the judge and policy from the base branch instead.
- **The evidence passes through GitHub's artifact storage.** I trust GitHub here. A stronger design would hash the evidence in the build job and check the hash in the judge job, but both values would still come from the same build job.
