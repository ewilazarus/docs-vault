#!/usr/bin/env bash
# Print the path for a new decision note, or just its number.
#
#   next-decision.sh "Authorization lives in middleware"
#     -> Decisions/00013-authorization-lives-in-middleware.md
#   next-decision.sh
#     -> 00013
#
# The number is one more than the highest in docs/Decisions/, on this checkout and on every
# local and remote-tracking branch, so a decision made on one branch doesn't take a number
# another branch already has. Numbers are never reused, even when a decision is deleted.
# The slug is the title in lowercase ASCII, with anything else turned into hyphens.
#
# The vault is $CLAUDE_PROJECT_DIR/docs, or ./docs. Written for bash 3.2.

set -eu

docs=${CLAUDE_PROJECT_DIR:-.}/docs
[ -d "$docs" ] || { echo "No vault found at $docs." >&2; exit 2; }

# Five-digit decision numbers, one per line, from file names on stdin.
numbers() { sed -n 's#^\(.*/\)\{0,1\}\([0-9]\{5\}\)-[^/]*\.md$#\2#p'; }

highest=$(
  {
    find "$docs/Decisions" -maxdepth 1 -name '[0-9][0-9][0-9][0-9][0-9]-*.md' 2>/dev/null
    if prefix=$(git -C "$docs" rev-parse --show-prefix 2>/dev/null); then
      git -C "$docs" for-each-ref --format='%(refname) %(symref)' refs/heads refs/remotes |
        while read -r ref symref; do
          [ -z "$symref" ] || continue
          git -C "$docs" ls-tree --name-only --full-tree "$ref" -- "${prefix}Decisions/" 2>/dev/null || true
        done
    fi
  } | numbers | sort | tail -n 1
)
next=$(printf '%05d' $((10#${highest:-0} + 1)))

if [ $# -eq 0 ]; then
  echo "$next"
  exit 0
fi

slug=$(printf '%s' "$*" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//')
[ -n "$slug" ] || { echo "The title needs some letters or digits for its slug." >&2; exit 2; }
echo "Decisions/$next-$slug.md"
