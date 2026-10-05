#!/bin/bash
# Fails if any system-provided icon (SF Symbols) is referenced. ProTask uses its own set in Assets.xcassets/Icons.
cd "$(dirname "$0")/.."
if matches=$(grep -rnE "systemName|systemImage|(^|[^A-Za-z])Label\(" Top3 --include='*.swift'); then
  echo "System icons found (use Icon(...) from Views/Icon.swift instead):"
  echo "$matches"
  exit 1
fi
echo "Icon check passed: no SF Symbols in use."
