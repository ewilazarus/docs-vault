#!/usr/bin/env bash
# Check a message between the main agent and the vault-keeper against their contract.
#
#   contract.sh check request < message    a request, from the main agent to the keeper
#   contract.sh check reply   < message    a reply, from the keeper
#
# Both are one JSON object, alone or in a ```json fence. Prints `ok`, or one line per
# problem, and exits 1 on problems. The hooks run it on every request and reply, so neither
# side can drift from the contract. Unknown fields are problems too, so a misspelt field
# fails instead of being dropped.
#
# Requests:
#   {"kind": "ask", "question": "…", "why": "…"}                    why is optional
#   {"kind": "record",                                              every list optional,
#    "changed":  ["…"],                                             at least one not empty
#    "decided":  [{"what": "…", "why": "…", "rejected": "…"}],      rejected is optional
#    "dropped":  [{"what": "…", "why": "…"}],
#    "open":     [{"todo": "…", "done_when": "…"}],
#    "finished": ["…"], "reopened": ["…"],
#    "wrong":    [{"note": "…", "issue": "…"}],
#    "commits":  "…"}                                               optional
#   {"kind": "answers", "answers": ["…"]}                           to a keeper that asked
#
# Replies, whose status names follow the A2A task states:
#   {"status": "completed",      "answer": "…", "sources": ["…"], "disagreements": ["…"],
#                                "written": [{"path": "…", "change": "…"}], "reason": "…"}
#   {"status": "input-required", "questions": [{"q": "…", "options": ["…"]}], "written": […]}
#   {"status": "failed",         "reason": "…"}
# A completed reply has at least one of answer, written or reason. Needs jq.

set -euo pipefail

command -v jq >/dev/null || { echo "contract.sh needs jq" >&2; exit 2; }
usage() { sed -n '4,5p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[ "${1:-}" = check ] && [ $# -eq 2 ] || usage
case "$2" in request | reply) ;; *) usage ;; esac

# The message, without surrounding blank lines or a ```json fence around the whole of it.
message=$(cat)
message=$(printf '%s\n' "$message" | awk '
  { lines[NR] = $0 }
  END {
    first = 1; while (first <= NR && lines[first] ~ /^[ \t]*$/) first++
    last = NR; while (last >= first && lines[last] ~ /^[ \t]*$/) last--
    if (lines[first] ~ /^[ \t]*```(json)?[ \t]*$/ && lines[last] ~ /^[ \t]*```[ \t]*$/ && last > first) { first++; last-- }
    for (i = first; i <= last; i++) print lines[i]
  }')

if ! printf '%s' "$message" | jq -se 'length == 1 and (.[0] | type) == "object"' >/dev/null 2>&1; then
  echo "The message isn't one JSON object: send only the object, alone or in a \`\`\`json fence."
  exit 1
fi

problems=$(printf '%s' "$message" | jq -r --arg side "$2" '
  def text: type == "string" and (gsub("\\s"; "") | length) > 0;
  def texts: type == "array" and all(.[]; text);
  def only($allowed; $where): keys - $allowed | map("\($where)has an unknown field \"\(.)\".")[];
  def need($k; $where): if (.[$k] | text) then empty else "\($where)needs \"\($k)\", as text." end;
  def maybe($k; $where): if has($k) and (.[$k] | text | not) then "\($where)\"\($k)\" must be text." else empty end;
  def list($k): if has($k) and (.[$k] | texts | not) then "\"\($k)\" must be a list of text." else empty end;
  def items($k; $required; $optional):
    if has($k) | not then empty
    elif (.[$k] | type) != "array" then "\"\($k)\" must be a list."
    else .[$k] | to_entries[] | .key as $i | .value
      | if type != "object" then "\"\($k)\"[\($i)] must be an object."
        else (only($required + $optional; "\"\($k)\"[\($i)] ")),
             ($required[] as $r | need($r; "\"\($k)\"[\($i)] ")),
             ($optional[] as $o | maybe($o; "\"\($k)\"[\($i)] "))
        end
    end;

  if $side == "request" then
    if .kind == "ask" then only(["kind", "question", "why"]; "An ask "), need("question"; "An ask "), maybe("why"; "An ask ")
    elif .kind == "answers" then only(["kind", "answers"]; "An answers request "),
      (if (.answers | texts) and (.answers | length) > 0 then empty else "\"answers\" must be a non-empty list of text." end)
    elif .kind == "record" then
      only(["kind", "changed", "decided", "dropped", "open", "finished", "reopened", "wrong", "commits"]; "A record "),
      list("changed"), list("finished"), list("reopened"),
      items("decided"; ["what", "why"]; ["rejected"]),
      items("dropped"; ["what", "why"]; []),
      items("open"; ["todo", "done_when"]; []),
      items("wrong"; ["note", "issue"]; []),
      maybe("commits"; "A record "),
      (if [.changed, .decided, .dropped, .open, .finished, .reopened, .wrong] | map(select(type == "array" and length > 0)) | length > 0
       then empty else "A record needs at least one non-empty list: changed, decided, dropped, open, finished, reopened or wrong." end)
    else "\"kind\" must be \"ask\", \"record\" or \"answers\"." end
  else
    only(["status", "answer", "sources", "disagreements", "written", "questions", "reason"]; "The reply "),
    list("sources"), list("disagreements"),
    items("written"; ["path", "change"]; []),
    maybe("answer"; "The reply "), maybe("reason"; "The reply "),
    (if has("questions") and (.questions | type) == "array" then
       .questions | to_entries[] | .key as $i | .value
       | if type != "object" then "\"questions\"[\($i)] must be an object."
         else only(["q", "options"]; "\"questions\"[\($i)] "), need("q"; "\"questions\"[\($i)] "),
              (if has("options") and (.options | texts | not) then "\"questions\"[\($i)] \"options\" must be a list of text." else empty end)
         end
     elif has("questions") then "\"questions\" must be a list." else empty end),
    (if .status == "completed" then
       if (.answer | text) or ((.written | type) == "array" and (.written | length) > 0) or (.reason | text) then empty
       else "A completed reply needs an answer, what was written, or a reason there was nothing to write." end
     elif .status == "input-required" then
       if (.questions | type) == "array" and (.questions | length) > 0 then empty
       else "An input-required reply needs its questions." end
     elif .status == "failed" then need("reason"; "A failed reply ")
     else "\"status\" must be \"completed\", \"input-required\" or \"failed\"." end)
  end')

if [ -n "$problems" ]; then
  printf '%s\n' "$problems"
  exit 1
fi
echo ok
