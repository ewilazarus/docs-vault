#!/usr/bin/env bash
# Keep work on the docs/ vault going through the docs-vault skills.
#
# One script, three hook events:
#
# - PostToolUse(Skill) and UserPromptExpansion note which docs-vault skills this session
#   (or subagent) has loaded.
# - PreToolUse on file tools:
#   - docs/.obsidian/ holds Obsidian's settings, not notes, so it is left alone;
#   - reading docs/ without `recall` loaded adds a reminder to load it;
#   - writing docs/ without `record` (or `init`) loaded is denied;
#   - a write that adds a bare section reference (`§4.2`) outside a link or code is denied;
#   - today's journal day, and decisions dated today, may be rewritten freely;
#   - a past journal day, or a decision dated before today, may only change the state of
#     its checkboxes or re-point a wikilink while keeping its displayed text;
#   - a new journal day or decision must be dated today, and a future journal day can't be
#     written at all.
#
# The history check enforces the shape of a change (only checkbox state and link targets
# move), not its meaning: it doesn't know whether a box sits under `## Follow-ups`. The
# todos script applies those semantics. The hook only sees Claude's file tools, so shell
# commands stay an escape hatch that needs the same trust as before.
#
# Needs jq. Anything unexpected fails open: the tool call goes through and the error is
# reported as a non-blocking hook error. Written for bash 3.2, which macOS still ships.

set -euo pipefail
trap 'echo "docs-vault hook failed, allowing the action (line $LINENO)" >&2; exit 1' ERR

command -v jq >/dev/null || { echo "docs-vault hook needs jq, allowing the action" >&2; exit 1; }

input=$(cat)
fields=$(jq -r '@sh "
  event=\(.hook_event_name // "")
  session=\(.session_id // "unknown")
  agent=\(.agent_id // "main")
  cwd=\(.cwd // "")
  tool=\(.tool_name // "")
  skill_called=\(.tool_input.skill // .tool_input.skill_name // "")
  command_name=\(.command_name // "")
  target=\(.tool_input.file_path // .tool_input.path // "")
"' <<<"$input")
eval "$fields"

project=${CLAUDE_PROJECT_DIR:-${cwd:-$PWD}}
[ -n "$cwd" ] || cwd=$project
state_dir="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/docs-vault}/sessions"
# A subagent has its own context, so a skill loaded by the parent doesn't count for it.
state_key=$(printf '%s--%s' "$session" "$agent" | tr -c 'A-Za-z0-9_.-' '_')

# --- which skills are loaded -------------------------------------------------------------

# `docs-vault:record`, `/docs-vault:record`, `docs-vault:docs-vault-record` or
# `docs-vault-record` -> `record`.
#
# Rewriting history (backdated decisions, past journal prose) is meant for a dedicated
# backfill skill only. When it exists, give it its own name here and its own narrow rules
# below, applied only while it is loaded. Don't relax the rules for `record`.
skill_from() {
  case "${1#/}" in
    docs-vault:recall | docs-vault:docs-vault-recall | docs-vault-recall) echo recall ;;
    docs-vault:record | docs-vault:docs-vault-record | docs-vault-record) echo record ;;
    docs-vault:init | docs-vault:docs-vault-init | docs-vault-init) echo init ;;
  esac
}

loaded() { [ -e "$state_dir/$state_key.$1" ]; }

mark() {
  [ -n "$1" ] || return 0
  mkdir -p "$state_dir"
  touch "$state_dir/$state_key.$1"
  find "$state_dir" -type f -mtime +7 -delete 2>/dev/null || true
}

# --- responses ---------------------------------------------------------------------------

deny() {
  jq -n --arg reason "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

remind() {
  jq -n --arg context "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $context}}'
  exit 0
}

# --- paths -------------------------------------------------------------------------------

# Resolve symlinks in the deepest existing directory, since the file itself may not exist yet.
resolve() {
  local path=$1 dir base
  case "$path" in /*) ;; *) path="$cwd/$path" ;; esac
  dir=$(dirname "$path") base=$(basename "$path")
  if [ -d "$path" ]; then
    (cd "$path" && pwd -P)
  elif [ -d "$dir" ]; then
    printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
  else
    printf '%s\n' "$path"
  fi
}

# Print the path relative to docs/, or fail when it's outside the vault.
vault_relative() {
  [ -n "$1" ] && [ -d "$project/docs" ] || return 1
  local docs path
  docs=$(cd "$project/docs" && pwd -P)
  path=$(resolve "$1")
  case "$path" in
    "$docs") echo . ;;
    "$docs"/*) echo "${path#"$docs"/}" ;;
    *) return 1 ;;
  esac
}

# --- the history check -------------------------------------------------------------------

# Reads the hook input on stdin, with the file's current text as $current. Prints the
# problem, or nothing when every change only flips checkboxes or re-points links. A box
# may go either way, `[ ]` to `[x]` or back, at any nesting depth, but its text may not.
history_problem() {
  local current=$1
  jq -r --arg current "$current" '
    # [[target|shown]] -> [[shown]], so re-pointing a link while keeping its text is no change.
    def links: gsub("\\[\\[[^\\]|]+\\|(?<s>[^\\]]+)\\]\\]"; "[[\(.s)]]");
    def unboxed: gsub("(?<b>[-*+]) \\[[ xX]\\]"; "\(.b) [ ]");
    def allowed($old; $new): ($old | links | unboxed) == ($new | links | unboxed);

    if .tool_name == "Write" then
      if allowed($current; .tool_input.content // "") then empty
      else "This rewrite changes more than checkboxes and links." end
    else
      (if .tool_name == "MultiEdit" then .tool_input.edits else [.tool_input] end)
      | if all(.[]; allowed(.old_string // ""; .new_string // "")) then empty
        else "This edit changes more than checkboxes and links." end
    end
  ' <<<"$input"
}

# Reads the hook input on stdin, with the file's current text as $current. Prints the
# problem when the change adds a bare section reference such as `§4.2`, outside a link or
# code. References already in the file don't count, so an old line can still be edited.
bare_section_problem() {
  local current=$1
  jq -r --arg current "$current" '
    def bare: gsub("(?s)```.*?```"; "") | gsub("`[^`\n]*`"; "")
      | gsub("\\[\\[[^\\]]*\\]\\]"; "") | gsub("\\[[^\\]]*\\]\\([^)]*\\)"; "")
      | [match("§ ?[0-9]"; "g")] | length;

    (if .tool_name == "Write" then [{old_string: $current, new_string: .tool_input.content}]
     elif .tool_name == "MultiEdit" then .tool_input.edits
     else [.tool_input] end)
    | if any(.[]; (.new_string // "" | bare) > (.old_string // "" | bare))
      then "This change adds a bare section reference such as §4.2." else empty end
  ' <<<"$input"
}

# Sets $current to the file's text, trailing newlines included, or to nothing when it
# doesn't exist.
load_current() {
  current=""
  [ -f "$project/docs/$1" ] || return 0
  current=$(cat "$project/docs/$1"; printf x)
  current=${current%x}
}

# --- dispatch ----------------------------------------------------------------------------

case "$event" in
  PostToolUse) mark "$(skill_from "$skill_called")"; exit 0 ;;
  UserPromptExpansion) mark "$(skill_from "$command_name")"; exit 0 ;;
  PreToolUse) ;;
  *) exit 0 ;;
esac

rel=$(vault_relative "$target") || exit 0

# Obsidian's own settings aren't notes, so neither the skills' rules nor their reminders apply.
case "$rel" in .obsidian | .obsidian/*) exit 0 ;; esac

case "$tool" in
  Read | Grep | Glob)
    loaded recall || remind "This is the project's docs vault. Load /docs-vault:recall before relying on what it says, if it isn't loaded already."
    exit 0
    ;;
  Edit | Write | MultiEdit) ;;
  *) exit 0 ;;
esac

loaded record || loaded init ||
  deny "Writes to docs/ go through the record skill. Load /docs-vault:record, then retry this change."

today=$(date +%F)

# Everywhere in the vault: a section reference is a heading link, never a bare `§N`.
load_current "$rel"
problem=$(bare_section_problem "$current")
[ -z "$problem" ] ||
  deny "$problem Obsidian can link to the section itself, so write it as a heading link that keeps the number as its text, for example [[Spec#4.2 Assertion|Spec §4.2]], or [[#4.2 Assertion|§4.2]] within the same note, and escape the | as \\| inside a table. Link a section in an outside document with a Markdown link to its URL."

# Journal/YYYY-MM-DD.md: today's day is a memo that converges during the day. A past day
# is history: only its checkbox state and link targets may change. A future day isn't
# history yet, and planning belongs in the project's own notes.
day=$(printf '%s\n' "$rel" | sed -n 's#^Journal/\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)\.md$#\1#p')
if [ -n "$day" ] && [[ "$day" > "$today" ]]; then
  deny "Journal/$day.md is in the future. The journal records what happened, so write in today's day file, Journal/$today.md, and put plans in the project's notes."
fi
if [ -n "$day" ] && [[ "$day" < "$today" ]]; then
  [ -f "$project/docs/$rel" ] ||
    deny "Journal/$day.md is a past day, and new history goes in today's day file, Journal/$today.md."
  load_current "$rel"
  problem=$(history_problem "$current")
  [ -z "$problem" ] ||
    deny "Journal/$day.md is a past day. $problem A past day's prose is history: the only edits it gets are ticking or unticking a box (without touching its text) or re-pointing a broken [[link]] while keeping its displayed text. Write anything new in today's day file, Journal/$today.md."
fi

# Decisions/YYYY-MM-DD-NN-short-slug.md: a new decision is dated today, and stays editable
# for the day. After that it is historical rationale, and a changed mind is a new decision.
case "$rel" in
  Decisions/*.md)
    dated=$(printf '%s\n' "$rel" | sed -n 's#^Decisions/\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)-[0-9][0-9]-[^/]\{1,\}\.md$#\1#p')
    [ "$dated" = "$today" ] && exit 0
    [ -f "$project/docs/$rel" ] ||
      deny "New decisions are named Decisions/$today-NN-short-slug.md: today's date, then 01, 02 and so on in the order they're made today, then a short slug."
    load_current "$rel"
    problem=$(history_problem "$current")
    [ -z "$problem" ] ||
      deny "$rel is a recorded decision. $problem Decisions keep the rationale as it was when the choice was made. If the project changed direction, create a new decision in Decisions/ that links to this one, and update the notes that describe the current state."
    ;;
esac
exit 0
