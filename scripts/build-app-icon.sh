#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_PATH="${1:-$ROOT_DIR/artwork/app-icon/source.png}"
OUTPUT_ICNS="${2:-$ROOT_DIR/artwork/app-icon/AppIcon.icns}"
OUTPUT_DIR="$(dirname "$OUTPUT_ICNS")"
OUTPUT_PREVIEW_PNG="$OUTPUT_DIR/AppIcon-1024.png"

if [[ ! -f "$INPUT_PATH" ]]; then
  echo "[icon] ERROR: input image not found at $INPUT_PATH" >&2
  exit 1
fi

if ! command -v sips >/dev/null 2>&1; then
  echo "[icon] ERROR: sips is required but not available" >&2
  exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
  echo "[icon] ERROR: iconutil is required but not available" >&2
  exit 1
fi

read -r WIDTH HEIGHT < <(
  sips -g pixelWidth -g pixelHeight "$INPUT_PATH" |
    awk '/pixelWidth:/ { width = $2 } /pixelHeight:/ { height = $2 } END { print width, height }'
)

if [[ -z "${WIDTH:-}" || -z "${HEIGHT:-}" ]]; then
  echo "[icon] ERROR: unable to read image dimensions from $INPUT_PATH" >&2
  exit 1
fi

SQUARE_SIZE=$(( WIDTH < HEIGHT ? WIDTH : HEIGHT ))
TMP_DIR="$(mktemp -d)"
ICONSET_DIR="$TMP_DIR/AppIcon.iconset"
SQUARE_SOURCE="$TMP_DIR/source-square.png"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR" "$ICONSET_DIR"

# Normalize to a centered square source so the icon is not slightly stretched.
sips -c "$SQUARE_SIZE" "$SQUARE_SIZE" "$INPUT_PATH" --out "$SQUARE_SOURCE" >/dev/null
sips -z 1024 1024 "$SQUARE_SOURCE" --out "$OUTPUT_PREVIEW_PNG" >/dev/null

for size in 16 32 128 256 512; do
  double_size=$(( size * 2 ))
  sips -z "$size" "$size" "$SQUARE_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  sips -z "$double_size" "$double_size" "$SQUARE_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

echo "[icon] Source:  $INPUT_PATH"
echo "[icon] Preview: $OUTPUT_PREVIEW_PNG"
echo "[icon] Output:  $OUTPUT_ICNS"
