# 001: Use Tetragon to record builds

Date: 2026-11-09

## What I needed to decide

How to record what a build actually does: which programs run, what they connect to, and which sensitive files they read. The record has to come from outside the build, so the build can't fake it.

## Options I considered

| Option | Why not, or why |
|---|---|
| Build logs | They only show what a program chooses to print. Malware prints nothing. |
| `strace` (ptrace) | Slows the build, can be detected by the traced program, and runs alongside it rather than outside it. |
| `auditd` | Built into Linux, but its rules and output are hard to filter per container. |
| Harden-Runner | A hosted service. Good for real teams, but I want to own and explain every part. |
| cicd-sensor | Close to this project's goal, but pre-release, and its docs treat the job and host as one trust zone. |
| **Tetragon** | eBPF in the kernel, so it sees system calls whatever the program prints. Stable releases (v1.8.0). Policies are plain YAML. Events are JSON with the container ID attached. |

## What I chose, and why

Tetragon v1.8.0, running as a privileged container on the GitHub runner, outside the build container. It records from the kernel, so the build can't hide from it. Its JSON events include the container ID, so one build's events can be separated from everything else on the machine.

Week 3 confirmed it works on GitHub's `ubuntu-24.04` runners, with kernel 7.0.

## What this choice costs me

- It needs Linux, so it can't run on my Mac. All recording happens on GitHub's machines.
- It needs root on the host. If the build could reach the host, it could stop the sensor. The start and end canaries make that visible, and the Week 4 kill test checks it.
- Hooks must be chosen carefully. Week 3 showed `tcp_connect` misses blocked connections, and DNS lookups aren't covered yet.
- The container ID field is 31 characters, not the 15 the schema comment says. The judge must match by prefix.
