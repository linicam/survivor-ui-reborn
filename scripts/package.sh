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
# Stamp the build commit for diagnostic session traceability.
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
printf '%s\n' "-- Stamped by scripts/package.sh with the source commit at build time." \
	"SurvivorUI_RebornBuildCommit = \"$COMMIT\"" > "$STAGE/SurvivorUI/BuildInfo.lua"
# Never ship development-only files, even if they were added under an addon dir.
find "$STAGE" -name "*.pyc" -delete
find "$STAGE" -name ".DS_Store" -delete

echo "== zipping =="
mkdir -p dist
( cd "$STAGE" && zip -qr -X "../SurvivorUI-Reborn.zip" SurvivorUI SurvivorPlates LICENSE )

echo "== validating archive =="
python3 scripts/validate_addon.py --zip "$OUT"
unzip -l "$OUT" | head -n 20 || true
echo
echo "Built: $OUT"

echo "== building diagnostics helper =="
HELPER_OUT="dist/SurvivorUI-Reborn-Diagnostics-Helper.zip"
HELPER_STAGE="dist/helper-staging"
rm -rf "$HELPER_STAGE" "$HELPER_OUT"
mkdir -p "$HELPER_STAGE"
cp tools/diagnostics-helper/Upload-Diagnostics.bat "$HELPER_STAGE/"
cp tools/diagnostics-helper/Upload-Diagnostics.ps1 "$HELPER_STAGE/"
cp tools/diagnostics-helper/Test-Diagnostics.bat "$HELPER_STAGE/"; cp tools/diagnostics-helper/README.md "$HELPER_STAGE/"
( cd "$HELPER_STAGE" && zip -qr -X "../SurvivorUI-Reborn-Diagnostics-Helper.zip" . )
echo "Built: $HELPER_OUT"
