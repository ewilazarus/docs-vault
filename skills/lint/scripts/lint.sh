#!/usr/bin/env bash
# Check a docs vault as a whole and print its problems as a Markdown table.
#
#   lint.sh [docs-dir]    (defaults to $CLAUDE_PROJECT_DIR/docs, or ./docs)
#
# The hooks check each write as it happens. This checks what is already there, including
# what shell commands and edits in Obsidian wrote:
#
# - every [[wikilink]] and ![[embed]] resolves to a file, and its #heading or #^block
#   exists in that file;
# - no bare section reference such as `§4.2` sits outside a link or code;
# - a journal file is named YYYY-MM-DD.md and isn't dated in the future;
# - a day in the current format (one with a `## Summary`, `## Decisions` or `## Follow-ups`
#   heading) has a `description:`, a Summary, and those sections once each, in that order,
#   none of them empty. Days in the legacy format are counted but not checked;
# - a decision is named NNNNN-short-slug.md, its number isn't shared, it has a `date:` and
#   a `## Why`, and some journal day links it.
#
# Links resolve the way Obsidian resolves them, ignoring case: a vault-relative path, then
# a path relative to the linking note, then any file whose path ends with the target.
# Frontmatter is read, but fenced code and inline code are skipped. Set DOCS_VAULT_TODAY
# to YYYY-MM-DD to check against another day. Written for bash 3.2 and POSIX awk.

set -eu

docs=${1:-${CLAUDE_PROJECT_DIR:-.}/docs}
today=${DOCS_VAULT_TODAY:-$(date +%F)}

if [ ! -d "$docs" ]; then
  echo "No vault found at \`$docs\`."
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

(cd "$docs" && find . -type f \
  -not -path './.obsidian/*' -not -path './.trash/*' -not -path './.git/*' -not -name '.DS_Store' |
  sed 's#^\./##' | LC_ALL=C sort) >"$tmp/index"

awk -v docs="$docs" -v today="$today" -v index_file="$tmp/index" -v stats_file="$tmp/stats" '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); gsub(/[ \t]+/, " ", s); return s }
function dirname(p) { return (p ~ /\//) ? substr(p, 1, match(p, /\/[^\/]*$/) - 1) : "" }
function basename(p) { sub(/^.*\//, "", p); return p }
function ends_with(s, t) { return length(s) >= length(t) && substr(s, length(s) - length(t) + 1) == t }

# Heading text as a link spells it: Obsidian drops the characters a link cannot hold.
function heading_key(h) {
  h = tolower(h)
  gsub(/`/, "", h)
  gsub(/[:#^%\[\]|\\]/, " ", h)
  return trim(h)
}

function report(f, n, severity, message) {
  printf "%s\t%d\t%s\t%s\n", f, n, severity, message
  if (severity == "error") errors++; else warnings++
}

# --- reading -------------------------------------------------------------------------------

function add_link(f, n, inner,   p, shown, target, sub_ref) {
  shown = inner
  p = index(inner, "|"); if (p) { inner = substr(inner, 1, p - 1); shown = inner }
  sub(/\\$/, "", inner); sub(/\\$/, "", shown)
  target = inner; sub_ref = ""
  p = index(target, "#"); if (p) { sub_ref = substr(target, p + 1); target = substr(target, 1, p - 1) }
  links++
  link_file[links] = f; link_line[links] = n; link_shown[links] = shown
  link_target[links] = trim(target); link_sub[links] = sub_ref
}

# Records the wikilinks in s, and returns s with them removed.
function take_links(f, n, s,   out, i, j) {
  out = ""
  while ((i = index(s, "[[")) > 0) {
    j = index(substr(s, i + 2), "]]")
    if (!j) break
    add_link(f, n, substr(s, i + 2, j - 1))
    out = out substr(s, 1, i - 1)
    s = substr(s, i + 2 + j + 1)
  }
  return out s
}

# A `#` or `##` heading closes the day section before it.
function close_section(f) {
  if (section != "" && !section_has_content)
    report(f, section_line, "warning", "`## " section "` is empty. Leave a section out when it has nothing in it.")
  section = ""
}

function open_section(f, n, name,   rank) {
  rank = (name == "Summary") ? 1 : (name == "Decisions") ? 2 : 3
  if (seen[name]++) report(f, n, "warning", "`## " name "` appears more than once. A day has one of each section.")
  else if (rank < last_rank) report(f, n, "warning", "`## " name "` comes after `## " last_name "`. The order is Summary, Decisions, Follow-ups.")
  if (rank > last_rank) { last_rank = rank; last_name = name }
  section = name; section_line = n; section_has_content = 0
}

function scan(f,   full, line, s, h, n, in_fm, fence, kind, m, rest) {
  full = docs "/" f
  kind = (f ~ /^Journal\/[^\/]*$/) ? "day" : (f ~ /^Decisions\/[^\/]*$/) ? "decision" : "note"
  n = 0; in_fm = 0; fence = 0
  section = ""; last_rank = 0; last_name = ""; split("", seen)
  while ((getline line < full) > 0) {
    n++
    sub(/\r$/, "", line)
    if (n == 1 && line == "---") { in_fm = 1; continue }
    if (in_fm) {
      if (line == "---") { in_fm = 0; continue }
      if (line ~ /^description:/) has_description[f] = 1
      if (line ~ /^date:[ \t]*"?[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]"?[ \t]*$/) has_date[f] = 1
      take_links(f, n, line)
      continue
    }
    if (line ~ /^[ \t]*(```|~~~)/) { fence = !fence; if (section != "") section_has_content = 1; continue }
    if (fence) continue

    if (line ~ /^#+[ \t]/) {
      h = line; sub(/^#+[ \t]+/, "", h); sub(/[ \t]+#+[ \t]*$/, "", h)
      heading[f SUBSEP heading_key(h)] = 1
    }
    if (match(line, /\^[A-Za-z0-9-]+[ \t]*$/)) {
      rest = substr(line, RSTART + 1); sub(/[ \t]+$/, "", rest)
      block[f SUBSEP rest] = 1
    }

    s = line; gsub(/`[^`]*`/, "", s)
    s = take_links(f, n, s)
    gsub(/\[[^]]*\]\([^)]*\)/, "", s)
    if (s ~ /§ ?[0-9]/)
      report(f, n, "warning", "Bare section reference. Link the section itself, for example `[[Spec#4.2 Assertion|Spec §4.2]]`.")

    if (kind == "decision" && line ~ /^##[ \t]+Why[ \t]*$/) has_why[f] = 1
    if (kind != "day") continue
    if (line ~ /^##?[ \t]/) {
      close_section(f)
      m = line; sub(/^##[ \t]+/, "", m); m = trim(m)
      if (line ~ /^##[ \t]/ && (m == "Summary" || m == "Decisions" || m == "Follow-ups")) open_section(f, n, m)
    } else if (section != "" && line !~ /^[ \t]*$/) {
      section_has_content = 1
    }
  }
  close(full)
  if (kind == "day") { close_section(f); day_format[f] = (last_rank > 0) ? "current" : "legacy"; has_summary[f] = ("Summary" in seen) }
}

# --- resolving -----------------------------------------------------------------------------

function find_file(from, target,   t, d, k, rel) {
  if (target == "") return from
  t = tolower(target)
  if (t in resolved) return resolved[t]
  for (k = 1; k <= files; k++) if (lower[k] == t || lower[k] == t ".md") return resolved[t] = path[k]
  d = tolower(dirname(from))
  if (d != "") {
    rel = d "/" t
    for (k = 1; k <= files; k++) if (lower[k] == rel || lower[k] == rel ".md") return path[k]
  }
  for (k = 1; k <= files; k++) if (ends_with(lower[k], "/" t) || ends_with(lower[k], "/" t ".md")) return path[k]
  return ""
}

function check_links(   i, f, target, last) {
  for (i = 1; i <= links; i++) {
    f = link_file[i]
    target = find_file(f, link_target[i])
    if (target == "") {
      report(f, link_line[i], "error", "Broken link `[[" link_shown[i] "]]`: no file named `" link_target[i] "`.")
      continue
    }
    if (f ~ /^Journal\// && target ~ /^Decisions\//) linked_from_journal[target] = 1
    if (link_sub[i] == "") continue
    last = link_sub[i]; sub(/^.*#/, "", last)
    if (last ~ /^\^/) {
      if (!((target SUBSEP substr(last, 2)) in block))
        report(f, link_line[i], "error", "Broken link `[[" link_shown[i] "]]`: no block `" last "` in `" target "`.")
    } else if (!((target SUBSEP heading_key(last)) in heading)) {
      report(f, link_line[i], "error", "Broken link `[[" link_shown[i] "]]`: no heading `" last "` in `" target "`.")
    }
  }
}

# --- the journal and decisions ------------------------------------------------------------

function check_day(f,   name) {
  days++
  name = basename(f)
  if (name !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\.md$/) {
    report(f, 0, "warning", "Not a day file. The journal holds only `Journal/YYYY-MM-DD.md`.")
    return
  }
  if (substr(name, 1, 10) > today) report(f, 0, "error", "Dated in the future. The journal records what happened.")
  if (day_format[f] == "legacy") { legacy_days++; return }
  if (!has_summary[f]) report(f, 0, "error", "No `## Summary`. Every day has one.")
  if (!has_description[f]) report(f, 0, "warning", "No `description:` in the frontmatter. It is the day'"'"'s headline.")
}

function check_decision(f,   name, number, k) {
  decisions++
  name = basename(f)
  if (name !~ /^[0-9][0-9][0-9][0-9][0-9]-[a-z0-9][a-z0-9-]*\.md$/) {
    report(f, 0, "warning", "Not named `NNNNN-short-slug.md`.")
  } else {
    number = substr(name, 1, 5)
    for (k = 1; k <= decisions_by_number[number]; k++)
      if (numbered[number, k] != f)
        report(f, 0, "error", "Decision number " number " is also used by `" numbered[number, k] "`. Numbers are never shared.")
  }
  if (!has_date[f]) report(f, 0, "error", "No `date: YYYY-MM-DD` in the frontmatter.")
  if (!has_why[f]) report(f, 0, "warning", "No `## Why`. A decision says why it was made.")
  if (!(f in linked_from_journal)) report(f, 0, "warning", "No journal day links this decision. The day it was made lists it under `## Decisions`.")
}

BEGIN {
  while ((getline p < index_file) > 0) {
    files++; path[files] = p; lower[files] = tolower(p)
    if (p ~ /^Decisions\/[0-9][0-9][0-9][0-9][0-9]-[^\/]*\.md$/) {
      number = substr(p, 11, 5)
      numbered[number, ++decisions_by_number[number]] = p
    }
  }
  close(index_file)
  for (k = 1; k <= files; k++) if (path[k] ~ /\.md$/) { scan(path[k]); notes++ }
  check_links()
  for (k = 1; k <= files; k++) {
    if (path[k] ~ /^Journal\/[^\/]*\.md$/) check_day(path[k])
    else if (path[k] ~ /^Decisions\/[^\/]*\.md$/) check_decision(path[k])
  }
  printf "%d %d %d %d %d %d\n", errors, warnings, notes, days, legacy_days, decisions > stats_file
}
' >"$tmp/problems"

read -r errors warnings notes days legacy decisions <"$tmp/stats"

plural() { [ "$1" -eq 1 ] && printf '%d %s' "$1" "$2" || printf '%d %ss' "$1" "$2"; }

checked="Checked $(plural "$notes" note): $(plural "$days" journal\ file)"
[ "$legacy" -eq 0 ] || checked="$checked ($legacy in the legacy format, not checked for structure)"
checked="$checked and $(plural "$decisions" decision)."

if [ ! -s "$tmp/problems" ]; then
  echo "No problems found. $checked"
  exit 0
fi

LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2n "$tmp/problems" | awk -F '\t' '
function cell(s) { gsub(/\|/, "\\|", s); return s }
BEGIN { print "| # | Severity | Where | Problem |"; print "|---|---|---|---|" }
{ printf "| %d | %s | `%s%s` | %s |\n", NR, $3, $1, ($2 > 0 ? ":" $2 : ""), cell($4); if (!($1 in seen)) { seen[$1] = 1; nfiles++ } }
END { printf "\n%d", nfiles > "/dev/stderr" }
' 2>"$tmp/nfiles"

printf '\n%s and %s in %s. %s\n' "$(plural "$errors" error)" "$(plural "$warnings" warning)" "$(plural "$(tr -d '\n' <"$tmp/nfiles")" file)" "$checked"
