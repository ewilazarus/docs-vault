---
name: recall
description: Look things up in this project's docs/ folder, an Obsidian vault of notes on what is true now and a dated journal of what was done, decided and left open. Use before any work the vault documents, and whenever the user asks how something works here, what was decided, why something is the way it is, or what is still open, or mentions "the docs", "the vault" or "the journal". Read-only; hands over to the record skill once there is something to write down.
allowed-tools: Read, Grep, Glob, Bash(rg *), Bash(fd *), Bash(obsidian vault), Bash(obsidian read *), Bash(obsidian search *), Bash(obsidian search:context *), Bash(obsidian file *), Bash(obsidian tasks *), Bash(obsidian backlinks *)
---

# Recall from the docs vault

`docs/` is an Obsidian vault. Every path below is relative to it. This skill **only reads**.
Writing belongs to the `record` skill, and the handoff at the end says when to load it.

This skill needs kepano's `obsidian-markdown`, `obsidian-bases` and `obsidian-cli` skills.
They own the syntax and the tooling, so use them instead of guessing.

## First, read the project's conventions

Read `Conventions.md` at the vault root if it exists. That is where the project defines how
the vault is laid out, what its notes carry and which rules bind work here. It takes
precedence over your defaults. Where it says nothing, look at how the vault is actually
organised before assuming anything.

## Notes are the present, the journal is history

- **`journal/`** holds **what was done, decided and left open**, one file per day
  (`journal/YYYY-MM-DD.md`). It is append-only and never the authority on the present.
- **Every other note** holds **what is true now**, however the project organises it.

So answer "how does X work" or "what is X" from the notes, and "why is X like this" or
"what happened to X" from the journal. If you have to read the journal to find out whether
something is *currently* true, you have found a gap. A note should hold that fact, and
filling the gap is a job for `record`.

**Read the note before acting on the thing it describes.** The note is the authority, not
the system. When the two disagree, don't assume the system is broken. The disagreement is
the finding, and the note gets rewritten.

## Reading the journal

The journal uses two tags, each at the start of a `###` block title inside an entry:

- **`### #decision`** marks a call that was made, with its reason. **Don't undo a recorded
  decision unless asked.** If something is disabled, pinned or deliberately missing and a
  decision explains why, someone made that call on purpose.
- **`### #todo`** marks a block of open work. **The unticked boxes across `journal/` are
  the project's TODO list.** An unticked box is the one part of the journal that *is*
  current, because nothing has ticked it yet. For the whole
  list as a table, with a suggestion of what to do next, use `/docs-vault:todos`.

Each day file's `description:` is that day's headline, so a sweep of descriptions is a
quick index of the project's history.

## Querying

**Use obsidian-cli, and check which vault it's pointed at.** Every project's vault is
named `docs`, so `vault=docs` is ambiguous, and by default the CLI targets whichever vault
was focused last. Before the first query in a session, run `obsidian vault` and check that
the path it reports is this project's `docs/`. If it isn't, or the command fails, use `rg`
and `fd`.

```bash
obsidian tasks todo                             # open work
obsidian search:context query="tag:#decision"   # every decision
obsidian search:context query="connection pool" # full text, with matches
obsidian read file="2026-09-25"                 # one day
obsidian backlinks file="Connection pool"       # what refers to a note
```

```bash
rg '^- \[ \]' docs/journal/              # open work
rg -A3 '^### #decision' docs/journal/    # every decision, with its reason
rg '^description:' docs/journal/         # one headline per day
rg -il 'connection pool' docs/           # full text
fd -F "Connection pool.md" docs/         # where a [[link]] actually lives
```

Note names often contain spaces, so quote them.

## Hand over to `record`

**Load `/docs-vault:record` before calling the work done** (`/docs-vault-record` if the
skills were copied into `.claude/skills/`) as soon as any of these is
true:

- you changed something outside the repo, such as a deployed system, a service, a setting
  or data
- you or the user made a call worth keeping, including a decision *not* to do something
- something was tried and backed out, or found and left open
- a note turned out to be wrong, missing or out of date

If none of these is true, there is nothing to write, so don't load it.
