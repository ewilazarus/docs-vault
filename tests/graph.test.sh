#!/usr/bin/env bash
# Tests for scripts/graph.sh: showing, converting, and what it keeps.

set -eu
. "$(dirname "$0")/lib.sh"

graph="$repo/scripts/graph.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# run <args>: runs graph.sh, and prints its output and any error.
run() { "$BASH" "$graph" "$@" 2>&1 || true; }

v="$tmp/docs"
mkdir -p "$v"

echo "graph.sh: a vault without groups"

check "no vault" "No vault at $tmp/none." "$(run show --vault "$tmp/none")"
check "no graph.json yet" "No colour groups." "$(run show --vault "$v")"
check "a colour must be six hex digits" "'#4C8BF' isn't a colour: use six hex digits, like #4C8BF5." \
  "$(run set --vault "$v" 'path:Journal=#4C8BF')"
check "a group needs a colour" "A group is '<query>=#RRGGBB', not 'path:Journal'." \
  "$(run set --vault "$v" 'path:Journal')"

check "set converts hex, keeps the order, and creates the file" "\
Wrote $v/.obsidian/graph.json:
| # | Colour | Query |
|---|---|---|
| 1 | #F5A623 | file:Home OR file:Conventions |
| 2 | #8A8F98 | path:Journal |
| 3 | #4C8BF5 | path:Concepts |" \
  "$(run set --vault "$v" 'file:Home OR file:Conventions=#F5A623' 'path:Journal=8a8f98' 'path:Concepts=#4C8BF5')"
check "rgb is stored as an integer" '[16098851,9080728,5016565] false' \
  "$(jq -c '[.colorGroups[].color.rgb]' "$v/.obsidian/graph.json") $(jq '.["collapse-color-groups"]' "$v/.obsidian/graph.json")"

echo "graph.sh: a vault with groups"

jq '. + {scale: 1.4, "showTags": true, search: "auth"}' "$v/.obsidian/graph.json" >"$tmp/g" && mv "$tmp/g" "$v/.obsidian/graph.json"
check "set refuses to replace chosen groups by default" \
  "graph.json already has 3 colour groups, which someone chose. Pass --replace to swap them for these, or --add to keep them and add these." \
  "$(run set --vault "$v" 'path:Decisions=#D68A46' 2>&1 | tail -n 1)"

run set --vault "$v" --add 'path:Decisions=#D68A46' 'path:Journal=#777777' >/dev/null
check "--add appends new queries and recolours existing ones" "\
| # | Colour | Query |
|---|---|---|
| 1 | #F5A623 | file:Home OR file:Conventions |
| 2 | #777777 | path:Journal |
| 3 | #4C8BF5 | path:Concepts |
| 4 | #D68A46 | path:Decisions |" "$(run show --vault "$v")"
check "other settings are kept" '1.4 true "auth"' \
  "$(jq -r '"\(.scale) \(.showTags) \(.search | tojson)"' "$v/.obsidian/graph.json")"

run set --vault "$v" --replace 'path:Notes=#123456' >/dev/null
check "--replace swaps every group" "\
| # | Colour | Query |
|---|---|---|
| 1 | #123456 | path:Notes |" "$(run show --vault "$v")"

echo '{ broken' >"$v/.obsidian/graph.json"
check "invalid JSON is refused, and left alone" "$v/.obsidian/graph.json isn't valid JSON.|{ broken" \
  "$(run set --vault "$v" 'path:Notes=#123456')|$(cat "$v/.obsidian/graph.json")"

finish
