#!/usr/bin/env bash
# Tests for skills/lint/scripts/lint.sh: what it reports, and how it prints.

set -eu
. "$(dirname "$0")/lib.sh"

lint="$repo/skills/lint/scripts/lint.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export DOCS_VAULT_TODAY=2026-09-28

# new_vault <name>: makes an empty vault with a journal and decisions, and prints its docs/ path.
new_vault() { mkdir -p "$tmp/$1/docs/Journal" "$tmp/$1/docs/Decisions" "$tmp/$1/docs/Reference"; printf '%s\n' "$tmp/$1/docs"; }

# note <docs> <path>: writes the note from stdin.
note() { cat >"$1/$2"; }

echo "lint.sh: empty vaults"

check "no vault" "No vault found at \`$tmp/none/docs\`." "$("$BASH" "$lint" "$tmp/none/docs")"

v=$(new_vault empty)
check "empty vault" "No problems found. Checked 0 notes: 0 journal files and 0 decisions." "$("$BASH" "$lint" "$v")"

echo "lint.sh: a clean vault"

v=$(new_vault clean)
: >"$v/Reference/diagram.png"
note "$v" Reference/Spec.md <<'EOF'
# Spec

## 4.2: Assertion

A rule. ^rule
EOF
note "$v" Journal/2026-09-20.md <<'EOF'
---
description: "Set up the spec."
---

## Summary

- Wrote [[Spec#4.2: Assertion|Spec §4.2]], [[Spec#4.2 Assertion\|§4.2]] and [[Spec#^rule]], with ![[diagram.png]].
- Links in code don't count: `[[Also not a link]]`.

```text
[[Not a link]] §9
```

## Decisions

- [[Decisions/00001-use-the-spec|Use the spec]]

## Follow-ups

- [ ] Review [[Reference/Spec|the spec]].
EOF
note "$v" Decisions/00001-use-the-spec.md <<'EOF'
---
description: "Use the spec."
date: 2026-09-20
---

# Use the spec

## Why

See [[#Why|this section]] and [[Journal/2026-09-20]].
EOF
check "resolves paths, names, headings, blocks and embeds, and skips code" \
  "No problems found. Checked 3 notes: 1 journal file and 1 decision." \
  "$("$BASH" "$lint" "$v")"

echo "lint.sh: a broken vault"

v=$(new_vault broken)
note "$v" Reference/Spec.md <<'EOF'
# Spec

## Intro
EOF
note "$v" Journal/2026-08-01.md <<'EOF'
## Set up the spec

Wrote [[Spec]].
EOF
note "$v" Journal/2026-09-21.md <<'EOF'
---
description: "Broke things."
---

## Summary

- See [[Nowhere]], [[Spec#Missing heading]], [[Spec#^nope|block]] and [[Spec]].
- Section §4.2 is bare, but `§4.2` and [[Spec#Intro|§1]] are not.

## Follow-ups

## Decisions

- [[Decisions/00002-second|Second]]
EOF
note "$v" Journal/2026-09-22.md <<'EOF'
## Follow-ups

- [ ] Something.
EOF
note "$v" Journal/2030-01-01.md <<'EOF'
## Summary

- Not yet.
EOF
note "$v" Journal/notes.md <<'EOF'
Scratch.
EOF
note "$v" Decisions/00002-first.md <<'EOF'
---
date: 2026-09-21
---

# First

## Why

Because.
EOF
note "$v" Decisions/00002-second.md <<'EOF'
# Second
EOF
expected=$(cat <<'EOF'
| # | Severity | Where | Problem |
|---|---|---|---|
| 1 | error | `Decisions/00002-first.md` | Decision number 00002 is also used by `Decisions/00002-second.md`. Numbers are never shared. |
| 2 | warning | `Decisions/00002-first.md` | No journal day links this decision. The day it was made lists it under `## Decisions`. |
| 3 | error | `Decisions/00002-second.md` | Decision number 00002 is also used by `Decisions/00002-first.md`. Numbers are never shared. |
| 4 | error | `Decisions/00002-second.md` | No `date: YYYY-MM-DD` in the frontmatter. |
| 5 | warning | `Decisions/00002-second.md` | No `## Why`. A decision says why it was made. |
| 6 | error | `Journal/2026-09-21.md:7` | Broken link `[[Nowhere]]`: no file named `Nowhere`. |
| 7 | error | `Journal/2026-09-21.md:7` | Broken link `[[Spec#Missing heading]]`: no heading `Missing heading` in `Reference/Spec.md`. |
| 8 | error | `Journal/2026-09-21.md:7` | Broken link `[[Spec#^nope]]`: no block `^nope` in `Reference/Spec.md`. |
| 9 | warning | `Journal/2026-09-21.md:8` | Bare section reference. Link the section itself, for example `[[Spec#4.2 Assertion\|Spec §4.2]]`. |
| 10 | warning | `Journal/2026-09-21.md:10` | `## Follow-ups` is empty. Leave a section out when it has nothing in it. |
| 11 | warning | `Journal/2026-09-21.md:12` | `## Decisions` comes after `## Follow-ups`. The order is Summary, Decisions, Follow-ups. |
| 12 | error | `Journal/2026-09-22.md` | No `## Summary`. Every day has one. |
| 13 | warning | `Journal/2026-09-22.md` | No `description:` in the frontmatter. It is the day's headline. |
| 14 | error | `Journal/2030-01-01.md` | Dated in the future. The journal records what happened. |
| 15 | warning | `Journal/2030-01-01.md` | No `description:` in the frontmatter. It is the day's headline. |
| 16 | warning | `Journal/notes.md` | Not a day file. The journal holds only `Journal/YYYY-MM-DD.md`. |

8 errors and 8 warnings in 6 files. Checked 8 notes: 5 journal files (1 in the legacy format, not checked for structure) and 2 decisions.
EOF
)
check "reports every kind of problem, sorted by file and line" "$expected" "$("$BASH" "$lint" "$v")"

check "output is stable across runs" "$("$BASH" "$lint" "$v")" "$("$BASH" "$lint" "$v")"

finish
