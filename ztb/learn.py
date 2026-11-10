#!/usr/bin/env python3
"""Suggest the policy's known program list from several clean builds.

Programs seen in every build go in the list. Programs seen in only some builds
are printed separately for a person to decide on. Paste the result into
policy/build-policy.toml after reviewing it; this never edits the policy.

Usage: python3 ztb/learn.py <evidence-dir> [<evidence-dir> ...]
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from judge import in_sandbox, read_events  # noqa: E402


def programs_in(evidence):
    container_id = (Path(evidence) / "builds" / "sandbox.cid").read_text().strip()
    found = set()
    for event in read_events(Path(evidence) / "sensor"):
        process = event.get("process_exec", {}).get("process", {})
        if in_sandbox(process, container_id):
            found.add(process.get("binary", ""))
    return found


def learn(builds):
    """Return (in every build, in only some builds)."""
    always = set.intersection(*builds)
    sometimes = set.union(*builds) - always
    return sorted(always), sorted(sometimes)


def main():
    folders = sys.argv[1:]
    if not folders:
        sys.exit(__doc__)
    builds = [programs_in(folder) for folder in folders]
    for folder, found in zip(folders, builds):
        if not found:
            sys.exit(f"{folder}: no sandbox programs found, so this evidence can't be learned from")
    always, sometimes = learn(builds)

    print(f"# Learned from {len(builds)} clean builds.")
    print("known = [")
    for binary in always:
        print(f'  "{binary}",')
    print("]")
    if sometimes:
        print("\n# Seen in only some builds. Check each one before adding it:")
        for binary in sometimes:
            print(f"#   {binary}")


if __name__ == "__main__":
    main()
