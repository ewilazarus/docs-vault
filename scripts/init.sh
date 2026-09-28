#!/usr/bin/env bash
# Make init's file changes in a project, without overwriting anything.
#
#   init.sh plan  [--agents-md import|append] [--ignore-plugins] [--checks]   show, change nothing
#   init.sh apply [--agents-md import|append] [--ignore-plugins] [--checks]
#
# Run it from the project root. It:
#
# - adds the two marketplaces and plugins to .claude/settings.json, keeping everything else
#   in the file;
# - creates docs/Journal/ and docs/Decisions/;
# - points the Daily notes core plugin at Journal/, if it is enabled;
# - writes the docs-vault section from assets/CLAUDE-section.md: between its markers in
#   CLAUDE.md, .claude/CLAUDE.md or AGENTS.md if they are there, or else appended to
#   CLAUDE.md. A project with only AGENTS.md needs --agents-md: `import` creates CLAUDE.md
#   with `@AGENTS.md` and the section, and `append` adds the section to AGENTS.md;
# - adds to .gitignore the Obsidian per-user settings it doesn't ignore yet, and with
#   --ignore-plugins the community plugins too;
# - with --checks, copies the lint skill's check.sh, lint.sh and history.sh into
#   .docs-vault/, so git can run them without the plugin, installs a pre-commit hook that
#   runs `.docs-vault/check.sh --staged` unless the clone already has one, and on GitHub
#   adds a workflow that runs it on every push and pull request. Once .docs-vault/ exists,
#   every run keeps its copies up to date, with or without --checks.
#
# A setting that already has a different value is reported as kept, never changed, so a
# plugin someone disabled stays disabled. Running it again changes nothing. Only the
# project's own .gitignore files count: a global or .git/info/exclude rule is personal,
# and doesn't cover anyone else. Needs jq. Written for bash 3.2, which macOS still ships.

set -euo pipefail

command -v jq >/dev/null || { echo "init.sh needs jq" >&2; exit 2; }

section_file="$(cd "$(dirname "$0")/.." && pwd)/assets/CLAUDE-section.md"
start_marker="<!-- docs-vault:start -->"
end_marker="<!-- docs-vault:end -->"

wanted_settings='{
  "extraKnownMarketplaces": {
    "obsidian-skills": { "source": { "source": "github", "repo": "kepano/obsidian-skills" } },
    "docs-vault": { "source": { "source": "github", "repo": "ewilazarus/docs-vault" } }
  },
  "enabledPlugins": { "obsidian@obsidian-skills": true, "docs-vault@docs-vault": true }
}'

personal_ignores="docs/.obsidian/workspace.json docs/.obsidian/workspace-mobile.json docs/.obsidian/graph.json docs/.obsidian/app.json docs/.obsidian/appearance.json"
plugin_ignores="docs/.obsidian/plugins/ docs/.obsidian/community-plugins.json"

usage() { sed -n '4,5p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { echo "$*" >&2; exit 2; }

[ $# -ge 1 ] || usage
mode=$1; shift
case "$mode" in plan | apply) ;; *) usage ;; esac
agents_md="" ignore_plugins="" checks=""
while [ $# -gt 0 ]; do
  case "$1" in
    --agents-md)
      [ $# -ge 2 ] || usage
      agents_md=$2; shift 2
      case "$agents_md" in import | append) ;; *) usage ;; esac
      ;;
    --ignore-plugins) ignore_plugins=1; shift ;;
    --checks) checks=1; shift ;;
    *) usage ;;
  esac
done

changes=""
# change <line>: prints a line that describes a change.
change() { changes=1; printf '%s\n' "$1"; }
applying() { [ "$mode" = apply ]; }

# write <file>: replaces the file with stdin, once stdin has been read in full.
write() { mkdir -p "$(dirname "$1")"; cat >"$1.tmp"; mv "$1.tmp" "$1"; }

# ends_open <file>: the file is not empty and its last line has no newline.
ends_open() { [ -s "$1" ] && [ -n "$(tail -c 1 "$1")" ]; }

# --- .claude/settings.json ---------------------------------------------------------------

settings() {
  local file=.claude/settings.json current lines
  current='{}'
  if [ -f "$file" ]; then
    current=$(jq . "$file" 2>/dev/null) || die "$file isn't valid JSON. Fix it, then run init.sh again."
  fi
  lines=$(jq -rn --argjson have "$current" --argjson want "$wanted_settings" '
    $want | to_entries[] | .key as $section | .value | keys_unsorted[] as $key
    | ($have[$section][$key]) as $value
    | if $value == null then "  add \($section).\($key)"
      elif $value == $want[$section][$key] then empty
      else "  kept \($section).\($key), already \($value | tojson)" end')
  [ -n "$lines" ] || return 0
  case "$lines" in
    *"  add "*) change "$file:$([ -f "$file" ] || echo " new file")" ;;
    *) printf '%s:\n' "$file" ;;
  esac
  printf '%s\n' "$lines"
  applying || return 0
  jq -n --argjson have "$current" --argjson want "$wanted_settings" '
    reduce ($want | to_entries[]) as $s ($have;
      reduce ($s.value | keys_unsorted[]) as $k (.;
        if .[$s.key][$k] == null then .[$s.key][$k] = $s.value[$k] else . end))' | write "$file"
}

# --- folders ---------------------------------------------------------------------------

folders() {
  local dir
  for dir in docs/Journal docs/Decisions; do
    [ -d "$dir" ] && continue
    change "$dir/: new folder"
    if applying; then mkdir -p "$dir"; fi
  done
  return 0
}

# --- Daily notes -------------------------------------------------------------------------

daily_notes() {
  local core=docs/.obsidian/core-plugins.json file=docs/.obsidian/daily-notes.json folder=""
  [ -f "$core" ] || return 0
  jq -e 'if type == "array" then index("daily-notes") != null else .["daily-notes"] == true end' \
    "$core" >/dev/null 2>&1 || return 0
  [ -f "$file" ] && folder=$(jq -r '.folder // ""' "$file")
  case "$folder" in
    Journal | Journal/) ;;
    "")
      change "$file:$([ -f "$file" ] || echo " new file")"
      echo "  add folder \"Journal/\""
      if applying; then
        { [ -f "$file" ] && cat "$file" || echo '{}'; } | jq '.folder = "Journal/"' | write "$file"
      fi
      ;;
    *) printf '%s:\n  kept folder, already "%s"\n' "$file" "$folder" ;;
  esac
}

# --- CLAUDE.md ---------------------------------------------------------------------------

# The file with the docs-vault markers, if any.
marked_file() {
  local f
  for f in CLAUDE.md .claude/CLAUDE.md AGENTS.md; do
    [ -f "$f" ] && grep -qxF "$start_marker" "$f" && { echo "$f"; return 0; }
  done
  return 0
}

# The CLAUDE.md to append to, if there is one.
claude_md() {
  local f
  for f in CLAUDE.md .claude/CLAUDE.md; do
    [ -f "$f" ] && { echo "$f"; return 0; }
  done
  return 0
}

# Prints the file with the text between its markers replaced by the section.
replaced() {
  awk -v section="$section_file" -v start="$start_marker" -v end="$end_marker" '
    $0 == start && !done { while ((getline line < section) > 0) print line; inside = 1; next }
    inside { if ($0 == end) { inside = 0; done = 1 } next }
    { print }
    END { if (inside) exit 3 }' "$1"
}

append_section() {
  if ends_open "$1"; then echo >>"$1"; fi
  if [ -s "$1" ]; then echo >>"$1"; fi
  cat "$section_file" >>"$1"
}

section() {
  local file new
  file=$(marked_file)
  if [ -n "$file" ]; then
    # The trailing x keeps the file's final newlines through $().
    new=$(replaced "$file" && printf x)
    [ "$new" != "$(cat "$file"; printf x)" ] || return 0
    change "$file: update the docs-vault section"
    if applying; then printf '%s' "${new%x}" | write "$file"; fi
    return 0
  fi
  file=$(claude_md)
  if [ -n "$file" ]; then
    change "$file: append the docs-vault section"
    if applying; then append_section "$file"; fi
  elif [ -f AGENTS.md ]; then
    case "$agents_md" in
      import)
        change "CLAUDE.md: new file, importing AGENTS.md, with the docs-vault section"
        if applying; then { printf '@AGENTS.md\n\n'; cat "$section_file"; } | write CLAUDE.md; fi
        ;;
      append)
        change "AGENTS.md: append the docs-vault section"
        if applying; then append_section AGENTS.md; fi
        ;;
      *) change "CLAUDE.md: needs a choice. The project has AGENTS.md but no CLAUDE.md: --agents-md import creates CLAUDE.md importing AGENTS.md, and --agents-md append adds the section to AGENTS.md." ;;
    esac
  else
    change "CLAUDE.md: new file, with the docs-vault section"
    if applying; then write CLAUDE.md <"$section_file"; fi
  fi
}

# --- .gitignore --------------------------------------------------------------------------

in_git=""
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && in_git=1

# ignored <path>: a .gitignore in the project already ignores the path.
ignored() {
  local path=$1 out source pattern
  case "$path" in */) path="${path}x" ;; esac
  if [ -z "$in_git" ]; then
    [ -f .gitignore ] && grep -qxF "$1" .gitignore
    return
  fi
  out=$(git check-ignore -v --no-index "$path" 2>/dev/null) || return 1
  source=${out%%:*}
  pattern=$(printf '%s' "$out" | cut -f 1 | cut -d : -f 3-)
  case "$source" in /* | .git/*) return 1 ;; esac
  case "$source" in .gitignore | */.gitignore) ;; *) return 1 ;; esac
  case "$pattern" in '!'*) return 1 ;; esac
  return 0
}

# missing <paths>: prints the paths that aren't ignored yet.
missing() {
  local path
  for path in $1; do ignored "$path" || echo "$path"; done
  return 0
}

gitignore() {
  local personal plugins="" header_shown=""
  personal=$(missing "$personal_ignores")
  if [ -n "$ignore_plugins" ]; then plugins=$(missing "$plugin_ignores"); fi
  if [ -n "$personal$plugins" ]; then
    change ".gitignore:$([ -f .gitignore ] || echo " new file")"
    header_shown=1
    [ -z "$personal" ] || printf '%s\n' "$personal" | sed 's/^/  add /'
    [ -z "$plugins" ] || printf '%s\n' "$plugins" | sed 's/^/  add /'
    if applying; then
      if ends_open .gitignore; then echo >>.gitignore; fi
      if [ -n "$personal" ]; then
        [ -s .gitignore ] && echo >>.gitignore
        { echo "# Obsidian: each user's own panes, graph view, editor preferences and theme"
          printf '%s\n' "$personal"; } >>.gitignore
      fi
      if [ -n "$plugins" ]; then
        [ -s .gitignore ] && echo >>.gitignore
        { echo "# Obsidian: community plugins, installed by each user"
          printf '%s\n' "$plugins"; } >>.gitignore
      fi
    fi
  fi
  if [ -z "$ignore_plugins" ] && [ -f docs/.obsidian/community-plugins.json ] &&
    [ -n "$(missing "$plugin_ignores")" ]; then
    [ -n "$header_shown" ] || printf '.gitignore:\n'
    echo "  note: the vault has community plugins; --ignore-plugins ignores them too"
  fi
  return 0
}

# --- the git checks ----------------------------------------------------------------------

# The lint skill's scripts, in the plugin or in a copied docs-vault-lint skill.
lint_scripts=""
dir="$(dirname "$0")"
[ -f "$dir/check.sh" ] && lint_scripts=$(cd "$dir" && pwd)

pre_commit='#!/bin/sh
# docs-vault: check the docs vault before each commit. Skip once with --no-verify.
exec .docs-vault/check.sh --staged
'

workflow='name: docs-vault

# Checks the docs vault in every pushed commit: lint errors in the notes that changed, and
# the rule that past journal days and older decisions keep their prose.

on:
  push:
  pull_request:

jobs:
  vault:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0
      - name: Check the docs vault
        env:
          BASE: ${{ github.event.pull_request.base.sha || github.event.before }}
          DEFAULT_BRANCH: ${{ github.event.repository.default_branch }}
        run: |
          # A new branch has no "before": check what it adds to the default branch.
          if ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then
            BASE=$(git merge-base HEAD "origin/$DEFAULT_BRANCH" 2>/dev/null || git rev-list --max-parents=0 HEAD | tail -n 1)
          fi
          .docs-vault/check.sh --range "$BASE..HEAD"
'

checks() {
  local name hooks hook
  [ -n "$checks" ] || [ -d .docs-vault ] || return 0
  [ -n "$lint_scripts" ] || { printf '.docs-vault/:\n  note: the lint skill'"'"'s scripts weren'"'"'t found next to init, so it wasn'"'"'t set up\n'; return 0; }
  for name in check.sh lint.sh history.sh; do
    if [ ! -f ".docs-vault/$name" ]; then
      change ".docs-vault/$name: new file"
    elif ! cmp -s "$lint_scripts/$name" ".docs-vault/$name"; then
      change ".docs-vault/$name: update to the plugin's version"
    else
      continue
    fi
    if applying; then mkdir -p .docs-vault; cp "$lint_scripts/$name" ".docs-vault/$name"; chmod +x ".docs-vault/$name"; fi
  done
  [ -n "$checks" ] || return 0

  if [ -z "$in_git" ]; then
    printf 'pre-commit hook:\n  note: not a git repository yet, so no hook; run init again once it is\n'
  else
    hooks=$(git rev-parse --git-path hooks)
    hook="$hooks/pre-commit"
    if [ ! -f "$hook" ]; then
      change "$hook: new file, runs .docs-vault/check.sh --staged"
      if applying; then mkdir -p "$hooks"; printf '%s' "$pre_commit" >"$hook"; chmod +x "$hook"; fi
    elif ! grep -q '.docs-vault/check.sh' "$hook"; then
      printf '%s:\n  kept, it is someone else'"'"'s; add `.docs-vault/check.sh --staged` to it\n' "$hook"
    fi
  fi

  if [ -f .github/workflows/docs-vault.yml ]; then
    :
  elif [ -d .github ] || git remote -v 2>/dev/null | grep -q 'github\.com'; then
    change ".github/workflows/docs-vault.yml: new file, runs the check on every push and pull request"
    if applying; then printf '%s' "$workflow" | write .github/workflows/docs-vault.yml; fi
  else
    printf 'CI:\n  note: not on GitHub; run `.docs-vault/check.sh --range <base>..HEAD` in your CI\n'
  fi
}

# --- run ---------------------------------------------------------------------------------

# Refuse before changing anything, rather than stop halfway.
marked=$(marked_file)
if [ -n "$marked" ] && ! replaced "$marked" >/dev/null; then
  die "$marked has the docs-vault start marker but no end marker. Fix it by hand, then run init.sh again."
fi
if applying && [ -z "$agents_md" ] && [ -z "$(marked_file)" ] && [ -z "$(claude_md)" ] && [ -f AGENTS.md ]; then
  die "The project has AGENTS.md but no CLAUDE.md. Pass --agents-md import or --agents-md append."
fi

settings
folders
daily_notes
section
gitignore
checks
[ -n "$changes" ] || echo "Nothing to change: the project already has everything init sets up."
