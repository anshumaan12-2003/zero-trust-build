#!/usr/bin/env bash
# Runs one attack-lab scenario end to end:
#   1. copy the app, and let the scenario mutate the copy (mutate-app.sh),
#   2. build the copy in the sandbox with the sensor on,
#   3. let the scenario mutate the evidence if it needs to (mutate-evidence.sh),
#   4. judge the evidence and leave the verdict in out/report/.
# Usage: lab/run-scenario.sh <scenario-id>
# It never signs or publishes anything. The release job is not involved.
set -euo pipefail

ID="${1:?usage: lab/run-scenario.sh <scenario-id>}"
DIR="lab/scenarios/$ID"
[ -d "$DIR" ] || { echo "No such scenario: $ID" >&2; exit 2; }

# A clean slate, so a leftover container or network from an earlier run can't
# make the build fail for the wrong reason.
docker rm -f ztb-proxy ztb-build tetragon > /dev/null 2>&1 || true
docker network rm ztb-sandbox ztb-egress > /dev/null 2>&1 || true
rm -rf out

work="$(mktemp -d)"
app="$work/app"
cp -r app "$app"

if [ -f "$DIR/mutate-app.sh" ]; then
  echo "== $ID: preparing the app =="
  SCENARIO_DIR="$PWD/$DIR" bash "$DIR/mutate-app.sh" "$app"
fi

echo "== $ID: building in the sandbox =="
sensor/start-sensor.sh
# A scenario's build may legitimately fail (a blocked connection aborts npm);
# the evidence is what matters, so don't stop the run on a non-zero build.
APP_DIR="$app" sandbox/run-build.sh || echo "(the sandboxed build exited non-zero)"
sensor/stop-sensor.sh

if [ -f "$DIR/mutate-evidence.sh" ]; then
  echo "== $ID: tampering with the evidence =="
  bash "$DIR/mutate-evidence.sh" out
fi

echo "== $ID: judging =="
python3 ztb/judge.py --evidence out --policy policy/build-policy.toml --output out/report || true
cat out/report/verdict.json
rm -rf "$work"
