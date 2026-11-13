#!/usr/bin/env python3
"""Which files of common/ and targets/ replace a file of prog8lib/, and has
upstream changed any of those since the replacement was made?

    tools/check_overrides.py            compare with overrides.txt, report
    tools/check_overrides.py --record   write overrides.txt for the present state

overrides.txt holds, for each replacing file, the hash of the upstream file it
was made from.  After prog8lib/ is updated to a new upstream commit, a file
whose upstream hash differs is one where the replacement now hides a change:
look at the upstream diff, merge it into the replacement, then --record.
"""
import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "overrides.txt")


def digest(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def overrides():
    """(replacing file, upstream file) pairs, both relative to the root"""
    found = []
    common = os.path.join(ROOT, "common")
    for name in sorted(os.listdir(common)) if os.path.isdir(common) else []:
        if os.path.isfile(os.path.join(ROOT, "prog8lib", name)):
            found.append((f"common/{name}", f"prog8lib/{name}"))
    targets = os.path.join(ROOT, "targets")
    for base, _, files in sorted(os.walk(targets)):
        rel = os.path.relpath(base, targets)
        for name in sorted(files):
            upstream = os.path.join("prog8lib", rel, name)
            if os.path.isfile(os.path.join(ROOT, upstream)):
                found.append((f"targets/{rel}/{name}", upstream))
            elif os.sep not in rel and os.path.isfile(os.path.join(ROOT, "prog8lib", name)):
                # a machine's module of the same name as a shared one: it comes first
                found.append((f"targets/{rel}/{name}", f"prog8lib/{name}"))
    return found


def main():
    pairs = overrides()
    if "--record" in sys.argv:
        with open(MANIFEST, "w") as f:
            f.write("# replacing file, the upstream file it replaces, sha256 of that upstream file\n")
            for mine, theirs in pairs:
                f.write(f"{mine}\t{theirs}\t{digest(os.path.join(ROOT, theirs))}\n")
        print(f"recorded {len(pairs)} replaced files in overrides.txt")
        return 0
    recorded = {}
    if os.path.isfile(MANIFEST):
        for line in open(MANIFEST):
            if line.strip() and not line.startswith("#"):
                mine, theirs, sha = line.rstrip("\n").split("\t")
                recorded[mine] = (theirs, sha)
    stale = 0
    for mine, theirs in pairs:
        now = digest(os.path.join(ROOT, theirs))
        if mine not in recorded:
            print(f"not recorded:      {mine}  (replaces {theirs})")
            stale += 1
        elif recorded[mine][1] != now:
            print(f"UPSTREAM CHANGED:  {theirs}  is hidden by  {mine}")
            stale += 1
    for mine in sorted(set(recorded) - {m for m, _ in pairs}):
        print(f"no longer replaces anything: {mine}")
        stale += 1
    print(f"{len(pairs)} files replace an upstream file; {stale} to look at")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
