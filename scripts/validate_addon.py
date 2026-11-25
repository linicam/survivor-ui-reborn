#!/usr/bin/env python3
"""Validate SurvivorUI / SurvivorPlates manifests and runtime files.

Usage:
    python3 scripts/validate_addon.py [--zip dist/SurvivorUI-Reborn.zip]
Without --zip it validates the working tree; with --zip it validates the
contents of the built archive (same checks, plus archive structure).
Exits non-zero with a clear message when anything is missing.
"""
import argparse
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDONS = ("SurvivorUI", "SurvivorPlates")


def read_toc_files(addon, members=None):
    toc = ROOT / addon / f"{addon}.toc"
    if members is not None:
        text = members[f"{addon}/{addon}.toc"]
    else:
        text = toc.read_text(encoding="utf-8", errors="replace")
    files = []
    interface = None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("## Interface:"):
            interface = line.split(":", 1)[1].strip()
        elif line and not line.startswith("##") and not line.startswith("#"):
            files.append(line)
    return interface, files


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--zip", dest="zip_path", default=None)
    args = parser.parse_args()

    members = None
    if args.zip_path:
        zf = zipfile.ZipFile(args.zip_path)
        members = {name: zf.read(name).decode("utf-8", errors="replace")
                   for name in zf.namelist() if name.endswith(".toc")}
        names = set(zf.namelist())
        # Archive structure: exactly the two addon folders (plus LICENSE at root).
        bad = [n for n in names
               if n.startswith("__") or ".git" in n or n.endswith((".pyc", ".DS_Store"))]
        if bad:
            print(f"FAIL: unexpected entries in zip: {bad[:10]}")
            return 1
        for addon in ADDONS:
            if f"{addon}/{addon}.toc" not in names:
                print(f"FAIL: zip is missing {addon}/{addon}.toc")
                return 1
        print(f"zip entries: {len(names)}")

    errors = []
    for addon in ADDONS:
        interface, files = read_toc_files(addon, members)
        if interface != "11200":
            errors.append(f"{addon}: Interface is {interface!r}, expected '11200'")
        if not files:
            errors.append(f"{addon}: no files listed in .toc")
        if "RebornCompat.lua" not in files and addon == "SurvivorUI":
            errors.append("SurvivorUI: RebornCompat.lua is not registered in the .toc")
        for f in files:
            rel = f"{addon}/{f}"
            if members is not None:
                if rel not in names:
                    errors.append(f"zip is missing {rel} (listed in {addon}.toc)")
            else:
                if not (ROOT / rel).is_file():
                    errors.append(f"missing file listed in {addon}.toc: {rel}")
        # Runtime assets that must ship even though the .toc does not list them.
        for required in ("Bindings.xml",):
            rel = f"{addon}/{required}"
            if members is not None:
                if rel not in names:
                    errors.append(f"zip is missing {rel}")
            elif not (ROOT / rel).is_file():
                errors.append(f"missing runtime file: {rel}")
        print(f"{addon}: Interface {interface}, {len(files)} files in .toc")

    if args.zip_path:
        for forbidden in ("tests/", "scripts/", ".github/", "installer/", "docs/"):
            if any(n.startswith(forbidden) or f"/{forbidden}" in n for n in names):
                errors.append(f"zip must not contain {forbidden}")

    if errors:
        for e in errors:
            print("FAIL: " + e)
        return 1
    print("OK: manifests and runtime files validate")
    return 0


if __name__ == "__main__":
    sys.exit(main())
