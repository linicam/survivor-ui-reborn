#!/usr/bin/env bash
# Build the installable AZ Reborn package: dist/SurvivorUI-Reborn.zip
#
#   bash scripts/package.sh
#
# Works in a clean checkout. No Lua / Node / npm needed to *use* the zip;
# building it needs only `zip` and python3 (both present in GitHub Actions
# ubuntu runners). The script:
#   1. validates the manifests and runtime files in the working tree,
#   2. stages exactly SurvivorUI/ + SurvivorPlates/ (+ LICENSE),
#   3. zips them with no parent directory inside the archive,
#   4. validates the finished archive (structure + every .toc file present).
# Fails loudly if anything is missing.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="dist/SurvivorUI-Reborn.zip"
STAGE="dist/staging"

echo "== validating working tree =="
python3 scripts/validate_addon.py

echo "== staging =="
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE"
cp -r SurvivorUI SurvivorPlates "$STAGE/"
cp LICENSE "$STAGE/"
# Never ship development-only files, even if they were added under an addon dir.
find "$STAGE" -name "*.pyc" -delete
find "$STAGE" -name ".DS_Store" -delete

echo "== zipping =="
mkdir -p dist
( cd "$STAGE" && zip -qr -X "../SurvivorUI-Reborn.zip" SurvivorUI SurvivorPlates LICENSE )

echo "== validating archive =="
python3 scripts/validate_addon.py --zip "$OUT"
unzip -l "$OUT" | head -n 20
echo
echo "Built: $OUT"
