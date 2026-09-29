#!/usr/bin/env bash
#
# generate.sh — render the AppIcon PNG set from static/icon.svg.
#
# Renders the brand vector master (static/icon.svg, stroke #63ff00) at every
# Apple-required iOS AppIcon pixel size and writes a matching Contents.json into
# MeData/MeData/Assets.xcassets/AppIcon.appiconset/.
#
# Prefers rsvg-convert (crisp vector rasteriser); falls back to sips, which
# ships with macOS. Run once and commit the generated PNGs alongside this script.
#
#   ./tools/appicon/generate.sh
#
set -euo pipefail

# Resolve repo root from this script's location so it runs from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

SVG="${REPO_ROOT}/static/icon.svg"
ICONSET="${REPO_ROOT}/MeData/MeData/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "${SVG}" ]]; then
  echo "error: source SVG not found at ${SVG}" >&2
  exit 1
fi

mkdir -p "${ICONSET}"

# Unique pixel sizes required across all iOS AppIcon slots.
SIZES=(40 58 60 80 87 120 180 1024)

# Pick a rasteriser: rsvg-convert preferred, sips as the macOS fallback.
render() {
  local size="$1" out="$2"
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w "${size}" -h "${size}" "${SVG}" -o "${out}"
  elif command -v sips >/dev/null 2>&1; then
    sips -s format png --resampleHeightWidth "${size}" "${size}" "${SVG}" --out "${out}" >/dev/null
  else
    echo "error: neither rsvg-convert nor sips is available" >&2
    exit 1
  fi
}

echo "Rendering AppIcon PNGs from ${SVG}"
for size in "${SIZES[@]}"; do
  out="${ICONSET}/icon-${size}.png"
  render "${size}" "${out}"
  echo "  icon-${size}.png"
done

# Write Contents.json. The 120px file is shared by the 40pt@3x and 60pt@2x slots.
cat > "${ICONSET}/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "icon-40.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "20x20"
    },
    {
      "filename" : "icon-60.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "20x20"
    },
    {
      "filename" : "icon-58.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "29x29"
    },
    {
      "filename" : "icon-87.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "29x29"
    },
    {
      "filename" : "icon-80.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "40x40"
    },
    {
      "filename" : "icon-120.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "40x40"
    },
    {
      "filename" : "icon-120.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "60x60"
    },
    {
      "filename" : "icon-180.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "60x60"
    },
    {
      "filename" : "icon-1024.png",
      "idiom" : "ios-marketing",
      "scale" : "1x",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "Wrote Contents.json"
echo "Done."
