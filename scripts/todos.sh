#!/usr/bin/env bash
# Print the open follow-ups in a docs vault's journal as a Markdown table.
#
#   todos.sh [docs-dir]    (defaults to $CLAUDE_PROJECT_DIR/docs, or ./docs)
#
# Reads Journal/YYYY-MM-DD.md, oldest day first. Every unticked top-level `- [ ]` box in a
# day's `## Follow-ups` section is one row: the day it was raised, its text (continuation
# lines joined), and its nested sub-items with their own state. The section runs to the
# next `#` or `##` heading. Boxes anywhere else are ordinary checklists, not project work:
# they aren't listed, and the summary line only counts the unticked ones.
# Frontmatter and fenced code blocks are skipped. Written for bash 3.2 and POSIX awk.
#
# LEGACY: day files written before Follow-ups sections kept open work in `### #todo`
# blocks, or tagged a box with `#todo`. Those boxes are listed too, marked as legacy, until
# the journal is backfilled. Everything legacy is inside the marked blocks below.

set -eu

docs=${1:-${CLAUDE_PROJECT_DIR:-.}/docs}
journal="$docs/Journal"

if [ ! -d "$journal" ]; then
  echo "No journal found at \`$journal\`."
  exit 0
fi

files=$(find "$journal" -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md' | LC_ALL=C sort)
if [ -z "$files" ]; then
  echo "The journal has no day files yet."
  exit 0
fi

# shellcheck disable=SC2086 # day-file names contain no spaces
awk '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); gsub(/[ \t]+/, " ", s); return s }
function cell(s) { s = trim(s); gsub(/\|/, "\\|", s); return s }

# item_state is "" (no item), "skip" (a box outside the scope, whose lines are swallowed),
# "open" or "done".
function flush_item() {
  if (item_state == "open") {
    rows++
    row_date[rows] = date
    row_item[rows] = item_text (item_legacy == "" ? "" : " _(" item_legacy ")_")
    row_subs[rows] = subs
    if (!(date in seen_day)) { seen_day[date] = 1; days++ }
    if (item_legacy != "") legacy_rows++
  } else if (item_state == "done") {
    closed++
  }
  item_state = ""; item_text = ""; item_legacy = ""; subs = ""; last_sub = ""
}

function add_sub(text) {
  if (last_sub != "") subs = subs (subs == "" ? "" : " · ") last_sub
  last_sub = text
}

function end_subs() {
  if (last_sub != "") subs = subs (subs == "" ? "" : " · ") last_sub
  last_sub = ""
}

# --- LEGACY (v1) scope: remove once the journal is backfilled -----------------------------
# Returns a label for a box that v1 counted as a todo, or "" when it is not one.
function legacy_scope(line) {
  if (legacy_block != "") return "legacy #todo block: " legacy_block
  if (line ~ /(^|[ \t])#todo([ \t]|$)/) return "legacy #todo tag"
  return ""
}
# --- end LEGACY ----------------------------------------------------------------------------

FNR == 1 {
  end_subs(); flush_item()
  date = FILENAME; sub(/^.*\//, "", date); sub(/\.md$/, "", date)
  in_followups = 0; legacy_block = ""; fence = 0; frontmatter = ($0 == "---")
  if (frontmatter) next
}

frontmatter { if ($0 == "---") frontmatter = 0; next }

/^[ \t]*(```|~~~)/ { fence = !fence; next }
fence { next }

# A heading ends the current item. A `#` or `##` heading opens or closes the Follow-ups
# section. Deeper headings stay inside the section they are in.
/^#+[ \t]/ {
  end_subs(); flush_item()
  match($0, /^#+/)
  if (RLENGTH <= 2) in_followups = ($0 ~ /^##[ \t]+Follow-ups[ \t]*$/)
  # LEGACY: a `### #todo Title` heading opens a v1 todo block, and any other heading ends it.
  legacy_block = ""
  if ($0 ~ /^###[ \t]+#todo([ \t]|$)/) {
    legacy_block = $0; sub(/^###[ \t]+#todo[ \t]*/, "", legacy_block); legacy_block = trim(legacy_block)
    if (legacy_block == "") legacy_block = "(untitled)"
  }
  next
}

# A top-level checkbox starts an item, if it is in scope.
/^[-*+][ \t]+\[[ xX]\]/ {
  end_subs(); flush_item()
  item_legacy = in_followups ? "" : legacy_scope($0)
  if (!in_followups && item_legacy == "") {
    item_state = "skip"
    if ($0 ~ /^[-*+][ \t]+\[ \]/) elsewhere++
    next
  }
  item_state = ($0 ~ /^[-*+][ \t]+\[ \]/) ? "open" : "done"
  item_text = $0; sub(/^[-*+][ \t]+\[[ xX]\][ \t]*/, "", item_text)
  if (item_legacy == "legacy #todo tag") gsub(/(^|[ \t])#todo([ \t]|$)/, " ", item_text)
  item_text = trim(item_text)
  next
}

# Any other top-level line that is not blank ends the item.
/^[^ \t]/ { end_subs(); flush_item(); next }

/^[ \t]*$/ { next }

# Indented lines belong to the current item: nested list items are sub-items, and
# anything else continues the text of the last sub-item, or of the item itself.
item_state == "open" || item_state == "done" {
  line = $0
  if (line ~ /^[ \t]+[-*+][ \t]+\[[ xX]\]/) {
    mark = (line ~ /^[ \t]+[-*+][ \t]+\[ \]/) ? "☐ " : "☑ "
    sub(/^[ \t]+[-*+][ \t]+\[[ xX]\][ \t]*/, "", line)
    add_sub(mark trim(line))
  } else if (line ~ /^[ \t]+([-*+]|[0-9]+[.)])[ \t]+/) {
    sub(/^[ \t]+([-*+]|[0-9]+[.)])[ \t]+/, "", line)
    add_sub("• " trim(line))
  } else if (last_sub != "") {
    last_sub = last_sub " " trim(line)
  } else {
    item_text = item_text " " trim(line)
  }
}

function note_elsewhere() {
  if (elsewhere > 0)
    printf " %d unticked %s elsewhere in the journal %s outside a Follow-ups section, so %s not listed.", elsewhere, (elsewhere == 1 ? "box" : "boxes"), (elsewhere == 1 ? "is" : "are"), (elsewhere == 1 ? "it is" : "they are")
}

END {
  end_subs(); flush_item()
  if (rows == 0) {
    printf "No open follow-ups. %d already ticked.", closed
    note_elsewhere()
    printf "\n"
    exit
  }
  print "| # | Raised | Todo | Sub-items |"
  print "|---|---|---|---|"
  for (i = 1; i <= rows; i++)
    printf "| %d | %s | %s | %s |\n", i, row_date[i], cell(row_item[i]), (row_subs[i] == "" ? "—" : cell(row_subs[i]))
  printf "\n%d open %s, raised on %d %s. %d already ticked.", rows, (rows == 1 ? "follow-up" : "follow-ups"), days, (days == 1 ? "day" : "days"), closed
  if (legacy_rows > 0) printf " %d %s from legacy `#todo` markup.", legacy_rows, (legacy_rows == 1 ? "comes" : "come")
  note_elsewhere()
  printf "\n"
}
' $files
