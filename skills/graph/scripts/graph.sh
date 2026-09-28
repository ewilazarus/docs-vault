#!/usr/bin/env bash
# Show or set the colour groups of a docs vault's graph view, in .obsidian/graph.json.
#
#   graph.sh show [--vault <dir>]
#   graph.sh set  [--vault <dir>] [--replace | --add] '<query>=#RRGGBB'...
#
# The vault defaults to ./docs. `show` prints the groups in order, with their colours as
# hex. `set` writes the groups in the order given, since the first group that matches a
# note colours it. Obsidian stores a colour as an integer, and `set` converts it.
#
# Groups already in the file were chosen by someone, so `set` won't touch them unless told
# how: --replace swaps them all for the new ones, and --add appends the new ones, changing
# the colour of any group whose query is already there. Every other key in graph.json is
# kept, and "collapse-color-groups" is set to false so the Groups panel shows what was
# added. Needs jq. Written for bash 3.2, which macOS still ships.

set -euo pipefail

command -v jq >/dev/null || { echo "graph.sh needs jq" >&2; exit 2; }

usage() { sed -n '4,5p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { echo "$*" >&2; exit 2; }

[ $# -ge 1 ] || usage
mode=$1; shift
case "$mode" in show | set) ;; *) usage ;; esac

vault=docs how=""
groups='[]'
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) [ $# -ge 2 ] || usage; vault=$2; shift 2 ;;
    --replace) how=replace; shift ;;
    --add) how=add; shift ;;
    -*) usage ;;
    *)
      [ "$mode" = set ] || usage
      case "$1" in *=*) ;; *) die "A group is '<query>=#RRGGBB', not '$1'." ;; esac
      query=${1%=*} hex=${1##*=}
      hex=${hex#\#}
      printf '%s' "$hex" | grep -Eq '^[0-9A-Fa-f]{6}$' || die "'#$hex' isn't a colour: use six hex digits, like #4C8BF5."
      [ -n "$query" ] || die "'$1' has no query."
      groups=$(jq -c --arg q "$query" --argjson rgb $((16#$hex)) '. + [{query: $q, color: {a: 1, rgb: $rgb}}]' <<<"$groups")
      shift
      ;;
  esac
done

[ -d "$vault" ] || die "No vault at $vault."
file="$vault/.obsidian/graph.json"
current='{}'
if [ -f "$file" ]; then
  current=$(jq . "$file" 2>/dev/null) || die "$file isn't valid JSON."
fi

# Prints the groups of a graph.json as a table.
table() {
  local rows
  rows=$(jq -r '.colorGroups // [] | to_entries[] | "\(.key + 1)\t\(.value.color.rgb)\t\(.value.query)"' <<<"$1")
  if [ -z "$rows" ]; then
    echo "No colour groups."
    return 0
  fi
  echo "| # | Colour | Query |"
  echo "|---|---|---|"
  printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r n rgb query; do
    printf '| %s | #%06X | %s |\n' "$n" "$rgb" "$(printf '%s' "$query" | sed 's/|/\\|/g')"
  done
}

if [ "$mode" = show ]; then
  table "$current"
  exit 0
fi

[ "$groups" != '[]' ] || usage
existing=$(jq '.colorGroups // [] | length' <<<"$current")
if [ "$existing" -gt 0 ] && [ -z "$how" ]; then
  table "$current" >&2
  die "graph.json already has $existing colour groups, which someone chose. Pass --replace to swap them for these, or --add to keep them and add these."
fi

updated=$(jq --argjson new "$groups" --arg how "$how" '
  .colorGroups = (if $how == "add"
    then reduce $new[] as $g (.colorGroups // [];
      if any(.[]; .query == $g.query) then map(if .query == $g.query then $g else . end) else . + [$g] end)
    else $new end)
  | .["collapse-color-groups"] = false' <<<"$current")

mkdir -p "$vault/.obsidian"
printf '%s\n' "$updated" >"$file.tmp"
mv "$file.tmp" "$file"
echo "Wrote $file:"
table "$updated"
