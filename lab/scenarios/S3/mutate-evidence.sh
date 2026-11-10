#!/usr/bin/env bash
# lab S3: delete the build output from the evidence. Expected: BUILD-1.
set -euo pipefail
rm -f "$1/dist.tar"
