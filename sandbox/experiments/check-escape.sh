#!/usr/bin/env bash
# Checks that the escape test was blocked, and that the evidence recorded each attempt.
set -uo pipefail

LOG=out/sensor/tetragon.log
PROXY_LOG=out/proxy/access.log
CID="$(cat out/builds/sandbox.cid)"
failed=0

# Prints the sandbox's hook events. Tetragon stores the start of the container ID.
# shellcheck disable=SC2016 # $d and $cid are jq variables, not shell ones
sandbox_hooks() {
  jq -c --arg cid "$CID" '.process_kprobe // empty
    | select((.process.docker // "") as $d | $d != "" and ($cid | startswith($d)))' "$LOG"
}

result() {
  if [ "$2" = yes ]; then echo "PASS: $1"; else echo "FAIL: $1"; failed=1; fi
}

hooks="$(sandbox_hooks)"

if jq -e 'select(.function_name == "security_socket_connect") | .args[] | select(.sockaddr_arg.addr == "203.0.113.10")' <<< "$hooks" > /dev/null; then
  result "the direct connection to 203.0.113.10 was recorded" yes
else
  result "the direct connection to 203.0.113.10 was recorded" no
fi

if jq -e 'select(.function_name == "tcp_connect")' <<< "$hooks" > /dev/null; then
  result "no connection got past the routing step" no
else
  result "no connection got past the routing step" yes
fi

if jq -e '.args[]? | select((.file_arg.path // "") | endswith("/.aws/credentials"))' <<< "$hooks" > /dev/null; then
  result "the decoy read was recorded" yes
else
  result "the decoy read was recorded" no
fi

if grep -q 'TCP_DENIED/403 .* CONNECT example.com:443' "$PROXY_LOG"; then
  result "the proxy refused example.com" yes
else
  result "the proxy refused example.com" no
fi

exit "$failed"
