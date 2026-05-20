#!/usr/bin/env bash
# check_spelling.sh — Irish/British English spelling linter (Req 19.2).
# Scans *.swift files and bundled string catalogs for US-English spellings.
# Exits 0 if clean, 1 if any violations are found.
# CI usage: bash tools/check_spelling.sh

set -euo pipefail

# Allow tests to override REPO_ROOT via environment variable.
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# US-English words banned in favour of Irish/British spellings.
# Each entry is a standalone word boundary pattern.
BANNED_WORDS=(
    "recognized"
    "recognizes"
    "recognizing"
    "unrecognized"
    "color"
    "colors"
    "colored"
    "colorize"
    "colorization"
    "fiber"
    "fibers"
    "favorite"
    "favorites"
    "center"
    "centers"
    "centered"
    "centering"
    "analyze"
    "analyzes"
    "analyzed"
    "analyzing"
    "analyzer"
    "analyzers"
    "behavior"
    "behaviors"
    "caliber"
    "calibers"
    "neighbor"
    "neighbors"
    "honor"
    "honors"
    "honored"
    "flavor"
    "flavors"
    "harbor"
    "harbors"
    "humor"
    "labeling"
    "labeled"
    "modeling"
    "modeled"
    "traveling"
    "traveled"
    "canceled"
    "canceling"
    "minimized"
    "minimizing"
    "minimization"
    "optimize"
    "optimizes"
    "optimized"
    "optimizing"
    "optimization"
    "organize"
    "organizes"
    "organized"
    "organizing"
    "organization"
    "serialize"
    "serializes"
    "serialized"
    "serialization"
    "deserialize"
    "deserialized"
    "normalize"
    "normalized"
    "normalizing"
    "normalization"
    "initialize"
    "initializes"
    "initialized"
    "initializing"
    "initialization"
    "visualize"
    "visualized"
    "visualizing"
    "visualization"
    "synchronize"
    "synchronized"
    "synchronizing"
    "synchronization"
    "localize"
    "localized"
    "localizing"
    "localization"
    "specialize"
    "specialized"
    "specializing"
    "specialization"
)

# Build a single grep pattern: \b(word1|word2|...)\b (case-sensitive).
join_words() {
    local IFS="|"
    echo "${BANNED_WORDS[*]}"
}

PATTERN="\\b($(join_words))\\b"

# Directories / file globs to scan.
SCAN_TARGETS=(
    "${REPO_ROOT}/MedataCore/Sources"
    "${REPO_ROOT}/HarnessCore"
    "${REPO_ROOT}/HarnessCLI"
    "${REPO_ROOT}/App"
)

FOUND=0
for target in "${SCAN_TARGETS[@]}"; do
    if [[ ! -d "$target" ]]; then
        continue
    fi
    # grep -rn: recursive, line numbers. -E: extended regex. --include: limit to .swift.
    if grep -rEn --include="*.swift" "$PATTERN" "$target" 2>/dev/null; then
        FOUND=1
    fi
done

# Also scan Localizable string catalogs (xcstrings JSON) for user-facing strings.
XCSTRINGS_DIR="${REPO_ROOT}/App"
if [[ -d "$XCSTRINGS_DIR" ]]; then
    while IFS= read -r -d '' f; do
        if grep -En "$PATTERN" "$f" 2>/dev/null; then
            FOUND=1
        fi
    done < <(find "$XCSTRINGS_DIR" -name "*.xcstrings" -print0 2>/dev/null)
fi

if [[ $FOUND -ne 0 ]]; then
    echo "FAIL: US-English spellings found." >&2
    exit 1
fi

echo "OK: no US-English spellings found."
exit 0
