---
name: docs-vault
description: Read and maintain this project's docs/ folder, an Obsidian vault with a dated journal of what was done, decided and left open. Use whenever work touches docs/, after any change or decision worth recording, and when the user says "the docs", "the vault", "the journal", "write it down", "log this", "add a todo", or asks what was decided or what is still open.
---

# Docs vault

`docs/` is an Obsidian vault. Every path below is relative to it. This skill fixes two
things: **the journal** and **its two tags**. Everything else is up to the project: folders,
note kinds, templates, bases, frontmatter and any other tags.

This skill needs kepano's `obsidian-markdown`, `obsidian-bases` and `obsidian-cli` skills.
They own the syntax and the tooling, so use them instead of guessing.

## First, read the project's conventions

Read `Conventions.md` at the vault root if it exists. That is where the project defines how
the rest of the vault works, and it takes precedence over your defaults. Where it says
nothing, follow the patterns already in the vault. Look at how neighbouring notes are named,
where they live and what frontmatter they carry, and match them. If the vault has no
pattern either, ask instead of inventing one.

The project's conventions can add to the journal and the tags below, but can't loosen
them.

## The journal is history, notes are the present

- **`journal/`** holds **what was done, decided and left open**, one file per day. It is
  append-only and never the authority on the present.
- **Every other note** holds **what is true now**, however the project organises it. When
  an entry settles a lasting fact, also rewrite the note that owns it and link to that note
  from the entry. The journal says how the project got here, and the note says where "here"
  is.

If you are reading the journal to find out whether something is *currently* true, that
fact belongs in a note that doesn't have it yet.

**Record what git can't, in the same session, before the work is called done.** Git
records the diff. The journal records changes made outside the repo, why a call was made,
and what is still open. A routine code change with nothing to explain needs no entry.

## Writing an entry

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

## The two tags

These tags are for the journal only. Each one **starts** a `###` block title, never a
frontmatter field.

| Tag | Where it goes |
|---|---|
| `#decision` | on each call that was made, with its reason. It *replaces* a field label, never sits next to one |
| `#todo` | on each block of open work, **titled in the imperative** |

**Open work lives in the journal, not in notes.** A note may state a present fact ("the
nightly export fails on large inputs"). "Not done yet" goes in a `#todo` block in the entry
that raised it, so the task sits next to the reasoning that produced it.

**The unticked boxes across `journal/` are the TODO list.** An unticked box is the one part
of the journal that *is* current, because nothing has ticked it yet.

**Closing a todo takes three edits.** Tick the box in the entry that raised it, write
what happened in today's entry, and rewrite any note whose facts changed.

**Don't undo a recorded `#decision` unless asked.** If something is disabled, pinned or
deliberately missing and a decision explains why, someone made that call on purpose.

## Querying

**Use obsidian-cli from inside `docs/`.** Every project's vault is named `docs`, so
`vault=docs` is ambiguous, and by default the CLI targets whichever vault was focused last.
Before the first query in a session, run `obsidian vault` and check that the path it reports
is this project's `docs/`. If it isn't, or the command fails, use `rg`.

```bash
cd docs
obsidian tasks todo                             # open work
obsidian search:context query="tag:#decision"   # every decision
obsidian search:context query="connection pool" # full text, with matches
obsidian read file="2026-09-25"                 # one day
```

```bash
cd docs
rg '^- \[ \]' journal/                 # open work
rg -A3 '^### #decision' journal/       # every decision, with its reason
rg '^description:' journal/            # one headline per day
rg -il 'connection pool'               # full text
```

## If the vault isn't set up

If `docs/journal/` doesn't exist, create it the first time there is something to record.
If `docs/Conventions.md` doesn't exist, mention `/docs-vault:init` once (`/docs-vault-init` if the skills were copied
into `.claude/skills/`) and carry on. Don't
bootstrap the vault yourself, and don't restructure existing notes to fit any convention
unless the user asks.
