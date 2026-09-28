#!/usr/bin/env bash
# Check a project's docs vault before a commit, or in CI: the lint script's errors in the
# notes that changed, and the history rules for every change.
#
#   check.sh --staged          for a pre-commit hook: the changes staged for this commit
#   check.sh --range A..B      for CI: the commits in the range
#
# Only notes that changed are linted, so older problems elsewhere don't block a commit;
# /docs-vault:lint shows those. Warnings never fail it. `init --checks` copies this script,
# lint.sh and history.sh into the project's .docs-vault/, and keeps them up to date.
# Exits 1 if anything fails. Needs git and jq. Written for bash 3.2.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
usage() { sed -n '5,6p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

case "${1:-}" in
  --staged) [ $# -eq 1 ] || usage ;;
  --range) [ $# -eq 2 ] || usage ;;
  *) usage ;;
esac

root=$(git rev-parse --show-toplevel)
[ -d "$root/docs" ] || exit 0
status=0

# The notes that changed, relative to the vault.
if [ "$1" = --staged ]; then
  changed=$(git -C "$root/docs" diff --cached --relative --no-renames --name-only --diff-filter=AM -- . 2>/dev/null)
else
  changed=$(git -C "$root/docs" diff --relative --no-renames --name-only --diff-filter=AM "${2%%..*}" "${2##*..}" -- . 2>/dev/null)
fi

lint_args=()
while IFS= read -r note; do
  case "$note" in .obsidian/*) ;; *.md) [ -f "$root/docs/$note" ] && lint_args+=(--only "$note") ;; esac
done <<<"$changed"

if [ ${#lint_args[@]} -gt 0 ]; then
  if ! out=$(bash "$here/lint.sh" "$root/docs" "${lint_args[@]}" --strict); then
    echo "docs-vault: the notes this changes have errors:"
    echo
    printf '%s\n' "$out" | grep -E '^\|(---| # | [0-9]+ \| error )'
    echo
    status=1
  fi
fi

if ! out=$(bash "$here/history.sh" "$@"); then
  echo "docs-vault: this changes the vault's history:"
  echo
  printf '%s\n' "$out" | sed 's/^/  /'
  echo
  echo "Past journal days and older decisions change only by ticking a checkbox or re-pointing a link. New history goes in today's day file, and a changed mind is a new decision."
  status=1
fi

exit "$status"
