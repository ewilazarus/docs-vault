---
name: todos
description: List every open todo in this project's docs/ journal as a table, with the day it was raised, its #todo block, its text and its sub-items, and recommend the easiest one to do next. Use when the user runs /docs-vault:todos or asks what's open, what's left, what to pick up next, or for the TODO list or backlog.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/todos.sh), Read, Grep, Glob, Bash(rg *), Bash(fd *)
---

# Open todos

A script has already collected the open todos from `docs/Journal/`. Every unticked
top-level `- [ ]` box is one row, oldest first. Here is its output:

!`${CLAUDE_SKILL_DIR}/scripts/todos.sh`

## 1. Show the list

**Print the script's output above exactly as it is:** the table and the summary line under
it. Don't reorder, merge, reword, shorten or drop rows, and don't add any from memory. The
list is deterministic so that it can be trusted. If the output says there is no journal, or
nothing is open, say so and stop.

## 2. Recommend the next low-hanging fruit

After the table, recommend **one** item, by its `#`, as the best one to pick up next. You
may name a runner-up. Judge from the row itself, and if you need more, read the day file it
came from or the note it links. Don't run anything that changes the system.

Prefer an item that is:

- **Unblocked.** Drop anything "waiting on" a person, an upstream change or another todo.
- **Concrete.** It has a clear next action or a checkable outcome.
- **Small.** It needs few steps, or has only one or two unticked sub-items left.
- **Low-risk.** It doesn't take a running system down or need a sign-off.
- **Old.** Among close calls, pick the one that has been open longest.

Give the recommendation in two or three sentences: which item, why it's the easy one, and
its first concrete step. If nothing qualifies, because everything is blocked or large, say
which item is closest and what it is waiting on.

## 3. Stop

Don't start the work or tick any box. Wait for the user to pick. Closing a todo is the
`record` skill's job: tick the box in its day file, write what happened in today's entry,
and rewrite any note whose facts changed.
