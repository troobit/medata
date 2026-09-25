#!/usr/bin/env bash
# check_surfaces.sh — UI surface catalogue linter.
#
# Checks design-system/surfaces.md against the code and the wireframes it claims
# to describe. Six checks, in order:
#   1. every SwiftUI-ish struct/enum/class/actor in App/ and
#      MeData/MeDataWidgets/ is named in the `surface` or `file` column of a
#      catalogue row, or carries an `exempt:<Name>` marker with a reason      FAILS
#   2. every case of every state enum named in the catalogue's own Coverage
#      table appears in a `state source` cell as `<Enum>.<case>`, unless the
#      baseline file allows that case by name                                 FAILS
#   3. ratchet — covered=N rows=M against tools/surfaces_baseline.txt
#      (a row alone is not coverage; the row must be status `shipped`)        FAILS on regression
#   4. every `data-zone` in design-system/wireframes/**/*.html and every zone
#      cited in a composition.md is declared in the catalogue's Zones lists    FAILS
#   5. every catalogue id cited in the Successor mapping resolves to a row     FAILS
#   6. layer report — App/*View.swift and App/*Sheet.swift importing a
#      MedataCore module directly                                            REPORT-ONLY
#
# Output is compact key=value lines. Exits 0 if checks 1–5 pass, 1 otherwise.
# CI / developer usage: make surfaces   (or: bash tools/check_surfaces.sh)
#
# Overrides, for testing against a fixture:
#   REPO_ROOT, SURFACES_CATALOGUE, SURFACES_BASELINE_FILE, SURFACES_WIREFRAME_DIR
#
# Portability: system bash 3.2 and BSD userland. Every corpus this script greps
# is written with a leading and a trailing tab, so a name at the start or the
# end of a cell still has a boundary character beside it and the word-boundary
# patterns need no `^`/`$` alternation. That is deliberate: `(^|[^A-Za-z0-9_.])`
# is not portable across the greps that turn up on a developer's PATH — BSD grep
# 2.6.0 matches it against a line beginning with the name, ugrep 7.8.4 does not,
# and `make surfaces` runs whichever one is found.

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CATALOGUE="${SURFACES_CATALOGUE:-${REPO_ROOT}/design-system/surfaces.md}"
BASELINE_FILE="${SURFACES_BASELINE_FILE:-${REPO_ROOT}/tools/surfaces_baseline.txt}"
WIREFRAME_DIR="${SURFACES_WIREFRAME_DIR:-${REPO_ROOT}/design-system/wireframes}"

# Declaration scan roots. Widgets live outside App/ but are UI all the same.
SCAN_DIRS=("${REPO_ROOT}/App" "${REPO_ROOT}/MeData/MeDataWidgets")

# Protocols that make a declaration a surface (or a piece of one). Deliberately
# wider than `: View` — ChipFlow: Layout, MaskContourShape: Shape,
# ARPreviewView: UIViewRepresentable, ShareSheet: UIViewControllerRepresentable,
# MedataApp: App and MeDataWidgetBundle: WidgetBundle are all invisible to a
# `struct .*: View` grep, and ChipFlow is exactly the component a UI attempt
# once silently deleted. Scene, ViewModifier and the style protocols have no
# conformer in the tree today; they are listed so that the first one to appear
# is caught rather than waved through.
CONFORMANCES="View|Shape|Layout|UIViewRepresentable|UIViewControllerRepresentable|Widget|WidgetBundle|App|Scene|ViewModifier|ButtonStyle|LabelStyle|ToggleStyle|ProgressViewStyle|InsettableShape"

# Catalogue header, normalised to lowercase with collapsed whitespace.
REQUIRED_COLUMNS="id|surface|file|kind|state|state source|view-model|data|direction|archive|status"
COLUMN_COUNT=11

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# ---------------------------------------------------------------- catalogue --

[[ -f "$CATALOGUE" ]] || fail "catalogue not found: ${CATALOGUE#"$REPO_ROOT"/} — write it before running this check."

CATALOGUE_REL="${CATALOGUE#"$REPO_ROOT"/}"

# Split the markdown table into a header row and data rows. Separator rows
# (|---|---|) are dropped; the first pipe row in the file is the header. Rows
# from the file's other tables (Exemptions, Successor mapping, Coverage) come
# through too — the exemption search below needs them.
awk -F'|' '
  /^[ \t]*\|/ {
    row = $0
    gsub(/^[ \t]*\|[ \t]*/, "", row); gsub(/[ \t]*\|[ \t]*$/, "", row)
    if (row ~ /^[ \t:|*-]+$/) next          # |---|:--:|  alignment row
    gsub(/[ \t]*\|[ \t]*/, "\t", row)
    if (!seen_header) { print row > headerfile; seen_header = 1; next }
    print FNR "\t" row
  }
' headerfile="$WORK/header.tsv" "$CATALOGUE" > "$WORK/cells.tsv"

[[ -s "$WORK/header.tsv" ]] || fail "no markdown table found in ${CATALOGUE_REL} — expected a header row of | id | surface | file | ... |"

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
    print "IDX\t" col["id"] "\t" col["surface"] "\t" col["file"] "\t" col["state source"] "\t" col["status"]
  }
' "$WORK/header.tsv" > "$WORK/header.info"

MISSING_COLUMNS=$(awk -F'\t' '$1=="MISSING"{print $2}' "$WORK/header.info")
[[ -z "$MISSING_COLUMNS" ]] || fail "catalogue header is incomplete — missing columns: ${MISSING_COLUMNS}"

ID_COL=$(awk -F'\t' '$1=="IDX"{print $2}' "$WORK/header.info")
SURFACE_COL=$(awk -F'\t' '$1=="IDX"{print $3}' "$WORK/header.info")
FILE_COL=$(awk -F'\t' '$1=="IDX"{print $4}' "$WORK/header.info")
STATE_SOURCE_COL=$(awk -F'\t' '$1=="IDX"{print $5}' "$WORK/header.info")
STATUS_COL=$(awk -F'\t' '$1=="IDX"{print $6}' "$WORK/header.info")

# The catalogue rows proper: the file's other tables are narrower, and each
# section repeats the header, which is not a row. Field 1 is the source line.
awk -F'\t' -v want="$COLUMN_COUNT" -v idc="$ID_COL" '
  NF == want + 1 && tolower($(idc + 1)) != "id" { print }
' "$WORK/cells.tsv" > "$WORK/rows.tsv"

CATALOGUE_ROWS=$(wc -l < "$WORK/rows.tsv" | tr -d ' ')
echo "catalogue=${CATALOGUE_REL} rows=${CATALOGUE_ROWS}"
[[ "$CATALOGUE_ROWS" -gt 0 ]] || fail "catalogue has a header but no rows — nothing to check against."

# Per-column extracts. Each line is wrapped in tabs — see the portability note
# at the top of this file.
awk -F'\t' -v s="$SURFACE_COL" -v f="$FILE_COL" '{ print "\t" $(s+1) "\t" $(f+1) "\t" }' "$WORK/rows.tsv" > "$WORK/cov_names.tsv"
awk -F'\t' -v s="$SURFACE_COL" -v f="$FILE_COL" -v st="$STATUS_COL" '
  tolower($(st+1)) ~ /shipped/ { print "\t" $(s+1) "\t" $(f+1) "\t" }' "$WORK/rows.tsv" > "$WORK/cov_shipped.tsv"
awk -F'\t' -v c="$STATE_SOURCE_COL" '{ print "\t" $(c+1) "\t" }' "$WORK/rows.tsv" > "$WORK/state_source.txt"
awk -F'\t' -v c="$ID_COL" '{ print $(c+1) }' "$WORK/rows.tsv" | sort -u > "$WORK/ids.txt"

# ------------------------------------------------ check 1: struct coverage --

# Walk every Swift file, tracking brace depth so nested declarations get a
# qualified name (MedataSymbolGeometry.Bowl, not a bare Bowl). Comments and
# string literals are blanked before brace counting so a `{` in prose cannot
# shift the depth. Generic parameter clauses are stripped naively (`<[^>]*>`),
# which is enough for this codebase — no App/ declaration nests angle brackets.
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
      # A surface is not always a struct: `App` is conformed to by a struct
      # today, but a class, an actor or an enum can render just as well, and a
      # gate on `struct` alone would wave any of them through.
      if (kind ~ /^(struct|class|enum|actor)$/ && tail ~ /^[ \t]*:/) {
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
  { print "\t" $0 "\t" }
' "$WORK/cells.tsv" > "$WORK/cells_exempt.tsv"

while IFS=$'\t' read -r sfile sline qual bare proto; do
    [[ -n "$bare" ]] || continue
    # An exemption is `exempt:<Name>` with a reason later in the same row — the
    # reason is required, so an exemption cannot lose its justification.
    if grep -qE "[[:space:]|]exempt:(${qual//./\\.}|${bare})[[:space:]]+[^[:space:]|].{9,}" "$WORK/cells_exempt.tsv"; then
        echo "${qual}" >> "$WORK/struct_exempt.txt"
        continue
    fi
    # `.` is excluded from the boundary so that `exempt:ResultView.FoodRow`
    # is not read as a reasonless exemption of `ResultView`.
    if grep -qE "[[:space:]|]exempt:(${qual//./\\.}|${bare})[^A-Za-z0-9_.]" "$WORK/cells_exempt.tsv"; then
        echo "exempt_no_reason struct=${qual} at=${sfile#"$REPO_ROOT"/}:${sline} — an exemption needs a reason in the same row." >> "$WORK/struct_missing.txt"
        continue
    fi
    # Covered when the qualified or bare name appears as a whole word in the
    # `surface` or `file` cell of a row. Only those two columns: a name that
    # merely turns up in some other row's prose — `ShareSheet` is named in two
    # `state` cells it does not belong to — is a mention, not a catalogue entry,
    # and used to make the row that does describe it deletable.
    if grep -qE "[^A-Za-z0-9_.](${qual//./\\.}|${bare})[^A-Za-z0-9_]" "$WORK/cov_names.tsv"; then
        if grep -qE "[^A-Za-z0-9_.](${qual//./\\.}|${bare})[^A-Za-z0-9_]" "$WORK/cov_shipped.tsv"; then
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

# --------------------------------------------------------------- baseline --

BASELINE_REL="${BASELINE_FILE#"$REPO_ROOT"/}"
COVERED_MIN=0
ROWS_MIN=0
: > "$WORK/uncited_allowed.txt"
if [[ -f "$BASELINE_FILE" ]]; then
    COVERED_MIN=$(awk -F'=' '/^covered_min=/ { print $2 }' "$BASELINE_FILE" | tr -d '[:space:]')
    ROWS_MIN=$(awk -F'=' '/^rows_min=/ { print $2 }' "$BASELINE_FILE" | tr -d '[:space:]')
    [[ "$COVERED_MIN" =~ ^[0-9]+$ ]] || fail "baseline file ${BASELINE_REL} has no valid covered_min= line."
    [[ "$ROWS_MIN" =~ ^[0-9]+$ ]] || fail "baseline file ${BASELINE_REL} has no valid rows_min= line."
    # uncited_cases=<Enum>:<case> <case> … — cases the catalogue covers by row
    # without naming them in a `state source` cell. Each line carries its reason
    # in the comment above it; closing one is a ratchet_raise.
    awk -F'=' '/^uncited_cases=/ {
        line = $2; sub(/[ \t]*#.*$/, "", line)
        split(line, a, ":")
        n = split(a[2], cs, /[ \t]+/)
        for (i = 1; i <= n; i++) if (cs[i] != "") print a[1] "." cs[i]
    }' "$BASELINE_FILE" | sort -u > "$WORK/uncited_allowed.txt"
else
    echo "baseline_file=absent path=${BASELINE_REL}"
fi
UNCITED_ALLOWED=$(wc -l < "$WORK/uncited_allowed.txt" | tr -d ' ')

# ------------------------------------------------ check 2: state enum cases --

# The enums are read out of the catalogue's own Coverage table — name and file
# both — so adding a row there puts the enum under the check, and a wrong path
# is a failure rather than a silent skip. The CASES are parsed from the Swift
# source, never from the table, so renaming or adding a case shows up as a
# catalogue miss rather than passing silently.
awk '
  /^### iOS detail/ { ios = 1 }
  /^### web-v0 detail/ { ios = 0 }
  ios && /^\| *`[A-Za-z_][A-Za-z0-9_.]*` *\| *[A-Za-z]/ {
    split($0, f, "|")
    nm = f[2]; gsub(/[` \t]/, "", nm)
    fl = f[3]; gsub(/^[ \t]+|[ \t]+$/, "", fl)
    print nm "\t" fl "\t" FNR
  }
' "$CATALOGUE" | sort -u > "$WORK/state_enums.tsv"

: > "$WORK/enum_missing.txt"
STATE_ENUMS=$(wc -l < "$WORK/state_enums.tsv" | tr -d ' ')
ENUM_CASES=0
ENUM_CASES_MISSING=0
ENUM_CASES_UNCITED=0
ENUMS_NOT_FOUND=0

[[ "$STATE_ENUMS" -gt 0 ]] || fail "no state enums found in ${CATALOGUE_REL} — expected an '### iOS detail' section with a | enum | file | cases | rows | table."

while IFS=$'\t' read -r enum_name enum_file enum_line; do
    # `AppRoot.ActiveSheet` is declared in Swift as `enum ActiveSheet`.
    short="${enum_name##*.}"
    enum_path="${REPO_ROOT}/${enum_file}"
    if [[ ! -f "$enum_path" ]] || ! grep -qE "(^|[^A-Za-z0-9_])enum ${short}[[:space:]:{]" "$enum_path"; then
        echo "enum_not_found enum=${enum_name} declared_in=${enum_file} at=${CATALOGUE_REL}:${enum_line} — the Coverage table names a file that does not declare it." >> "$WORK/enum_missing.txt"
        ENUMS_NOT_FOUND=$((ENUMS_NOT_FOUND + 1))
        continue
    fi
    # Cases at the enum body's own brace depth only — this is what keeps the
    # `case .veryLow:` arms of a switch inside `var label` out of the list.
    cases=$(awk -v target="$short" '
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
    ' "$enum_path")
    case_count=$(printf '%s' "$cases" | grep -c . || true)
    ENUM_CASES=$((ENUM_CASES + case_count))
    if [[ "$case_count" -eq 0 ]]; then
        # A namespace enum (static members only) has no states to catalogue.
        echo "enum=${enum_name} cases=0 note=namespace-enum"
        continue
    fi
    for c in $cases; do
        if grep -qF "${short}.${c}" "$WORK/state_source.txt"; then continue; fi
        if grep -qxF "${short}.${c}" "$WORK/uncited_allowed.txt"; then
            ENUM_CASES_UNCITED=$((ENUM_CASES_UNCITED + 1))
            continue
        fi
        echo "missing_state enum=${enum_name} case=${c} expected_state_source=${short}.${c} at=${enum_file}" >> "$WORK/enum_missing.txt"
        ENUM_CASES_MISSING=$((ENUM_CASES_MISSING + 1))
    done
done < "$WORK/state_enums.tsv"

[[ ! -s "$WORK/enum_missing.txt" ]] || cat "$WORK/enum_missing.txt"
echo "state_enums=${STATE_ENUMS} enum_cases=${ENUM_CASES} missing=${ENUM_CASES_MISSING} enums_not_found=${ENUMS_NOT_FOUND} uncited=${ENUM_CASES_UNCITED} uncited_allowed=${UNCITED_ALLOWED}"

# ------------------------------------------------------- check 3: ratchets --

# Coverage is deliberately stricter than check 1: a struct counts as covered
# only when one of its rows is status `shipped`. A catalogue full of `planned`
# rows therefore passes check 1 and still reports covered=0, which is the point
# — a green boolean over unwritten rows is worse than a visibly absent file.
#
# `rows_min` is the second half. Coverage alone is satisfied by one row per
# type, so before it existed 26 of the 30 `meal-review/*` rows, or all 7
# `dose-notification/*` rows, could be deleted with the check still green.
COVERED=$(sort -u "$WORK/struct_shipped.txt" | grep -c . || true)
TOTAL=$((STRUCTS_TOTAL - STRUCTS_EXEMPT))

echo "covered=${COVERED} total=${TOTAL} covered_min=${COVERED_MIN} rows_min=${ROWS_MIN}"

RATCHET_OK=1
if [[ "$COVERED" -lt "$COVERED_MIN" ]]; then
    echo "ratchet_regression covered=${COVERED} covered_min=${COVERED_MIN} — a surface lost its shipped row." >&2
    RATCHET_OK=0
elif [[ "$COVERED" -gt "$COVERED_MIN" ]]; then
    echo "ratchet_raise set covered_min=${COVERED} in ${BASELINE_REL} to lock this in."
fi
if [[ "$CATALOGUE_ROWS" -lt "$ROWS_MIN" ]]; then
    echo "ratchet_regression rows=${CATALOGUE_ROWS} rows_min=${ROWS_MIN} — $((ROWS_MIN - CATALOGUE_ROWS)) catalogue rows went missing." >&2
    RATCHET_OK=0
elif [[ "$CATALOGUE_ROWS" -gt "$ROWS_MIN" ]]; then
    echo "ratchet_raise set rows_min=${CATALOGUE_ROWS} in ${BASELINE_REL} to lock this in."
fi
if [[ "$ENUM_CASES_UNCITED" -lt "$UNCITED_ALLOWED" ]]; then
    echo "ratchet_raise ${UNCITED_ALLOWED} uncited cases are allowed in ${BASELINE_REL} but only ${ENUM_CASES_UNCITED} are still uncited — drop the closed ones."
fi

# --------------------------------------------------- check 4: zone pointers --

# A zone is declared once per surface in the catalogue's Zones lists and used in
# the wireframes as `data-zone="…"` and in a composition table. This is a
# spell-check on those references and nothing more: it says that every name
# pointed at exists, not that a SwiftUI view — or even the wireframe itself —
# respects the boundary the zone names. Nothing enforces a zone boundary, by
# design (design-system/surfaces.md, "What they are not").
#
# The comparison is against the union of every declared list rather than
# per surface, because a wireframe folder is named after the decision it serves
# rather than the surface it renders: design-system/wireframes/insulin-dose/
# holds options for the `meal-review` surface.

# Declared: `- **`surface`** — `zone` · `zone` · … .` possibly wrapped. The list
# ends at the first backtick-then-full-stop; the prose after it cites files.
awk -v mark="** — " '
  function flush(   s, p, tok) {
    if (buf == "") return
    p = index(buf, mark)
    if (p > 0) {
      s = substr(buf, p + length(mark))
      p = index(s, "`.")
      if (p > 0) s = substr(s, 1, p)
      while (match(s, /`[^`]+`/)) {
        tok = substr(s, RSTART + 1, RLENGTH - 2)
        s = substr(s, RSTART + RLENGTH)
        if (tok ~ /^[a-z0-9]+(-[a-z0-9]+)*(\/[a-z0-9]+(-[a-z0-9]+)*)?$/) print tok
      }
    }
    buf = ""
  }
  /^- \*\*`/ { flush(); buf = $0; next }
  buf != "" && /^[ \t]+[^ \t]/ { buf = buf " " $0; next }
  { flush() }
  END { flush() }
' "$CATALOGUE" | sort -u > "$WORK/zones_declared.txt"

ZONES_DECLARED=$(wc -l < "$WORK/zones_declared.txt" | tr -d ' ')

: > "$WORK/zone_uses.txt"
if [[ -d "$WIREFRAME_DIR" ]]; then
    find "$WIREFRAME_DIR" -name '*.html' -print0 > "$WORK/zone_html.z"
    find "$WIREFRAME_DIR" -name 'composition*.md' -print0 > "$WORK/zone_md.z"
fi
if [[ -s "${WORK}/zone_html.z" ]]; then
    # A value holding a quote or a `+` is a selector assembled in JavaScript —
    # compare.html builds `[data-zone="' + want + '"]` — and is not a zone use.
    xargs -0 grep -HnoE 'data-zone="[^"]*"' < "$WORK/zone_html.z" 2>/dev/null \
      | sed -E 's/data-zone="([^"]*)"/\1/' \
      | grep -v "['+]" >> "$WORK/zone_uses.txt" || true
fi
if [[ -s "${WORK}/zone_md.z" ]]; then
    # A composition cites zones in the first column of a table headed `zone`.
    # Its prose backticks name files and attempts, so they are not read.
    # shellcheck disable=SC2016  # $0 below is an awk field, not a shell var
    xargs -0 awk '
        /^[ \t]*\|/ {
          row = $0
          gsub(/^[ \t]*\|[ \t]*/, "", row); gsub(/[ \t]*\|[ \t]*$/, "", row)
          if (row ~ /^[ \t:|*-]+$/) next
          first = row; sub(/[ \t]*\|.*$/, "", first); gsub(/[` \t]/, "", first)
          if (tolower(first) == "zone") { intable = 1; next }
          if (intable && first != "") print FILENAME ":" FNR ":" first
          next
        }
        { intable = 0 }
      ' < "$WORK/zone_md.z" 2>/dev/null >> "$WORK/zone_uses.txt" || true
fi

: > "$WORK/zone_bad.txt"
ZONE_USES=$(wc -l < "$WORK/zone_uses.txt" | tr -d ' ')
while IFS= read -r use; do
    [[ -n "$use" ]] || continue
    zone="${use##*:}"
    where="${use%:*}"
    grep -qxF "$zone" "$WORK/zones_declared.txt" \
      || echo "undeclared_zone zone=${zone} at=${where#"$REPO_ROOT"/} — no Zones list in ${CATALOGUE_REL} declares it." >> "$WORK/zone_bad.txt"
done < "$WORK/zone_uses.txt"

ZONES_BAD=$(wc -l < "$WORK/zone_bad.txt" | tr -d ' ')
[[ "$ZONES_BAD" -eq 0 ]] || cat "$WORK/zone_bad.txt"
echo "zones_declared=${ZONES_DECLARED} zone_uses=${ZONE_USES} undeclared=${ZONES_BAD}"

# ----------------------------------------------- check 5: successor mapping --

# The web-v0 half cites iOS rows by id in the Successor mapping, and nothing
# validated those citations, which is how eight broken ones survived. `x/*`
# means the whole surface and resolves when any row's id starts `x/`.
awk '
  /^### Successor mapping/ { on = 1; next }
  on && /^## / { on = 0 }
  on && /^[ \t]*\|/ {
    row = $0
    gsub(/^[ \t]*\|[ \t]*/, "", row); gsub(/[ \t]*\|[ \t]*$/, "", row)
    if (row ~ /^[ \t:|*-]+$/) next
    n = split(row, f, /[ \t]*\|[ \t]*/)
    if (n < 3) next
    if (tolower(f[3]) == "catalogue id") next
    cell = f[3]
    while (match(cell, /`[^`]+`/)) {
      tok = substr(cell, RSTART + 1, RLENGTH - 2)
      cell = substr(cell, RSTART + RLENGTH)
      if (tok ~ /^[A-Za-z0-9][A-Za-z0-9\/*-]*$/) print FNR "\t" tok
    }
  }
' "$CATALOGUE" > "$WORK/successors.tsv"

: > "$WORK/successor_bad.txt"
SUCCESSORS=$(wc -l < "$WORK/successors.tsv" | tr -d ' ')
while IFS=$'\t' read -r sline sid; do
    [[ -n "$sid" ]] || continue
    if [[ "$sid" == */\* ]]; then
        prefix="${sid%\*}"
        grep -qE "^${prefix}" "$WORK/ids.txt" \
          || echo "unresolved_successor id=${sid} at=${CATALOGUE_REL}:${sline} — no catalogue row id starts ${prefix}" >> "$WORK/successor_bad.txt"
    else
        grep -qxF "$sid" "$WORK/ids.txt" \
          || echo "unresolved_successor id=${sid} at=${CATALOGUE_REL}:${sline} — no catalogue row has that id." >> "$WORK/successor_bad.txt"
    fi
done < "$WORK/successors.tsv"

SUCCESSORS_BAD=$(wc -l < "$WORK/successor_bad.txt" | tr -d ' ')
[[ "$SUCCESSORS_BAD" -eq 0 ]] || cat "$WORK/successor_bad.txt"
echo "successor_ids=${SUCCESSORS} unresolved=${SUCCESSORS_BAD}"

# ------------------------------------------------ check 6: layer report (D5) --

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

if [[ "$STRUCTS_MISSING" -ne 0 || "$ENUM_CASES_MISSING" -ne 0 || "$ENUMS_NOT_FOUND" -ne 0 \
      || "$RATCHET_OK" -ne 1 || "$ZONES_BAD" -ne 0 || "$SUCCESSORS_BAD" -ne 0 ]]; then
    echo "FAIL: surface catalogue is out of step with the code." >&2
    exit 1
fi

echo "OK: every surface, state enum case, zone pointer and successor id checks out."
exit 0
