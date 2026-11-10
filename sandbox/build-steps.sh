#!/bin/sh
# Runs inside the sandbox. Treat everything here as untrusted.
set -eu

echo "Sandbox user: $(id)"
grep -E '^Cap(Eff|Bnd)' /proc/self/status

# The decoy credentials are mounted read-only as $HOME. Nothing legitimate reads them.
cp -r /src /tmp/work
cd /tmp/work

npm ci --no-audit --no-fund
npm test
npm run build
npm prune --omit=dev

cp -r dist node_modules package.json /out/
