#!/bin/bash
# Fails if any appearance style, mode and accent combination has text, accents or timeline marks below
# WCAG contrast minimums (Top3/Logic/ContrastCheck.swift). Runs as a build phase and from package.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${DERIVED_FILE_DIR:-${TMPDIR:-/tmp}}/contrast-check"
mkdir -p "$(dirname "$OUT")"
# Build-phase environments point SDKROOT at the target SDK; swiftc needs the macOS one either way.
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" xcrun --sdk macosx swiftc -O -suppress-warnings \
  Top3/Shared/StyleTokens.swift Top3/Logic/ContrastCheck.swift scripts/contrast/main.swift -o "$OUT"
"$OUT"
# A stamp for Xcode's dependency tracking, so the phase only reruns when the tokens change.
if [ -n "${DERIVED_FILE_DIR:-}" ]; then touch "$DERIVED_FILE_DIR/contrast-check.stamp"; fi
