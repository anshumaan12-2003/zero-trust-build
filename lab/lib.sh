# Shared helpers for the attack-lab scenarios. Sourced by each mutate-app.sh.
# Every payload here is a harmless, clearly labelled test fixture. It only
# touches reserved addresses (203.0.113.0/24, 169.254.169.254), .invalid
# domains and the fake decoy credentials. Nothing reaches a real system.

# Wire a payload as the app's install script, the same way the Week 7 escape
# test does. npm runs it during `npm ci` inside the sandbox, where the sensor
# and proxy can see what it tries to do.
add_install_script() {
  local app="$1" payload="$2"
  cp "$payload" "$app/lab-payload.js"
  (cd "$app" && npm pkg set scripts.postinstall="node lab-payload.js" > /dev/null)
}

# Add a real dependency to a benign scenario. --package-lock-only updates
# package.json and the lockfile on the runner (which has direct network) so the
# sandboxed `npm ci` can then fetch it through the proxy. It runs no scripts.
add_dependency() {
  local app="$1" spec="$2"
  (cd "$app" && npm install --package-lock-only --no-audit --no-fund "$spec" > /dev/null)
}
