#!/usr/bin/env python3
"""Unpack the build output without trusting it.

The build wrote this archive, so it may hold absolute paths, "../" paths,
links pointing outside the folder, device files or setuid bits. Python's
"data" filter refuses all of them. Usage: unpack.py <dist.tar> <folder>
"""
import sys
import tarfile
from pathlib import Path

archive, target = sys.argv[1], Path(sys.argv[2])
target.mkdir(parents=True, exist_ok=False)
with tarfile.open(archive) as tar:
    tar.extractall(target, filter="data")

for required in ("package.json", "dist/server.js", "node_modules"):
    if not (target / required).exists():
        sys.exit(f"The build output has no {required}")
print(f"Unpacked {sum(1 for _ in target.rglob('*'))} files into {target}")
