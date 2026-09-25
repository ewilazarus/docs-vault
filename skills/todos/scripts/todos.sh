#!/usr/bin/env bash
# Print the open work in a docs vault's journal as a Markdown table.
#
#   todos.sh [docs-dir]    (defaults to $CLAUDE_PROJECT_DIR/docs, or ./docs)
#
# Reads journal/YYYY-MM-DD.md, oldest day first. Every unticked top-level `- [ ]` box is one
# row: the day it was raised, the `### #todo` block it sits in, its text (continuation lines
# joined), and its nested sub-items with their own state. Unticked boxes outside a `#todo`
# block are listed too, because every unticked box in the journal is open work.
# Frontmatter and fenced code blocks are skipped. Written for bash 3.2 and POSIX awk.

set -eu

docs=${1:-${CLAUDE_PROJECT_DIR:-.}/docs}
journal="$docs/journal"

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
function indent(s) { match(s, /^[ \t]*/); return RLENGTH }

function flush_item() {
  if (item_state == "") return
  if (item_state == "open") {
    rows++
    row_date[rows] = date
    row_todo[rows] = (block == "" ? "_outside a #todo block_" : block)
    row_item[rows] = item_text
    row_subs[rows] = subs
    if (block == "") stray++
    else if (!((date SUBSEP block) in seen_block)) { seen_block[date SUBSEP block] = 1; blocks++ }
    if (!(date in seen_day)) { seen_day[date] = 1; days++ }
  } else {
    closed++
  }
  item_state = ""; item_text = ""; subs = ""; last_sub = ""
}

function add_sub(text) {
  if (last_sub != "") subs = subs (subs == "" ? "" : " · ") last_sub
  last_sub = text
}

function end_subs() {
  if (last_sub != "") subs = subs (subs == "" ? "" : " · ") last_sub
  last_sub = ""
}

FNR == 1 {
  end_subs(); flush_item()
  date = FILENAME; sub(/^.*\//, "", date); sub(/\.md$/, "", date)
  block = ""; fence = 0; frontmatter = ($0 == "---")
  if (frontmatter) next
}

frontmatter { if ($0 == "---") frontmatter = 0; next }

/^[ \t]*(```|~~~)/ { fence = !fence; next }
fence { next }

# A heading ends the current item, and opens or closes a #todo block.
/^#+[ \t]/ {
  end_subs(); flush_item()
  block = ""
  if ($0 ~ /^###[ \t]+#todo([ \t]|$)/) {
    block = $0; sub(/^###[ \t]+#todo[ \t]*/, "", block); block = trim(block)
    if (block == "") block = "(untitled)"
  }
  next
}

# A top-level checkbox starts an item.
/^[-*+][ \t]+\[[ xX]\]/ {
  end_subs(); flush_item()
  item_state = ($0 ~ /^[-*+][ \t]+\[ \]/) ? "open" : "done"
  item_text = $0; sub(/^[-*+][ \t]+\[[ xX]\][ \t]*/, "", item_text); item_text = trim(item_text)
  next
}

# Any other top-level line that is not blank ends the item.
/^[^ \t]/ { end_subs(); flush_item(); next }

/^[ \t]*$/ { next }

# Indented lines belong to the current item: nested list items are sub-items, and
# anything else continues the text of the last sub-item, or of the item itself.
item_state != "" {
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

END {
  end_subs(); flush_item()
  if (rows == 0) {
    printf "No open todos. %d ticked %s across the journal.\n", closed, (closed == 1 ? "box" : "boxes")
    exit
  }
  print "| # | Raised | Todo | Open item | Sub-items |"
  print "|---|---|---|---|---|"
  for (i = 1; i <= rows; i++)
    printf "| %d | %s | %s | %s | %s |\n", i, row_date[i], cell(row_todo[i]), cell(row_item[i]), (row_subs[i] == "" ? "—" : cell(row_subs[i]))
  printf "\n%d open %s in %d %s", rows, (rows == 1 ? "item" : "items"), blocks, (blocks == 1 ? "todo block" : "todo blocks")
  if (stray > 0) printf " (plus %d outside one)", stray
  printf ", raised on %d %s. %d %s already ticked.\n", days, (days == 1 ? "day" : "days"), closed, (closed == 1 ? "box is" : "boxes are")
}
' $files
