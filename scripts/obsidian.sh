#!/usr/bin/env bash
# Check that the Obsidian CLI targets this project's vault, and reload Obsidian safely.
#
#   obsidian.sh check  [--vault <dir>]    exit 0 if `obsidian` commands reach this vault
#   obsidian.sh reload [--vault <dir>]    reload Obsidian so it rereads .obsidian/*.json
#
# The vault defaults to $CLAUDE_PROJECT_DIR/docs, or ./docs. Every project's vault is
# called `docs`, so `vault=docs` is ambiguous, and the CLI talks to whichever vault was
# focused last. `check` compares the path that vault reports with this one, symlinks
# resolved, and says what to do when they differ.
#
# `reload` runs `obsidian command id=app:reload` only once `check` passes. If Obsidian
# isn't running there is nothing to reload, because it reads the settings when it starts.
# Written for bash 3.2, which macOS still ships.

set -euo pipefail

usage() { sed -n '4,5p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

[ $# -ge 1 ] || usage
mode=$1; shift
case "$mode" in check | reload) ;; *) usage ;; esac
vault=${CLAUDE_PROJECT_DIR:-.}/docs
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) [ $# -ge 2 ] || usage; vault=$2; shift 2 ;;
    *) usage ;;
  esac
done

[ -d "$vault" ] || { echo "No vault at $vault."; exit 1; }
vault=$(cd "$vault" && pwd -P)

running() { pgrep -x Obsidian >/dev/null 2>&1 || pgrep -x obsidian >/dev/null 2>&1; }

# Resolves a directory's symlinks, or prints the path as given when it doesn't exist.
real() { if [ -d "$1" ]; then (cd "$1" && pwd -P); else printf '%s\n' "$1"; fi; }

# Obsidian has opened this vault before: `obsidian vaults verbose` lists it.
known() {
  local path
  while IFS= read -r path; do
    [ "$(real "$path")" != "$vault" ] || return 0
  done < <(obsidian vaults verbose 2>/dev/null | cut -f 2-)
  return 1
}

# Prints why the CLI can't be used on this vault, or nothing when it can.
problem() {
  local target
  command -v obsidian >/dev/null 2>&1 || { echo "The Obsidian CLI isn't installed."; return 0; }
  running || { echo "Obsidian isn't running, so its CLI can't answer."; return 0; }
  target=$(obsidian vault info=path 2>/dev/null | head -n 1) || true
  [ -n "$target" ] || { echo "The Obsidian CLI didn't report a vault."; return 0; }
  [ "$(real "$target")" != "$vault" ] || return 0
  if known; then
    echo "The Obsidian CLI targets $target, not $vault, because it talks to the vault focused last. Switching to this vault's window in Obsidian points it here."
  else
    echo "Obsidian hasn't opened $vault as a vault yet, and targets $target. Opening docs/ with Open folder as vault adds it."
  fi
}

case "$mode" in
  check)
    why=$(problem)
    [ -z "$why" ] || { echo "$why Use rg and fd until it targets this vault."; exit 1; }
    echo "The Obsidian CLI targets this vault, $vault."
    ;;
  reload)
    running || { echo "Obsidian isn't running, so there's nothing to reload. It reads the settings when it next starts."; exit 0; }
    why=$(problem)
    [ -z "$why" ] ||
      { echo "Didn't reload. $why Or ask the user to run Reload app without saving from the command palette, in this vault's window."; exit 1; }
    obsidian command id=app:reload >/dev/null
    echo "Reloaded Obsidian on $vault."
    ;;
esac
