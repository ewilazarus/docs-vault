#!/usr/bin/env bash
# Install the docs-vault plugin for Claude Code, and kepano's obsidian plugin it depends on.
#
#   curl -fsSL https://raw.githubusercontent.com/ewilazarus/docs-vault/main/bootstrap.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/ewilazarus/docs-vault/main/bootstrap.sh | bash -s -- --project
#
# By default the plugins are installed for you, in every project. With --project, run from
# a project's root, they are declared in its .claude/settings.json instead, so everyone who
# opens the project is offered them. --dry-run prints the commands without running them.
#
# It adds the two marketplaces, then installs docs-vault, which brings obsidian along. A
# step that is already done is skipped, and an installed docs-vault is updated instead, so
# it is safe to run again. Then run /docs-vault:init in a project to set up its vault.
# Needs the `claude` CLI. The plugin's hooks and scripts also need jq and git.

set -euo pipefail

main() {
  local scope=user dry_run="" arg
  for arg in "$@"; do
    case "$arg" in
      --project) scope=project ;;
      --dry-run) dry_run=1 ;;
      -h | --help) sed -n '2,14p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null | sed 's/^# \{0,1\}//'; return 0 ;;
      *) fail "Unknown option: $arg. Use --project, --dry-run or --help." ;;
    esac
  done

  command -v claude >/dev/null 2>&1 ||
    fail "The claude CLI isn't on your PATH. Install Claude Code first: https://docs.claude.com/en/docs/claude-code"
  command -v jq >/dev/null 2>&1 ||
    warn "jq isn't installed. docs-vault's hooks and scripts need it: install it with your package manager (brew install jq, apt install jq)."
  command -v git >/dev/null 2>&1 ||
    warn "git isn't installed. docs-vault uses it to number decisions and check the vault."

  if [ "$scope" = project ]; then
    git rev-parse --show-toplevel >/dev/null 2>&1 ||
      warn "This isn't a git repository. --project writes .claude/settings.json here, in $(pwd)."
  fi

  # A project-scope install is listed once per project, with its projectPath.
  local marketplaces plugins here
  here=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
  marketplaces=$(listing "claude plugin marketplace list --json" '.[].name')
  plugins=$(listing "claude plugin list --json" \
    '.[] | select(.scope == $scope and (.scope == "user" or .projectPath == $here)) | .id')

  add_marketplace obsidian-skills kepano/obsidian-skills
  add_marketplace docs-vault ewilazarus/docs-vault

  if printf '%s\n' "$plugins" | grep -qx 'docs-vault@docs-vault'; then
    say "docs-vault is installed ($scope); updating it."
    run claude plugin marketplace update docs-vault
    run claude plugin update docs-vault@docs-vault --scope "$scope"
  else
    say "Installing docs-vault ($scope), with the obsidian plugin it depends on."
    run claude plugin install docs-vault@docs-vault --scope "$scope"
  fi

  echo
  say "Done. Restart Claude Code, open a project, and run /docs-vault:init to set up its docs/ vault."
  [ "$scope" = user ] ||
    say "Commit .claude/settings.json, so everyone who opens the project is offered the plugins."
}

say() { printf 'docs-vault: %s\n' "$*"; }
warn() { printf 'docs-vault: warning: %s\n' "$*" >&2; }
fail() { printf 'docs-vault: %s\n' "$*" >&2; exit 1; }

# run <command...>: runs it, or only prints it with --dry-run. stdin is closed, so nothing
# reads the rest of this script when it arrives through a pipe.
run() {
  printf '  $ %s\n' "$*"
  [ -n "$dry_run" ] || "$@" </dev/null
}

# listing <command> <jq filter>: the names a JSON listing reports, one per line, or nothing
# when jq is missing or the listing fails, in which case every step simply runs.
listing() {
  command -v jq >/dev/null 2>&1 || return 0
  $1 </dev/null 2>/dev/null | jq -r --arg scope "$scope" --arg here "${here:-}" "$2" 2>/dev/null || true
}

add_marketplace() {
  local name=$1 repo=$2
  if [ "$scope" = user ] && printf '%s\n' "$marketplaces" | grep -qx "$name"; then
    say "The $name marketplace is already added."
    return 0
  fi
  if [ "$scope" = project ] && [ -f .claude/settings.json ] && command -v jq >/dev/null 2>&1 &&
    jq -e --arg n "$name" '.extraKnownMarketplaces[$n]' .claude/settings.json >/dev/null 2>&1; then
    say "The $name marketplace is already declared in .claude/settings.json."
    return 0
  fi
  say "Adding the $name marketplace ($repo)."
  run claude plugin marketplace add "$repo" --scope "$scope"
}

main "$@"
