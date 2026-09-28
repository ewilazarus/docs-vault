#!/usr/bin/env bash
# Tests for hooks/vault_guard.sh: skill tracking, the reminder, and which writes it lets through.

set -eu
. "$(dirname "$0")/lib.sh"

guard="$repo/hooks/vault_guard.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

project="$tmp/project"
docs="$project/docs"
mkdir -p "$docs/Journal" "$docs/Decisions" "$docs/.obsidian"
export CLAUDE_PROJECT_DIR=$project CLAUDE_PLUGIN_DATA="$tmp/data"

today=$(date +%F)
past=2020-01-01

cat >"$docs/Journal/$past.md" <<'EOF'
---
description: "Reworked backups."
---

## Summary

- Reworked backups around restic. See [[Backups]].

## Follow-ups

- [ ] Verify the restore path.
  - [ ] Restore one file.
  - [x] Write the runbook.
* [x] Rotate the keys.
EOF

cat >"$docs/Decisions/00001-use-postgres.md" <<'EOF'
---
description: "Store data in Postgres."
date: 2020-01-01
---

# Use Postgres

## Why

The team already runs it. See [[Databases]].
EOF

session=s1
agent=""

# run <json>: feeds one hook event to the guard and prints its decision: "deny", "remind",
# or "allow" when it prints nothing.
run() {
  local out
  out=$(printf '%s' "$1" | "$BASH" "$guard")
  if [ -z "$out" ]; then
    echo allow
  elif [ "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$out")" = deny ]; then
    echo deny
  elif [ -n "$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$out")" ]; then
    echo remind
  else
    echo "unexpected: $out"
  fi
}

# event <json fields>: common fields for this session and agent, merged with the given ones.
event() {
  jq -nc --arg s "$session" --arg a "$agent" --arg cwd "$project" --argjson extra "$1" \
    '{session_id: $s, cwd: $cwd} + (if $a == "" then {} else {agent_id: $a} end) + $extra'
}

load_skill() {
  run "$(event "$(jq -nc --arg k "$1" '{hook_event_name: "PostToolUse", tool_name: "Skill", tool_input: {skill: $k}}')")" >/dev/null
}

load_command() {
  run "$(event "$(jq -nc --arg k "$1" '{hook_event_name: "UserPromptExpansion", command_name: $k}')")" >/dev/null
}

read_file() {
  run "$(event "$(jq -nc --arg p "$docs/$1" '{hook_event_name: "PreToolUse", tool_name: "Read", tool_input: {file_path: $p}}')")"
}

write_file() {
  run "$(event "$(jq -nc --arg p "$docs/$1" --arg c "$2" '{hook_event_name: "PreToolUse", tool_name: "Write", tool_input: {file_path: $p, content: $c}}')")"
}

edit_file() {
  run "$(event "$(jq -nc --arg p "$docs/$1" --arg o "$2" --arg n "$3" '{hook_event_name: "PreToolUse", tool_name: "Edit", tool_input: {file_path: $p, old_string: $o, new_string: $n}}')")"
}

echo "vault_guard.sh: loading skills"

check "reading docs without recall reminds" remind "$(read_file Conventions.md)"
check "writing docs without record is denied" deny "$(write_file Notes.md "x")"
check "reading .obsidian/ doesn't remind" allow "$(read_file .obsidian/app.json)"
check "writing .obsidian/ without record is allowed" allow "$(write_file .obsidian/app.json "{}")"
check "files outside docs/ are ignored" allow \
  "$(run "$(event "$(jq -nc --arg p "$project/src/main.sh" '{hook_event_name: "PreToolUse", tool_name: "Write", tool_input: {file_path: $p, content: "x"}}')")")"

load_skill docs-vault:recall
check "reading docs with recall loaded is quiet" allow "$(read_file Conventions.md)"

load_skill docs-vault:record
check "writing a note with the plugin's record loaded" allow "$(write_file Notes.md "x")"

agent=sub1
check "a subagent doesn't inherit the parent's record" deny "$(write_file Notes.md "x")"
load_skill docs-vault:record
check "a subagent that loads record may write" allow "$(write_file Notes.md "x")"
agent=""

session=s2
load_command docs-vault-record
check "a copied record skill counts" allow "$(write_file Notes.md "x")"

session=s3
load_command /docs-vault:init
check "init counts as a writer" allow "$(write_file "Journal/$today.md" "## Summary")"

session=s4
load_skill docs-vault:record

echo "vault_guard.sh: today's journal"

check "creating today's journal" allow \
  "$(write_file "Journal/$today.md" $'---\ndescription: "Investigated auth."\n---\n\n## Summary\n\n- Investigated moving authorization into middleware.\n')"
check "consolidating today's summary" allow \
  "$(edit_file "Journal/$today.md" "- Investigated moving authorization into middleware." "- Implemented authorization in middleware after comparing it with a router-level approach.")"
check "adding a follow-up today" allow \
  "$(edit_file "Journal/$today.md" "## Summary" $'## Follow-ups\n\n- [ ] Verify auth behind the proxy.')"

echo "vault_guard.sh: past journal"

check "creating a future day is denied" deny "$(write_file "Journal/2999-01-01.md" "## Summary")"
printf '## Summary\n' >"$docs/Journal/2999-01-02.md"
check "editing an existing future day is denied" deny \
  "$(edit_file "Journal/2999-01-02.md" "## Summary" $'## Summary\n\n- Planned.')"
check "creating a future decision is denied" deny "$(write_file "Decisions/2999-01-01-01-plan.md" "# Plan")"
check "creating a backdated day is denied" deny "$(write_file "Journal/2020-01-02.md" "## Summary")"
check "rewriting past summary prose is denied" deny \
  "$(edit_file "Journal/$past.md" "- Reworked backups around restic." "- Reworked backups around restic, which was a mistake.")"
check "ticking a past top-level follow-up" allow \
  "$(edit_file "Journal/$past.md" "- [ ] Verify the restore path." "- [x] Verify the restore path.")"
check "unticking a past follow-up" allow \
  "$(edit_file "Journal/$past.md" "* [x] Rotate the keys." "* [ ] Rotate the keys.")"
check "ticking a past nested box" allow \
  "$(edit_file "Journal/$past.md" "  - [ ] Restore one file." "  - [x] Restore one file.")"
check "changing task text while ticking is denied" deny \
  "$(edit_file "Journal/$past.md" "- [ ] Verify the restore path." "- [x] Verify the restore path on the new server.")"
check "adding a follow-up to a past day is denied" deny \
  "$(edit_file "Journal/$past.md" "* [x] Rotate the keys." $'* [x] Rotate the keys.\n- [ ] Rotate them again.')"
check "adding a decision link to a past day is denied" deny \
  "$(edit_file "Journal/$past.md" "## Follow-ups" $'## Decisions\n\n- [[Decisions/00001-use-postgres|Use Postgres]]\n\n## Follow-ups')"
check "re-pointing a past link while keeping its text" allow \
  "$(edit_file "Journal/$past.md" "See [[Backups]]." "See [[Runbooks/Backups|Backups]].")"

current=$(cat "$docs/Journal/$past.md"; printf x) current=${current%x}
open_box='- [ ] Verify' ticked_box='- [x] Verify'
check "rewriting a whole past day with only a box changed" allow \
  "$(write_file "Journal/$past.md" "${current/"$open_box"/$ticked_box}")"
check "rewriting a whole past day with a new line is denied" deny \
  "$(write_file "Journal/$past.md" "${current}- [ ] Something new.
")"

echo "vault_guard.sh: decisions"

decision() { printf -- '---\ndescription: "%s"\ndate: %s\n---\n\n# %s\n' "$1" "$2" "$1"; }

check "creating the next decision, dated today" allow \
  "$(write_file "Decisions/00002-authorization-lives-in-middleware.md" "$(decision "Authorization lives in middleware" "$today")")"
check "creating a decision with a dated name is denied" deny \
  "$(write_file "Decisions/$today-01-authorization.md" "$(decision "Authorization" "$today")")"
check "creating a decision without a number is denied" deny \
  "$(write_file "Decisions/authorization-lives-in-middleware.md" "$(decision "x" "$today")")"
check "creating a decision without today's date is denied" deny \
  "$(write_file "Decisions/00002-use-sqlite.md" "$(decision "Use SQLite" 2020-01-02)")"
check "creating a decision without a date is denied" deny \
  "$(write_file "Decisions/00002-use-sqlite.md" "# Use SQLite")"
check "reusing a decision number is denied" deny \
  "$(write_file "Decisions/00001-use-sqlite.md" "$(decision "Use SQLite" "$today")")"
decision "Authorization lives in middleware" "$today" >"$docs/Decisions/00002-authorization-lives-in-middleware.md"
check "filling in a lower number is denied" deny \
  "$(write_file "Decisions/00001-use-sqlite.md" "$(decision "Use SQLite" "$today")")"
check "refining a decision made today" allow \
  "$(edit_file "Decisions/00002-authorization-lives-in-middleware.md" "# Authorization lives in middleware" $'# Authorization lives in middleware\n\n## Why\n\nNested routes.')"
check "rewriting an old decision's rationale is denied" deny \
  "$(edit_file "Decisions/00001-use-postgres.md" "The team already runs it." "SQLite turned out simpler.")"
check "re-dating an old decision to today is denied" deny \
  "$(edit_file "Decisions/00001-use-postgres.md" "date: 2020-01-01" "date: $today")"
check "re-pointing a link in an old decision" allow \
  "$(edit_file "Decisions/00001-use-postgres.md" "[[Databases]]" "[[Reference/Databases|Databases]]")"
check "a superseding decision is a new file" allow \
  "$(write_file "Decisions/00003-use-sqlite.md" "$(decision "Use SQLite" "$today")
## Related

- Supersedes [[Decisions/00001-use-postgres|Use Postgres]]")"

echo "vault_guard.sh: section references"

check "a bare section reference is denied" deny \
  "$(write_file Notes.md "Specified in Spec §4.2.")"
check "a heading link to a section" allow \
  "$(write_file Notes.md "Specified in [[Spec#4.2 Assertion|Spec §4.2]].")"
check "an escaped heading link in a table" allow \
  "$(write_file Notes.md "| field | [[#2.6 Repository IDs\\|§2.6]] |")"
check "a Markdown link to an outside section" allow \
  "$(write_file Notes.md "See [RFC 8949 §4.2.1](https://www.rfc-editor.org/rfc/rfc8949#section-4.2.1).")"
check "a reference in code" allow \
  "$(write_file Notes.md $'Use `§4` literally.\n\n```\nsee §53\n```\n')"
printf 'Legacy text, see §7.\n' >"$docs/Legacy.md"
check "editing near an existing bare reference" allow \
  "$(edit_file Legacy.md "Legacy text, see §7." "Legacy notes, see §7.")"
check "adding one to a file that has some is denied" deny \
  "$(edit_file Legacy.md "Legacy text, see §7." "Legacy text, see §7 and §8.")"
check "a bare reference in today's journal is denied" deny \
  "$(edit_file "Journal/$today.md" "## Summary" $'## Summary\n\n- Settled §7.')"

echo "vault_guard.sh: linting a written note"

# written <path> <content>: puts the note on disk, then sends the PostToolUse of its Write.
written() {
  mkdir -p "$(dirname "$docs/$1")"
  printf '%s' "$2" >"$docs/$1"
  printf '%s' "$(event "$(jq -nc --arg p "$docs/$1" --arg c "$2" '{hook_event_name: "PostToolUse", tool_name: "Write", tool_input: {file_path: $p, content: $c}}')")" |
    "$BASH" "$guard"
}

check "a clean note is quiet" "" "$(written Linted.md "See [[Legacy]].")"
check "a warning alone is quiet" "" \
  "$(written "Journal/$today.md" $'---\ndescription: "x"\n---\n\n## Summary\n\n- Done.\n\n## Follow-ups\n')"
check "a note outside the vault is quiet" "" \
  "$(printf '%s' "$(event "$(jq -nc --arg p "$project/README.md" '{hook_event_name: "PostToolUse", tool_name: "Write", tool_input: {file_path: $p}}')")" | "$BASH" "$guard")"
check "an error is handed back as context" "\
PostToolUse
The lint script found errors in Linted.md after this write. Fix them now, in the same way as the rest of this change:

| # | Severity | Where | Problem |
|---|---|---|---|
| 1 | error | \`Linted.md:1\` | Broken link \`[[Legacy#Missing]]\`: no heading \`Missing\` in \`Legacy.md\`. |
| 2 | error | \`Linted.md:1\` | Broken link \`[[Nowhere]]\`: no file named \`Nowhere\`. |" \
  "$(written Linted.md "See [[Nowhere]] and [[Legacy#Missing]]." | jq -r '.hookSpecificOutput | .hookEventName, .additionalContext')"
check "another note's errors aren't reported" "" "$(written Other.md "Fine.")"

echo "vault_guard.sh: failing open"

out=$(printf 'not json' | "$BASH" "$guard" 2>/dev/null) && status=0 || status=$?
check "bad input lets the action through with a non-blocking error" "1:" "$status:$out"

finish
