#!/usr/bin/env bash
# Tests for skills/init/scripts/init.sh: what plan reports, what apply writes, and what it keeps.

set -eu
. "$(dirname "$0")/lib.sh"

init="$repo/skills/init/scripts/init.sh"
section="$repo/skills/init/assets/CLAUDE-section.md"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Keep the user's own git settings, such as a global excludes file, out of the tests.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# project <name> [git]: makes an empty project, a git repo if asked, and prints its path.
project() {
  mkdir -p "$tmp/$1"
  [ "${2:-}" != git ] || git -C "$tmp/$1" init -q
  printf '%s\n' "$tmp/$1"
}

# run <project> <args>: runs init.sh in the project, and prints its output and any error.
run() { local p=$1; shift; (cd "$p" && "$BASH" "$init" "$@" 2>&1) || true; }

echo "init.sh: a new project"

p=$(project fresh)
check "plan lists every change" "\
.claude/settings.json: new file
  add extraKnownMarketplaces.obsidian-skills
  add extraKnownMarketplaces.docs-vault
  add enabledPlugins.obsidian@obsidian-skills
  add enabledPlugins.docs-vault@docs-vault
docs/Journal/: new folder
docs/Decisions/: new folder
CLAUDE.md: new file, with the docs-vault section
.gitignore: new file
  add docs/.obsidian/workspace.json
  add docs/.obsidian/workspace-mobile.json
  add docs/.obsidian/graph.json
  add docs/.obsidian/app.json
  add docs/.obsidian/appearance.json" \
  "$(run "$p" plan)"
check "plan changes nothing" "" "$(ls -A "$p")"

run "$p" apply >/dev/null
check "settings are written" \
  '{"extraKnownMarketplaces":{"obsidian-skills":{"source":{"source":"github","repo":"kepano/obsidian-skills"}},"docs-vault":{"source":{"source":"github","repo":"ewilazarus/docs-vault"}}},"enabledPlugins":{"obsidian@obsidian-skills":true,"docs-vault@docs-vault":true}}' \
  "$(jq -c . "$p/.claude/settings.json")"
check "folders are created" "yes" "$([ -d "$p/docs/Journal" ] && [ -d "$p/docs/Decisions" ] && echo yes)"
check "CLAUDE.md is the section" "$(cat "$section")" "$(cat "$p/CLAUDE.md")"
check ".gitignore says what it holds" "\
# Obsidian: each user's own panes, graph view, editor preferences and theme
docs/.obsidian/workspace.json
docs/.obsidian/workspace-mobile.json
docs/.obsidian/graph.json
docs/.obsidian/app.json
docs/.obsidian/appearance.json" "$(cat "$p/.gitignore")"
check "a second run changes nothing" \
  "Nothing to change: the project already has everything init sets up." "$(run "$p" apply)"

echo "init.sh: keeping what is there"

p=$(project existing git)
mkdir -p "$p/.claude" "$p/docs/Journal" "$p/docs/Decisions" "$p/docs/.obsidian"
cat >"$p/.claude/settings.json" <<'EOF'
{
  "permissions": { "allow": ["Bash(make test)"] },
  "enabledPlugins": { "docs-vault@docs-vault": false, "other@market": true }
}
EOF
echo '{"daily-notes": true, "graph": true}' >"$p/docs/.obsidian/core-plugins.json"
echo '["dataview"]' >"$p/docs/.obsidian/community-plugins.json"
printf '# Project\n\nBuild with make.' >"$p/CLAUDE.md"
printf 'node_modules/\ndocs/.obsidian/workspace*.json\n*.json\n!docs/.obsidian/graph.json\n' >"$p/.gitignore"
printf 'docs/.obsidian/app.json\n' >"$p/.git/info/exclude"
check "plan adds only what is missing, and reports what it keeps" "\
.claude/settings.json:
  add extraKnownMarketplaces.obsidian-skills
  add extraKnownMarketplaces.docs-vault
  add enabledPlugins.obsidian@obsidian-skills
  kept enabledPlugins.docs-vault@docs-vault, already false
docs/.obsidian/daily-notes.json: new file
  add folder \"Journal/\"
CLAUDE.md: append the docs-vault section
.gitignore:
  add docs/.obsidian/graph.json
  note: the vault has community plugins; --ignore-plugins ignores them too" \
  "$(run "$p" plan)"

run "$p" apply --ignore-plugins >/dev/null
check "other settings are kept" \
  '{"allow":["Bash(make test)"]} false true' \
  "$(jq -c '.permissions' "$p/.claude/settings.json") $(jq '.enabledPlugins["docs-vault@docs-vault"]' "$p/.claude/settings.json") $(jq '.enabledPlugins["other@market"]' "$p/.claude/settings.json")"
check "daily notes point at the journal" '{"folder":"Journal/"}' "$(jq -c . "$p/docs/.obsidian/daily-notes.json")"
check "the section is appended after a blank line" \
  "$(printf '# Project\n\nBuild with make.\n\n'; cat "$section")" "$(cat "$p/CLAUDE.md")"
check ".gitignore gets only the uncovered lines, in groups" "\
node_modules/
docs/.obsidian/workspace*.json
*.json
!docs/.obsidian/graph.json

# Obsidian: each user's own panes, graph view, editor preferences and theme
docs/.obsidian/graph.json

# Obsidian: community plugins, installed by each user
docs/.obsidian/plugins/" "$(cat "$p/.gitignore")"
check "a second run changes nothing" "\
.claude/settings.json:
  kept enabledPlugins.docs-vault@docs-vault, already false
Nothing to change: the project already has everything init sets up." "$(run "$p" apply --ignore-plugins)"

echo "init.sh: the CLAUDE.md section"

p=$(project marked)
mkdir -p "$p/.claude"
printf '# Project\n\n<!-- docs-vault:start -->\nOld text.\n<!-- docs-vault:end -->\n\n## Tests\n\nRun make.\n' >"$p/.claude/CLAUDE.md"
check "a marked section is updated in place" ".claude/CLAUDE.md: update the docs-vault section" \
  "$(run "$p" plan | grep CLAUDE)"
run "$p" apply >/dev/null
check "only the text between the markers changes" \
  "$(printf '# Project\n\n'; cat "$section"; printf '\n## Tests\n\nRun make.\n')" "$(cat "$p/.claude/CLAUDE.md"; echo)"
check "an up-to-date section is left alone" "" "$(run "$p" plan | grep CLAUDE || true)"

p=$(project unclosed)
printf '<!-- docs-vault:start -->\nOld text.\n' >"$p/CLAUDE.md"
check "a start marker without an end is refused" \
  "CLAUDE.md has the docs-vault start marker but no end marker. Fix it by hand, then run init.sh again." \
  "$(run "$p" plan)"
run "$p" apply >/dev/null
check "before anything is changed" "CLAUDE.md" "$(ls -A "$p")"

p=$(project agents)
printf '# Agents\n' >"$p/AGENTS.md"
check "AGENTS.md alone needs a choice" \
  "CLAUDE.md: needs a choice. The project has AGENTS.md but no CLAUDE.md: --agents-md import creates CLAUDE.md importing AGENTS.md, and --agents-md append adds the section to AGENTS.md." \
  "$(run "$p" plan | grep CLAUDE)"
check "apply refuses without the choice" \
  "The project has AGENTS.md but no CLAUDE.md. Pass --agents-md import or --agents-md append." \
  "$(run "$p" apply)"
check "and changes nothing" "AGENTS.md" "$(ls -A "$p")"
run "$p" apply --agents-md import >/dev/null
check "import creates CLAUDE.md with the import first" \
  "$(printf '@AGENTS.md\n\n'; cat "$section")" "$(cat "$p/CLAUDE.md")"

p=$(project agents-append)
printf '# Agents\n' >"$p/AGENTS.md"
run "$p" apply --agents-md append >/dev/null
check "append adds the section to AGENTS.md" "$(printf '# Agents\n\n'; cat "$section")" "$(cat "$p/AGENTS.md")"
check "and a later run finds it there" "" "$(run "$p" plan | grep -i 'md:' || true)"

echo "init.sh: problems"

p=$(project broken)
mkdir -p "$p/.claude"
echo '{ not json' >"$p/.claude/settings.json"
check "invalid settings are refused" \
  ".claude/settings.json isn't valid JSON. Fix it, then run init.sh again." "$(run "$p" plan)"

p=$(project daily)
mkdir -p "$p/docs/.obsidian"
echo '["daily-notes"]' >"$p/docs/.obsidian/core-plugins.json"
echo '{"folder": "Daily", "format": "YYYY-MM-DD"}' >"$p/docs/.obsidian/daily-notes.json"
check "a daily notes folder set elsewhere is kept" "\
docs/.obsidian/daily-notes.json:
  kept folder, already \"Daily\"" "$(run "$p" plan | grep -A1 daily-notes)"

finish
