#!/usr/bin/env bash
# Keep the docs/ vault behind the vault-keeper agent, and keep its history as written.
#
# One script, for these hook events:
#
# - SubagentStart gives the keeper its rules: keeper/recall.md and keeper/record.md.
# - PreToolUse on Agent and SendMessage checks every request to the keeper against the
#   contract in scripts/contract.sh, and refuses one that doesn't fit, saying what to fix.
# - SubagentStop checks the keeper's reply the same way, and sends it back once to fix it.
# - PreToolUse on file tools:
#   - docs/.obsidian/ holds Obsidian's settings, not notes, so it is left alone;
#   - anyone but the keeper is refused docs/, for reads and writes, and sent to the keeper;
#   - a write that adds a bare section reference (`§4.2`) outside a link or code is denied;
#   - today's journal day, and decisions whose `date:` is today, may be rewritten freely;
#   - a past journal day, or a decision dated before today, may only change the state of
#     its checkboxes or re-point a wikilink while keeping its displayed text;
#   - a new journal day must be dated today, and a future journal day can't be written at
#     all;
#   - a new decision takes the next number, `Decisions/NNNNN-slug.md`, with `date:` today.
# - PostToolUse on file writes runs the lint script on the note just written, and hands its
#   errors back to fix while the note is still in hand. Warnings are left to
#   /docs-vault:lint, since a note mid-way through a record may not be finished yet.
# - PostToolUse on Bash does the same after a git merge, pull, rebase or cherry-pick, for
#   the notes it changed, since that is where two branches' decisions and links first meet.
# - Stop reminds Claude, once, to send the keeper a record request when the session used
#   the keeper, then changed project files outside docs/, and hasn't sent one since. It
#   never fires while a stop hook is already active, and DOCS_VAULT_STOP_REMINDER=off turns
#   it off.
#
# A new decision's number comes from scripts/next-decision.sh, which also counts the
# decisions on other branches.
#
# The history check enforces the shape of a change (only checkbox state and link targets
# move), not its meaning: it doesn't know whether a box sits under `## Follow-ups`. The
# todos script applies those semantics. The hook only sees Claude's tools, so shell
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
  agent_type=\(.agent_type // "")
  subagent=\(.tool_input.subagent_type // "")
  cwd=\(.cwd // "")
  tool=\(.tool_name // "")
  target=\(.tool_input.file_path // .tool_input.path // "")
  shell_command=\(.tool_input.command // "")
  stop_active=\(.stop_hook_active // false)
"' <<<"$input")
eval "$fields"

project=${CLAUDE_PROJECT_DIR:-${cwd:-$PWD}}
[ -n "$cwd" ] || cwd=$project
state_dir="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/docs-vault}/sessions"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- the keeper --------------------------------------------------------------------------

# The plugin's agent, or a project-level copy of it.
is_keeper() { case "$1" in docs-vault:vault-keeper | vault-keeper) return 0 ;; esac; return 1; }
by_keeper() { [ "$agent" != main ] && is_keeper "$agent_type"; }

# Session markers, shared by the session and its subagents: the keeper was used, and project
# files changed outside docs/ since the last record request.
session_key=$(printf '%s' "$session" | tr -c 'A-Za-z0-9_.-' '_')
used_marker="$state_dir/$session_key.used"
changed_marker="$state_dir/$session_key.changed"
touch_marker() {
  mkdir -p "$state_dir"
  touch "$1"
  find "$state_dir" -type f -mtime +7 -delete 2>/dev/null || true
}

# The project keeps a docs-vault vault.
has_vault() { [ -f "$project/docs/Conventions.md" ] || [ -d "$project/docs/Journal" ]; }

to_keeper="Send the docs-vault:vault-keeper agent a request instead: load the docs-vault:keeper-contract skill for the format."

# --- responses ---------------------------------------------------------------------------

deny() {
  jq -n --arg reason "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

remind() {
  jq -n --arg event "$event" --arg context "$1" \
    '{hookSpecificOutput: {hookEventName: $event, additionalContext: $context}}'
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

# --- after a write -----------------------------------------------------------------------

# Lints the note just written, and hands any errors back to Claude.
lint_written() {
  case "$rel" in *.md) ;; *) exit 0 ;; esac
  local lint out errors
  lint="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lint.sh"
  [ -f "$lint" ] || exit 0
  out=$(bash "$lint" "$project/docs" --only "$rel")
  errors=$(printf '%s\n' "$out" | grep '^| [0-9]* | error |' || true)
  [ -n "$errors" ] || exit 0
  remind "The lint script found errors in $rel after this write. Fix them now, in the same way as the rest of this change:

| # | Severity | Where | Problem |
|---|---|---|---|
$errors"
}

# After a git merge, pull, rebase or cherry-pick, lints the notes it changed in docs/ and
# hands any errors back. Two branches that each took the next decision number, or a note
# renamed on one side and linked on the other, only meet here.
lint_merged() {
  printf '%s\n' "$shell_command" |
    grep -Eq '(^|[;&|(]|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(merge|pull|rebase|cherry-pick)([[:space:]]|$)' ||
    exit 0
  [ -d "$project/docs" ] || exit 0
  git -C "$project/docs" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
  local before after lint file out errors
  before=$(git -C "$project/docs" rev-parse -q --verify ORIG_HEAD 2>/dev/null) || exit 0
  after=$(git -C "$project/docs" rev-parse -q --verify HEAD 2>/dev/null) || exit 0
  [ "$before" != "$after" ] || exit 0
  lint="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lint.sh"
  [ -f "$lint" ] || exit 0
  set -- "$project/docs"
  while IFS= read -r file; do
    case "$file" in .obsidian/*) ;; *.md) set -- "$@" --only "$file" ;; esac
  done < <(git -C "$project/docs" diff --relative --name-only --diff-filter=AMR "$before" "$after" -- . 2>/dev/null)
  [ $# -gt 1 ] || exit 0
  out=$(bash "$lint" "$@")
  errors=$(printf '%s\n' "$out" | grep '^| [0-9]* | error |' || true)
  [ -n "$errors" ] || exit 0
  remind "That git command changed notes in docs/, and the lint script found errors in them:

| # | Severity | Where | Problem |
|---|---|---|---|
$errors

Tell the user. A decision number shared by two notes means two branches each took the next one: offer to have the vault-keeper renumber the newer decision and update the links to it, but ask first, since other branches may link to it. The keeper can also fix broken links by piping them to the note's new name."
}

# --- the contract ------------------------------------------------------------------------

# A keeper started by an Agent call speaks the contract; one started by a slash command
# replies to the user in Markdown. PreToolUse on the Agent call leaves a pending mark, and
# SubagentStart turns it into a mark on that keeper's agent_id.
pending_marker="$state_dir/$session_key.pending"
contract_marker() { printf '%s/%s.contract' "$state_dir" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_')"; }

# SubagentStart: gives the keeper its rules, with the plugin's path filled in.
give_rules() {
  touch_marker "$used_marker"
  local rules mode
  if [ -s "$pending_marker" ]; then
    # One line per request sent: this keeper takes one of them.
    sed '1d' "$pending_marker" >"$pending_marker.tmp" && mv "$pending_marker.tmp" "$pending_marker"
    touch_marker "$(contract_marker "$agent")"
    mode="This task came from the main agent, so it is a JSON request, and your final message is a JSON reply."
  else
    mode="This task is the user's slash command, so your final message is for the user to read: plain Markdown, not JSON. If you need the user's answers, end with the numbered questions, and say they can answer in the conversation for Claude to pass on."
  fi
  rules=$(printf '# The recall rules\n\n'; cat "$root/keeper/recall.md"; printf '\n\n# The record rules\n\n'; cat "$root/keeper/record.md")
  rules=${rules//'${CLAUDE_PLUGIN_ROOT}'/$root}
  remind "$mode

$rules"
}

# PreToolUse on Agent or SendMessage: checks a request to the keeper. A SendMessage is only
# checked when it is JSON, since its recipient could be any agent.
check_request() {
  local message problems
  if [ "$tool" = Agent ]; then
    is_keeper "$subagent" || exit 0
    message=$(jq -r '.tool_input.prompt // ""' <<<"$input")
  else
    message=$(jq -r '.tool_input.message // .tool_input.content // "" | if type == "string" then . else tojson end' <<<"$input")
    printf '%s' "$message" | grep -Eq '^[[:space:]]*(\{|```)' || exit 0
    printf '%s' "$message" | grep -q '"kind"' || exit 0
  fi
  touch_marker "$used_marker"
  if ! problems=$(printf '%s' "$message" | bash "$root/scripts/contract.sh" check request); then
    deny "This request to the vault-keeper doesn't fit its contract: $(printf '%s\n' "$problems" | tr '\n' ' ')Load the docs-vault:keeper-contract skill for the format, and send it again."
  fi
  if [ "$tool" = Agent ]; then mkdir -p "$state_dir"; echo pending >>"$pending_marker"; fi
  # A record request covers the changes made so far, so the stop reminder waits for new ones.
  [ "$(printf '%s' "$message" | sed -e '1{/^[[:space:]]*```/d;}' -e '${/^[[:space:]]*```[[:space:]]*$/d;}' | jq -r '.kind' 2>/dev/null)" != record ] ||
    rm -f "$changed_marker"
  exit 0
}

# SubagentStop: checks the keeper's reply, and sends it back once if it doesn't fit.
check_reply() {
  is_keeper "$agent_type" || exit 0
  [ -e "$(contract_marker "$agent")" ] || exit 0
  [ "$stop_active" != true ] || exit 0
  local problems
  if ! problems=$(jq -r '.last_assistant_message // ""' <<<"$input" | bash "$root/scripts/contract.sh" check reply); then
    jq -n --arg reason "Your reply doesn't fit your contract: $(printf '%s\n' "$problems" | tr '\n' ' ')Reply again with one JSON object, as your instructions describe, and nothing else." \
      '{decision: "block", reason: $reason}'
  fi
  exit 0
}

# PreToolUse on Bash, for the keeper only: approves the commands its rules tell it to run,
# since a plugin agent can't carry permission rules of its own. That is exactly the plugin's
# own scripts, read-only git commands and `date`, each alone: anything with a shell operator,
# a substitution or a redirection goes through the usual permission check.
approve_keeper_command() {
  by_keeper || exit 0
  local command rest
  command=$(printf '%s' "$shell_command" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  case "$command" in *[';&|`$<>(){}']* | *"
"*) exit 0 ;; esac
  command=${command#bash }
  command=${command//\"/}
  command=${command//\'/}
  case "$command" in
    "$root"/scripts/*)
      rest=${command#"$root"/scripts/}
      printf '%s\n' "$rest" | grep -Eq '^[a-z-]+\.sh( |$)' || exit 0
      ;;
    git\ *)
      printf '%s\n' "$command" | grep -Eq '^git( -C [^ ]+)? (status|diff|log|show|ls-files|ls-tree|rev-parse)( |$)' || exit 0
      case " $command" in *" --output"*) exit 0 ;; esac
      ;;
    date | "date +%F") ;;
    *) exit 0 ;;
  esac
  jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: "A command the vault-keeper'"'"'s rules call for: a docs-vault script, a read-only git command, or date."}}'
  exit 0
}

# --- the stop reminder -------------------------------------------------------------------

# Notes that Claude changed a project file outside docs/.
note_change() {
  local path root
  has_vault || return 0
  [ -n "$target" ] || return 0
  ! by_keeper || return 0
  path=$(resolve "$target")
  # A file in a folder that doesn't exist keeps its path unresolved, so try both spellings.
  for root in "$(cd "$project" && pwd -P)" "$project"; do
    case "$path" in
      "$root"/.git/*) return 0 ;;
      "$root"/*) mkdir -p "$state_dir"; touch "$changed_marker"; return 0 ;;
    esac
  done
  return 0
}

# At Stop: asks Claude, once, to send a record request, if the session changed project
# files after using the keeper and hasn't sent one since.
stop_reminder() {
  [ "${DOCS_VAULT_STOP_REMINDER:-on}" != off ] || exit 0
  [ "$stop_active" != true ] || exit 0
  [ -e "$changed_marker" ] || exit 0
  has_vault || exit 0
  [ -e "$used_marker" ] || exit 0
  rm -f "$changed_marker"
  jq -n --arg reason "Before finishing: this session used the docs vault and then changed project files, and hasn't sent the vault-keeper a record request since. Send one, in the background, if the work changed something outside the repo, made a choice whose reason will matter later, left work unfinished, finished or reopened a follow-up, or showed a note to be wrong; the docs-vault:keeper-contract skill has the format. If none of that is true, routine code work that git explains needs no record: say in one line that there is nothing to record, and stop." \
    '{decision: "block", reason: $reason}'
  exit 0
}

# --- dispatch ----------------------------------------------------------------------------

case "$event" in
  SubagentStart) is_keeper "$agent_type" && give_rules; exit 0 ;;
  SubagentStop) check_reply ;;
  Stop) stop_reminder ;;
  PostToolUse)
    case "$tool" in
      Bash) lint_merged; exit 0 ;;
      Edit | Write | MultiEdit) ;;
      *) exit 0 ;;
    esac
    ;;
  PreToolUse)
    case "$tool" in
      Agent | SendMessage) check_request ;;
      Bash) approve_keeper_command ;;
    esac
    ;;
  *) exit 0 ;;
esac

if ! rel=$(vault_relative "$target"); then
  [ "$event" != PostToolUse ] || note_change
  exit 0
fi

# Obsidian's own settings aren't notes, so neither the vault's rules nor its reminders apply.
case "$rel" in .obsidian | .obsidian/*) exit 0 ;; esac

[ "$event" != PostToolUse ] || lint_written

case "$tool" in
  Read | Grep | Glob | Edit | Write | MultiEdit) ;;
  *) exit 0 ;;
esac

by_keeper || deny "docs/ is kept by the docs-vault:vault-keeper agent, and nobody else reads or writes it. $to_keeper"

case "$tool" in Read | Grep | Glob) exit 0 ;; esac

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

# Decisions/NNNNN-short-slug.md: numbered across the vault, with the day it was made in its
# `date:` frontmatter. A new decision takes the next number and is dated today, and stays
# editable for the day. After that it is historical rationale, and a changed mind is a new
# decision.
case "$rel" in
  Decisions/*.md)
    if [ ! -f "$project/docs/$rel" ]; then
      number=$(printf '%s\n' "$rel" | sed -n 's#^Decisions/\([0-9]\{5\}\)-[a-z0-9][a-z0-9-]*\.md$#\1#p')
      # The record skill's script counts the decisions on every branch too.
      next=$(CLAUDE_PROJECT_DIR=$project bash "$(dirname "${BASH_SOURCE[0]}")/../scripts/next-decision.sh")
      [ -n "$number" ] ||
        deny "New decisions are named Decisions/NNNNN-short-slug.md: the next number, $next, then a short lowercase slug. The record skill's next-decision.sh prints the whole path from the title."
      [ $((10#$number)) -ge $((10#$next)) ] ||
        deny "Decision numbers are never reused or filled in, including numbers taken on other branches. The next one is $next."
      content=$(jq -r '.tool_input.content // ""' <<<"$input")
      printf '%s\n' "$content" | grep -qx "date: $today" ||
        deny "A new decision carries \`date: $today\` in its frontmatter: decisions are recorded on the day they're made."
      exit 0
    fi
    load_current "$rel"
    printf '%s' "$current" | grep -qx "date: $today" && exit 0
    problem=$(history_problem "$current")
    [ -z "$problem" ] ||
      deny "$rel is a recorded decision. $problem Decisions keep the rationale as it was when the choice was made. If the project changed direction, create a new decision in Decisions/ that links to this one, and update the notes that describe the current state."
    ;;
esac
exit 0
