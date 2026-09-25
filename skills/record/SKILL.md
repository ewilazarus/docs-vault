---
name: record
description: Write to this project's docs/ Obsidian vault. It adds journal entries with #decision and #todo blocks, ticks off finished todos, and rewrites or creates notes when what is true changes. Use after changing anything outside the repo, after a decision worth keeping, when a note turns out wrong or missing, and when the user says "write it down", "log this", "record that", "add a todo" or "update the docs".
---

# Record to the docs vault

`docs/` is an Obsidian vault. Every path below is relative to it.

**If `/docs-vault:recall` isn't loaded in this session, load it first**
(`/docs-vault-recall` if the skills were copied into `.claude/skills/`). It covers the
project's `Conventions.md`, what notes and the journal each hold, and how to find the note
you're about to change. This skill doesn't repeat any of that.

## What gets recorded

**Record what git can't, in the same session, before the work is called done.** Git records
the diff. The vault records changes made outside the repo, why a call was made, what was
tried and backed out, what is still open, and what is true now. A routine code change with
nothing to explain needs no entry.

Most work produces two writes: a **journal entry** saying what happened, and a **rewrite of
the note** that owns any fact that changed. The journal says how the project got here, and
the note says where "here" is. A fact that seems to belong in both is really two facts, the
current state and the story of how it got there, so split it.

## Writing notes

Everything outside `journal/` describes **what is true now**. Rewrite notes in place when
that changes.

- **Follow the project's conventions.** Put a note where `Conventions.md` says, with the
  name, frontmatter and template it asks for. Where the conventions are silent, match
  the neighbouring notes. If the vault has no pattern either, ask instead of inventing one.
- **No history in a note.** Don't write "used to be", resolved incidents or superseded
  designs. Move the displaced text into today's journal entry. A lesson that is still true
  counts as current knowledge, and it stays.
- **No open work in a note.** A note may state a present fact ("the nightly export fails
  on large inputs"). "Not done yet" goes in a `#todo` block in the journal.
- **Link from the entry to the note** it rewrote, so the story and the state find each
  other.

Don't restructure existing notes to fit a convention unless the user asks.

## Writing a journal entry

There is one file per day, `journal/YYYY-MM-DD.md`, and both the user and the agent write
to it. Several entries can share a day: add a new section, and never rewrite an existing
one.

```markdown
---
description: "The day in one line."
---

## Short title, past tense

What changed, and what you observed while doing it. Plain prose, no field labels.

### #decision Name the call

The call, and *because*. The reason is the part that nothing else records.

### #todo Name the job in the imperative

- [ ] What is still open, with the evidence that makes it checkable and the concrete next
      action, or exactly what it is waiting on.
```

- **Only the `##` title and the prose are required.** The `###` blocks are optional and
  repeatable, so an entry may have none, or three decisions and two todos.
- **Each tag starts a `###` block title.** Tags never go in frontmatter or mid-sentence. A
  `#decision` *replaces* a field label, never sits next to one. A `#todo` title is written
  in the imperative, like a task.
- **The `description:` is the day's headline.** Don't repeat the date in it, because the
  filename already has it. Update it when a later entry changes what the day was about.
  That is the only frontmatter edit a day file gets.
- **Don't add a byline.** `git log` records who wrote an entry.

> [!danger] Never edit a past entry, except to tick a box
> This includes your own entries from earlier in the same session. A later entry corrects
> an earlier one and says which one. That keeps the log usable as evidence when a problem
> turns out to date from one specific change. If a link in an old entry breaks, **pipe** it
> to the new target instead of rewriting it.
>
> **The one permitted edit is `- [ ]` → `- [x]` in a `#todo` block.** Change the box and
> nothing else, because the words around it record what was true that day.

## Closing a todo

Closing a todo takes three edits. Tick the box in the entry that raised it, write what
happened in today's entry, and rewrite any note whose facts changed.

## If the vault isn't set up

If `journal/` doesn't exist, create it with the first entry. If `Conventions.md` doesn't
exist, mention `/docs-vault:init` (or `/docs-vault-init`) once and carry on. Don't bootstrap the vault yourself.
