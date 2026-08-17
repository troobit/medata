#!/usr/bin/env bash
# check_surfaces.sh — UI surface catalogue linter.
#
# Checks design-system/surfaces.md against the code it claims to describe.
# Four checks, in order:
#   1. every SwiftUI-ish struct in App/ and MeData/MeDataWidgets/ has a
#      catalogue row, or an `exempt:<Name>` marker with a reason in the same
#      row                                                                  FAILS
#   2. every case of each named state enum appears in a `state source` cell
#      as `<Enum>.<case>`                                                   FAILS
#   3. coverage ratchet — covered=N total=M against tools/surfaces_baseline.txt
#      (a row alone is not coverage; the row must be status `shipped`)      FAILS on regression
#   4. layer report — App/*View.swift and App/*Sheet.swift importing a
#      MedataCore module directly                                          REPORT-ONLY
#
# Output is compact key=value lines. Exits 0 if checks 1–3 pass, 1 otherwise.
# CI / developer usage: make surfaces   (or: bash tools/check_surfaces.sh)
#
# Overrides, for testing against a fixture:
#   REPO_ROOT, SURFACES_CATALOGUE, SURFACES_BASELINE_FILE

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CATALOGUE="${SURFACES_CATALOGUE:-${REPO_ROOT}/design-system/surfaces.md}"
BASELINE_FILE="${SURFACES_BASELINE_FILE:-${REPO_ROOT}/tools/surfaces_baseline.txt}"

# Declaration scan roots. Widgets live outside App/ but are UI all the same.
SCAN_DIRS=("${REPO_ROOT}/App" "${REPO_ROOT}/MeData/MeDataWidgets")

# Protocols that make a struct a surface (or a piece of one). Deliberately
# wider than `: View` — ChipFlow: Layout, MaskContourShape: Shape,
# ARPreviewView: UIViewRepresentable and ShareSheet:
# UIViewControllerRepresentable are all invisible to a `struct .*: View` grep,
# and ChipFlow is exactly the component a UI attempt once silently deleted.
CONFORMANCES="View|Shape|Layout|UIViewRepresentable|UIViewControllerRepresentable|Widget"

# The named state enums. The NAMES are an editorial choice and are listed here;
# their CASES are parsed out of the Swift source, never hard-coded, so renaming
# or adding a case shows up as a catalogue miss rather than passing silently.
STATE_ENUMS="CaptureState ConfidenceLevel CalibrationBannerState PlateFraction \
ShutterButtonState TiltGuideState CaptureStage MealRoute CaptureRoute PermissionSubject"

# Catalogue header, normalised to lowercase with collapsed whitespace.
REQUIRED_COLUMNS="id|surface|file|kind|state|state source|view-model|data|direction|archive|status"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# ---------------------------------------------------------------- catalogue --

[[ -f "$CATALOGUE" ]] || fail "catalogue not found: ${CATALOGUE#"$REPO_ROOT"/} — write it before running this check."

# Split the markdown table into a header row and data rows. Separator rows
# (|---|---|) are dropped; the first pipe row in the file is the header.
awk -F'|' '
  /^[ \t]*\|/ {
    row = $0
    gsub(/^[ \t]*\|[ \t]*/, "", row); gsub(/[ \t]*\|[ \t]*$/, "", row)
    if (row ~ /^[ \t:|*-]+$/) next          # |---|:--:|  alignment row
    gsub(/[ \t]*\|[ \t]*/, "\t", row)
    if (!seen_header) { print row > headerfile; seen_header = 1; next }
    print row
  }
' headerfile="$WORK/header.tsv" "$CATALOGUE" > "$WORK/cells.tsv"

[[ -s "$WORK/header.tsv" ]] || fail "no markdown table found in ${CATALOGUE#"$REPO_ROOT"/} — expected a header row of | id | surface | file | ... |"

# Normalise the header and locate the columns the checks read.
awk -F'\t' -v want="$REQUIRED_COLUMNS" '
  {
    for (i = 1; i <= NF; i++) {
      h = tolower($i); gsub(/^[ \t]+|[ \t]+$/, "", h); gsub(/[ \t]+/, " ", h)
      col[h] = i
    }
    n = split(want, req, "|")
    missing = ""
    for (j = 1; j <= n; j++) if (!(req[j] in col)) missing = missing (missing ? "," : "") req[j]
    print "MISSING\t" missing
    print "IDX\t" col["id"] "\t" col["state source"] "\t" col["status"]
  }
' "$WORK/header.tsv" > "$WORK/header.info"

MISSING_COLUMNS=$(awk -F'\t' '$1=="MISSING"{print $2}' "$WORK/header.info")
[[ -z "$MISSING_COLUMNS" ]] || fail "catalogue header is incomplete — missing columns: ${MISSING_COLUMNS}"

STATE_SOURCE_COL=$(awk -F'\t' '$1=="IDX"{print $3}' "$WORK/header.info")
STATUS_COL=$(awk -F'\t' '$1=="IDX"{print $4}' "$WORK/header.info")
CATALOGUE_ROWS=$(wc -l < "$WORK/cells.tsv" | tr -d ' ')

echo "catalogue=${CATALOGUE#"$REPO_ROOT"/} rows=${CATALOGUE_ROWS}"
[[ "$CATALOGUE_ROWS" -gt 0 ]] || fail "catalogue has a header but no rows — nothing to check against."

# ------------------------------------------------ check 1: struct coverage --

# Walk every Swift file, tracking brace depth so nested declarations get a
# qualified name (MedataLoadingSymbol.Bowl, not a bare Bowl). Comments and
# string literals are blanked before brace counting so a `{` in prose cannot
# shift the depth. Generic parameter clauses are stripped naively (`<[^>]*>`),
# which is enough for this codebase — no App/ struct nests angle brackets.
# shellcheck disable=SC2016  # the $ signs below are awk fields, not shell vars
find "${SCAN_DIRS[@]}" -name '*.swift' -print0 2>/dev/null \
  | xargs -0 awk -v conf="$CONFORMANCES" '
  function qualifier(  d, s) { s = ""; for (d = 1; d <= depth; d++) if (names[d] != "") s = s names[d] "."; return s }
  FNR == 1 { depth = 0; for (k in names) names[k] = "" }
  {
    work = $0
    sub(/\/\/.*$/, "", work)
    gsub(/"[^"]*"/, "", work)

    t = work
    sub(/^[ \t]+/, "", t)
    while (t ~ /^(public|internal|private|fileprivate|package|final|indirect|open|@[A-Za-z_]+)[ \t]+/) sub(/^[@A-Za-z_]+[ \t]+/, "", t)

    pending = ""
    if (t ~ /^(struct|class|enum|actor|protocol|extension)[ \t]+[A-Za-z_]/) {
      kind = t; sub(/[ \t].*$/, "", kind)
      tail = t; sub(/^[a-z]+[ \t]+/, "", tail)
      name = tail; sub(/[^A-Za-z0-9_].*$/, "", name)
      pending = name
      sub(/^[A-Za-z0-9_]+/, "", tail)
      sub(/^<[^>]*>/, "", tail)
      if (kind == "struct" && tail ~ /^[ \t]*:/) {
        sub(/^[ \t]*:/, "", tail)
        sub(/\{.*$/, "", tail)
        sub(/[ \t]+where[ \t].*$/, "", tail)
        n = split(tail, parts, ",")
        for (i = 1; i <= n; i++) {
          p = parts[i]; gsub(/[ \t]/, "", p); sub(/<.*$/, "", p)
          if (p ~ "^(" conf ")$") { print FILENAME "\t" FNR "\t" qualifier() name "\t" name "\t" p; break }
        }
      }
    }

    before = depth
    opens = gsub(/\{/, "{", work); closes = gsub(/\}/, "}", work)
    depth = before + opens - closes
    if (depth < 0) depth = 0
    if (pending != "" && depth > before) names[depth] = pending
    for (k = depth + 1; k <= before + opens; k++) names[k] = ""
  }
' | sort -u > "$WORK/structs.tsv"

STRUCTS_TOTAL=$(wc -l < "$WORK/structs.tsv" | tr -d ' ')
: > "$WORK/struct_missing.txt"
: > "$WORK/struct_exempt.txt"
: > "$WORK/struct_shipped.txt"

# Normalise the exemption markers before either search touches them. The
# catalogue writes an exemption as a table row — | exempt: `A`, `B` | file |
# reason | — so the backticks are stripped, the space after the colon is
# dropped, and a comma-separated list is expanded to one `exempt:<Name>` marker
# per name. Without this a marker reading `exempt: `ChipFlow`` would neither
# excuse ChipFlow nor be blanked from the coverage corpus, so the row would
# quietly count as coverage for the very struct it fails to excuse.
awk -F'\t' 'BEGIN { OFS = "\t" }
  /exempt:/ {
    for (i = 1; i <= NF; i++) {
      if ($i !~ /exempt:/) continue
      cell = $i; gsub(/`/, "", cell)
      head = cell; sub(/exempt:.*$/, "", head)
      list = cell; sub(/^.*exempt:[ \t]*/, "", list)
      n = split(list, nm, ",")
      markers = ""
      for (k = 1; k <= n; k++) {
        t = nm[k]; gsub(/^[ \t]+|[ \t]+$/, "", t)
        if (t != "") markers = markers "exempt:" t " "
      }
      $i = head markers
    }
  }
  { print }
' "$WORK/cells.tsv" > "$WORK/cells_exempt.tsv"

# Coverage is searched over a copy with the exemption markers blanked out, so a
# bare `exempt:ChipFlow` cannot satisfy the whole-word rule by naming the very
# struct it fails to excuse.
sed -E 's/exempt:[A-Za-z0-9_.]*//g' "$WORK/cells_exempt.tsv" > "$WORK/cells_search.tsv"

while IFS=$'\t' read -r sfile sline qual bare proto; do
    [[ -n "$bare" ]] || continue
    # An exemption is `exempt:<Name>` with a reason later in the same row — the
    # reason is required, so an exemption cannot lose its justification.
    if grep -qE "(^|[[:space:]|])exempt:(${qual//./\\.}|${bare})[[:space:]]+[^[:space:]|].{9,}" "$WORK/cells_exempt.tsv"; then
        echo "${qual}" >> "$WORK/struct_exempt.txt"
        continue
    fi
    # `.` is excluded from the boundary so that `exempt:ResultView.FoodRow`
    # is not read as a reasonless exemption of `ResultView`.
    if grep -qE "(^|[[:space:]|])exempt:(${qual//./\\.}|${bare})([^A-Za-z0-9_.]|\$)" "$WORK/cells_exempt.tsv"; then
        echo "exempt_no_reason struct=${qual} at=${sfile#"$REPO_ROOT"/}:${sline} — an exemption needs a reason in the same row." >> "$WORK/struct_missing.txt"
        continue
    fi
    # Covered when the qualified or bare name appears as a whole word in a row
    # — normally via the `file` cell for a top-level view, or named explicitly
    # for a nested or private component.
    if grep -qE "(^|[^A-Za-z0-9_.])(${qual//./\\.}|${bare})([^A-Za-z0-9_]|\$)" "$WORK/cells_search.tsv"; then
        if awk -F'\t' -v c="$STATUS_COL" -v q="$qual" -v b="$bare" '
             $0 ~ ("(^|[^A-Za-z0-9_.])(" q "|" b ")([^A-Za-z0-9_]|$)") && tolower($c) ~ /shipped/ { found = 1 }
             END { exit !found }' "$WORK/cells_search.tsv"; then
            echo "${qual}" >> "$WORK/struct_shipped.txt"
        fi
        continue
    fi
    echo "missing_row struct=${qual} proto=${proto} at=${sfile#"$REPO_ROOT"/}:${sline}" >> "$WORK/struct_missing.txt"
done < "$WORK/structs.tsv"

STRUCTS_EXEMPT=$(wc -l < "$WORK/struct_exempt.txt" | tr -d ' ')
STRUCTS_MISSING=$(wc -l < "$WORK/struct_missing.txt" | tr -d ' ')
[[ "$STRUCTS_MISSING" -eq 0 ]] || cat "$WORK/struct_missing.txt"
echo "structs=${STRUCTS_TOTAL} missing=${STRUCTS_MISSING} exempt=${STRUCTS_EXEMPT}"

# ------------------------------------------------ check 2: state enum cases --

: > "$WORK/enum_missing.txt"
ENUM_CASES=0
ENUM_CASES_MISSING=0
ENUMS_NOT_FOUND=0

for enum_name in $STATE_ENUMS; do
    enum_file=$(grep -rlE "(^|[^A-Za-z0-9_])enum ${enum_name}[[:space:]:{]" --include='*.swift' "${SCAN_DIRS[@]}" 2>/dev/null | head -1 || true)
    if [[ -z "$enum_file" ]]; then
        echo "enum_not_found enum=${enum_name} — named as a state enum but no declaration in App/ or MeData/MeDataWidgets/" >> "$WORK/enum_missing.txt"
        ENUMS_NOT_FOUND=$((ENUMS_NOT_FOUND + 1))
        continue
    fi
    # Cases at the enum body's own brace depth only — this is what keeps the
    # `case .veryLow:` arms of a switch inside `var label` out of the list.
    cases=$(awk -v target="$enum_name" '
      {
        work = $0; sub(/\/\/.*$/, "", work); gsub(/"[^"]*"/, "", work)
        if (active && depth == body && work ~ /^[ \t]*case[ \t]+[A-Za-z_]/) {
          line = work; sub(/^[ \t]*case[ \t]+/, "", line)
          # Drop associated-value lists before splitting on commas, so that
          # `case capturing(stage: CaptureStage, frozen: GatingSnapshot)`
          # yields one case and not three.
          while (sub(/\([^()]*\)/, "", line)) { }
          n = split(line, items, ",")
          for (i = 1; i <= n; i++) {
            c = items[i]; gsub(/^[ \t]+|[ \t]+$/, "", c); sub(/[^A-Za-z0-9_].*$/, "", c)
            if (c != "") print c
          }
        }
        before = depth
        depth += gsub(/\{/, "{", work) - gsub(/\}/, "}", work)
        if (!active && work ~ ("(^|[^A-Za-z0-9_])enum[ \t]+" target "[ \t:{]") && depth > before) { active = 1; body = depth }
        if (active && depth < body) active = 0
      }
    ' "$enum_file")
    case_count=$(printf '%s' "$cases" | grep -c . || true)
    ENUM_CASES=$((ENUM_CASES + case_count))
    if [[ "$case_count" -eq 0 ]]; then
        # A namespace enum (static members only) has no states to catalogue.
        echo "enum=${enum_name} cases=0 note=namespace-enum"
        continue
    fi
    for c in $cases; do
        if ! awk -F'\t' -v col="$STATE_SOURCE_COL" -v needle="${enum_name}.${c}" '
             index($col, needle) { n = index($col, needle) + length(needle)
                                   rest = substr($col, n, 1)
                                   if (rest !~ /[A-Za-z0-9_]/) found = 1 }
             END { exit !found }' "$WORK/cells.tsv"; then
            echo "missing_state enum=${enum_name} case=${c} expected_state_source=${enum_name}.${c} at=${enum_file#"$REPO_ROOT"/}" >> "$WORK/enum_missing.txt"
            ENUM_CASES_MISSING=$((ENUM_CASES_MISSING + 1))
        fi
    done
done

[[ ! -s "$WORK/enum_missing.txt" ]] || cat "$WORK/enum_missing.txt"
echo "enum_cases=${ENUM_CASES} missing=${ENUM_CASES_MISSING} enums_not_found=${ENUMS_NOT_FOUND}"

# ------------------------------------------------- check 3: coverage ratchet --

# Coverage is deliberately stricter than check 1: a struct counts as covered
# only when one of its rows is status `shipped`. A catalogue full of `planned`
# rows therefore passes check 1 and still reports covered=0, which is the point
# — a green boolean over unwritten rows is worse than a visibly absent file.
COVERED=$(sort -u "$WORK/struct_shipped.txt" | grep -c . || true)
TOTAL=$((STRUCTS_TOTAL - STRUCTS_EXEMPT))

BASELINE=0
if [[ -f "$BASELINE_FILE" ]]; then
    BASELINE=$(awk -F'=' '/^covered_min=/ { print $2 }' "$BASELINE_FILE" | tr -d '[:space:]')
    [[ "$BASELINE" =~ ^[0-9]+$ ]] || fail "baseline file ${BASELINE_FILE#"$REPO_ROOT"/} has no valid covered_min= line."
else
    echo "baseline_file=absent path=${BASELINE_FILE#"$REPO_ROOT"/}"
fi
echo "covered=${COVERED} total=${TOTAL} baseline=${BASELINE}"

RATCHET_OK=1
if [[ "$COVERED" -lt "$BASELINE" ]]; then
    echo "ratchet_regression covered=${COVERED} baseline=${BASELINE} — a surface lost its shipped row." >&2
    RATCHET_OK=0
elif [[ "$COVERED" -gt "$BASELINE" ]]; then
    echo "ratchet_raise set covered_min=${COVERED} in ${BASELINE_FILE#"$REPO_ROOT"/} to lock this in."
fi

# ------------------------------------------------ check 4: layer report (D5) --

# Report-only, by design. 19 of the 22 App/*View.swift + App/*Sheet.swift files
# already import a MedataCore module directly; failing on that today would just
# get the whole check switched off. The module list is read off the source tree
# so it cannot rot.
CORE_MODULES=$(find "${REPO_ROOT}/MedataCore/Sources" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
               | sed 's|.*/||' | sort | tr '\n' '|' | sed 's/|$//')
LAYER_VIOLATIONS=0
if [[ -n "$CORE_MODULES" ]]; then
    for vf in "${REPO_ROOT}"/App/*View.swift "${REPO_ROOT}"/App/*Sheet.swift; do
        [[ -f "$vf" ]] || continue
        mods=$(grep -hE "^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)?import[[:space:]]+(${CORE_MODULES})[[:space:]]*$" "$vf" 2>/dev/null \
               | sed -E 's/.*import[[:space:]]+//' | tr -d ' ' | sort -u | tr '\n' ',' | sed 's/,$//' || true)
        if [[ -n "$mods" ]]; then
            echo "layer file=${vf#"$REPO_ROOT"/} imports=${mods}"
            LAYER_VIOLATIONS=$((LAYER_VIOLATIONS + 1))
        fi
    done
fi
echo "layer_violations=${LAYER_VIOLATIONS} (report-only)"

# ------------------------------------------------------------------ verdict --

if [[ "$STRUCTS_MISSING" -ne 0 || "$ENUM_CASES_MISSING" -ne 0 || "$ENUMS_NOT_FOUND" -ne 0 || "$RATCHET_OK" -ne 1 ]]; then
    echo "FAIL: surface catalogue is out of step with the code." >&2
    exit 1
fi

echo "OK: every surface and state enum case has a catalogue row."
exit 0
