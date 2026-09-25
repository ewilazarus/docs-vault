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
#   - editing a past journal day is denied unless the only changes tick `- [ ]` boxes or
#     re-point a wikilink while keeping its displayed text.
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

# --- the past-entry check ----------------------------------------------------------------

# Reads the hook input on stdin, with the day file's current text as $current. Prints the
# problem, or nothing when every change only ticks boxes or re-points links.
past_entry_problem() {
  local current=$1
  jq -r --arg current "$current" '
    # [[target|shown]] -> [[shown]], so re-pointing a link while keeping its text is no change.
    def links: gsub("\\[\\[[^\\]|]+\\|(?<s>[^\\]]+)\\]\\]"; "[[\(.s)]]");
    def unboxed: gsub("- \\[[ xX]\\]"; "- [ ]");
    def boxes: [scan("- \\[([ xX])\\]") | .[0]];
    def allowed($old; $new):
      ($old | links) as $o | ($new | links) as $n
      | ($o | unboxed) == ($n | unboxed)
        and ([($o | boxes), ($n | boxes)] | transpose | all(.[0] == " " or .[1] != " "));

    if .tool_name == "Write" then
      if $current == "" then "New entries go in today'"'"'s file, not a past day'"'"'s."
      elif allowed($current; .tool_input.content // "") then empty
      else "This rewrite changes more than boxes and links." end
    else
      (if .tool_name == "MultiEdit" then .tool_input.edits else [.tool_input] end)
      | if all(.[]; allowed(.old_string // ""; .new_string // "")) then empty
        else "This edit changes more than boxes and links." end
    end
  ' <<<"$input"
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

day=$(printf '%s\n' "$rel" | sed -n 's#^journal/\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)\.md$#\1#p')
if [ -n "$day" ] && [[ "$day" < "$(date +%F)" ]]; then
  current=""
  [ -f "$project/docs/$rel" ] && current=$(cat "$project/docs/$rel"; printf x) && current=${current%x}
  problem=$(past_entry_problem "$current")
  [ -z "$problem" ] ||
    deny "journal/$day.md is a past day. $problem The only edits a past entry gets are ticking a \`- [ ]\` box or re-pointing a broken [[link]] while keeping its displayed text. Write anything else in today's entry, and say which earlier entry it corrects."
fi
exit 0
