#!/usr/bin/env bash
# Week 3 experiments: do things for the sensor to see, one container per case.
# Each case saves its container ID, so its events can be found in the log.
# Every target is harmless. 203.0.113.10 is a reserved documentation address.
set -uo pipefail

IMAGE="alpine:3.22"
mkdir -p out/cases
docker pull -q "$IMAGE" > /dev/null
docker network create --internal ztb-test > /dev/null

run_case() {
  local name="$1"; shift
  echo "== $name"
  docker run --rm --cidfile "out/cases/$name.cid" "$@" || true
}

# Network: the same blocked address with three kinds of network.
run_case a-normal-network "$IMAGE" sh -c 'wget -T 3 -q -O /dev/null http://203.0.113.10 || true'
run_case b-no-network --network none "$IMAGE" sh -c 'wget -T 3 -q -O /dev/null http://203.0.113.10 || true'
run_case c-internal-network --network ztb-test "$IMAGE" sh -c 'wget -T 3 -q -O /dev/null http://203.0.113.10 || true'

# Network: a name lookup with no network, as seen in Week 1.
run_case d-dns-no-network --network none "$IMAGE" sh -c 'wget -T 3 -q -O /dev/null http://example.invalid || true'

# Files: a fake credential file, another process's environment and memory.
run_case e-decoy-file "$IMAGE" sh -c 'mkdir -p /root/.aws && echo FAKE-DECOY-NOT-A-KEY > /root/.aws/credentials && cat /root/.aws/credentials > /dev/null'
run_case f-proc-environ "$IMAGE" sh -c 'FAKE_TOKEN=abc sleep 30 & sleep 0.5; cat /proc/$!/environ > /dev/null; kill $!'
run_case g-proc-mem "$IMAGE" sh -c 'sleep 30 & sleep 0.5; head -c 1 /proc/$!/mem > /dev/null 2>&1; kill $!'

# Memory: strace uses ptrace to watch another program.
run_case h-ptrace "$IMAGE" sh -c 'apk add -q --no-cache strace && strace -f -o /dev/null true'

docker network rm ztb-test > /dev/null
