#!/usr/bin/env bash
# Check that git changes to a docs vault keep its history as it was written.
#
#   history.sh --staged          the changes staged for the next commit, as of today
#   history.sh --range A..B      each commit in the range, as of the day it was authored
#
# The same rules the plugin's hook applies to Claude's writes, for every change:
#
# - a journal day, Journal/YYYY-MM-DD.md, can't be written for a future day, or created
#   or deleted after its day;
# - after its day, a journal day's only changes are ticking or unticking a checkbox,
#   without touching its text, and re-pointing a [[link]] while keeping its displayed text;
# - a new decision is dated the day it is made, in its `date:` frontmatter;
# - after its day, a decision changes only in the same two ways.
#
# "Today" is the commit's author date, which a rebase keeps, so rebased work isn't taken
# for a rewrite of the past. Run it from inside the repository; the vault is its docs/.
# Prints one line per problem and exits 1 if there are any. Needs git and jq. Written for
# bash 3.2, which macOS still ships.

set -euo pipefail

command -v jq >/dev/null || { echo "history.sh needs jq" >&2; exit 2; }

usage() { sed -n '4,5p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

case "${1:-}" in
  --staged) [ $# -eq 1 ] || usage ;;
  --range) [ $# -eq 2 ] || usage ;;
  *) usage ;;
esac

root=$(git rev-parse --show-toplevel)
[ -d "$root/docs" ] || exit 0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
problems=0

# The same comparison as hooks/vault_guard.sh: [[target|shown]] becomes [[shown]], and
# every checkbox becomes unticked, so only other changes remain.
same_but_boxes_and_links() {
  jq -en --rawfile old "$1" --rawfile new "$2" '
    def links: gsub("\\[\\[[^\\]|]+\\|(?<s>[^\\]]+)\\]\\]"; "[[\(.s)]]");
    def unboxed: gsub("(?<b>[-*+]) \\[[ xX]\\]"; "\(.b) [ ]");
    ($old | links | unboxed) == ($new | links | unboxed)' >/dev/null
}

# The `date:` in a note's frontmatter, if any.
date_of() { sed -n '1{/^---$/!q;};2,/^---$/{s/^date:[[:space:]]*"\{0,1\}\([0-9-]\{10\}\)"\{0,1\}[[:space:]]*$/\1/p;}' "$1"; }

report() { problems=$((problems + 1)); printf '%s%s: %s\n' "$where" "$1" "$2"; }

# check_change <status> <path> <old-rev> <new-rev> <today> [<old path>]. A rev of "" is
# the index. A rename (R) is a change to the note under its old path, so a decision that
# is renamed but otherwise kept as it was passes.
check_change() {
  local status=$1 path=$2 old=$3 new=$4 today=$5 from=${6:-$2} rel day date
  rel=${path#docs/}
  : >"$tmp/old"; : >"$tmp/new"
  [ "$status" = A ] || git show "$old:$from" >"$tmp/old" 2>/dev/null || true
  [ "$status" = D ] || git show "$new:$path" >"$tmp/new" 2>/dev/null || true
  if [ "$status" = R ]; then
    day=$(printf '%s\n' "${from#docs/}" | sed -n 's#^Journal/\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)\.md$#\1#p')
    if [ -n "$day" ] && [[ "$day" < "$today" ]]; then
      report "${from#docs/}" "renames a past day to $rel. The journal is a record of what was known then."
      return 0
    fi
    status=M
  fi

  day=$(printf '%s\n' "$rel" | sed -n 's#^Journal/\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)\.md$#\1#p')
  if [ -n "$day" ]; then
    if [[ "$day" > "$today" ]]; then
      [ "$status" = D ] || report "$rel" "writes a future day. The journal records what happened; plans belong in notes."
    elif [[ "$day" < "$today" ]]; then
      case "$status" in
        A) report "$rel" "creates a past day on $today. New history goes in that day's own file." ;;
        D) report "$rel" "deletes a past day. The journal is a record of what was known then." ;;
        M) same_but_boxes_and_links "$tmp/old" "$tmp/new" ||
             report "$rel" "changes a past day's prose. After its day, only checkbox state and link targets may change." ;;
      esac
    fi
    return 0
  fi

  case "$rel" in
    Decisions/*.md)
      case "$status" in
        A)
          date=$(date_of "$tmp/new")
          [ "$date" = "$today" ] ||
            report "$rel" "is a new decision dated ${date:-nowhere}, not $today. A decision is dated the day it's made."
          ;;
        M)
          date=$(date_of "$tmp/old")
          if [ -n "$date" ] && [[ "$date" < "$today" ]]; then
            same_but_boxes_and_links "$tmp/old" "$tmp/new" ||
              report "$rel" "changes a decision made on $date. A changed mind is a new decision that supersedes this one."
          fi
          ;;
      esac
      ;;
  esac
}

# check_diff <old-rev> <new-rev> <today>: every change to docs/ between them.
check_diff() {
  local old=$1 new=$2 today=$3 status path to
  while IFS="$(printf '\t')" read -r status path to; do
    case "$status" in
      R*) check_change R "$to" "$old" "$new" "$today" "$path" ;;
      *) check_change "$status" "$path" "$old" "$new" "$today" ;;
    esac
  done < <(
    if [ -z "$new" ]; then
      git -C "$root" diff --cached --find-renames --name-status "$old" -- docs/
    else
      git -C "$root" diff --find-renames --name-status "$old" "$new" -- docs/
    fi | grep -E '^([ADM]|R[0-9]*)	' || true
  )
}

cd "$root"
empty_tree=$(git hash-object -t tree /dev/null)
if [ "$1" = --staged ]; then
  where=""
  base=HEAD
  git rev-parse -q --verify HEAD >/dev/null || base=$empty_tree
  check_diff "$base" "" "${DOCS_VAULT_TODAY:-$(date +%F)}"
else
  while read -r commit; do
    where="$(git rev-parse --short "$commit") "
    parent="$commit^"
    git rev-parse -q --verify "$parent" >/dev/null || parent=$empty_tree
    check_diff "$parent" "$commit" "$(git log -1 --format=%ad --date=short "$commit")"
  done < <(git rev-list --reverse --no-merges "$2")
fi

[ "$problems" -eq 0 ]
