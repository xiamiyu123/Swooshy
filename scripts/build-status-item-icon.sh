#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SOURCE_PATH="${1:-$ROOT_DIR/artwork/status-item/source.png}"
OUTPUT_PNG_PATH="${2:-$ROOT_DIR/Sources/Swooshy/Resources/StatusItem/SwooshyStatusTemplate.png}"
OUTPUT_PDF_PATH="${3:-$ROOT_DIR/Sources/Swooshy/Resources/StatusItem/SwooshyStatusTemplate.pdf}"

uv run --with pillow python3 scripts/build-status-item-icon.py "$SOURCE_PATH" "$OUTPUT_PNG_PATH"

if command -v sips >/dev/null 2>&1; then
  sips -s format pdf "$OUTPUT_PNG_PATH" --out "$OUTPUT_PDF_PATH" >/dev/null
  echo "[status-item] PDF: $OUTPUT_PDF_PATH"
else
  echo "[status-item] WARN: sips unavailable, skipped PDF output" >&2
fi
