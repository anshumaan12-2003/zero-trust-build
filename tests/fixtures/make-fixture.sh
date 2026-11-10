#!/usr/bin/env bash
# Cuts a small test fixture from a real evidence folder downloaded from CI.
# Keeps every sandbox event, both canaries, and 20 host events as noise the
# judge must ignore. Drops process_exit events, which the judge doesn't read.
# Usage: tests/fixtures/make-fixture.sh <evidence-dir> <fixture-dir>
set -euo pipefail

SOURCE="$1"
TARGET="$2"
CID="$(cat "$SOURCE/builds/sandbox.cid")"

mkdir -p "$TARGET/sensor" "$TARGET/proxy" "$TARGET/builds"
cp "$SOURCE/nonce.txt" "$SOURCE/proxy.ip" "$TARGET/"
cp "$SOURCE/builds/sandbox.cid" "$TARGET/builds/"
cp "$SOURCE/proxy/access.log" "$TARGET/proxy/"

jq -c --arg cid "$CID" '
  ((.process_exec.process // .process_kprobe.process // {}).docker // "") as $id
  | select(.process_exit | not)
  | select(($id != "" and ($cid | startswith($id)))
      or ((.process_exec.process.arguments // "") | contains("ztb-canary")))
' "$SOURCE/sensor/tetragon.log" > "$TARGET/sensor/tetragon.log"

# jq stops after 20 itself. Piping to head would kill jq with SIGPIPE.
jq -c -n '
  limit(20; inputs | select(.process_exec
    and (.process_exec.process.docker // "") == ""
    and ((.process_exec.process.arguments // "") | contains("ztb-canary") | not)))
' "$SOURCE/sensor/tetragon.log" >> "$TARGET/sensor/tetragon.log"

echo "$TARGET: $(wc -l < "$TARGET/sensor/tetragon.log") events"
