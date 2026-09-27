---
name: recall
description: Look things up in this project's docs/ folder, an Obsidian vault of notes on what is true now, a daily journal of what meaningful things happened and what was left open, and decision notes on why important choices were made. Use before any work the vault documents, and whenever the user asks how something works here, what happened, what was decided, why something is the way it is, or what is still open, or mentions "the docs", "the vault", "the journal" or "decisions". Read-only; hands over to the record skill once there is something to write down.
allowed-tools: Read, Grep, Glob, Bash(rg *), Bash(fd *), Bash(obsidian vault), Bash(obsidian read *), Bash(obsidian search *), Bash(obsidian search:context *), Bash(obsidian file *), Bash(obsidian tasks *), Bash(obsidian backlinks *)
---

# Recall from the docs vault

`docs/` is an Obsidian vault. Every path below is relative to it. This skill **only reads**.
Writing belongs to the `record` skill, and the handoff at the end says when to load it.

This skill needs kepano's `obsidian-markdown`, `obsidian-bases` and `obsidian-cli` skills.
They own the syntax and the tooling, so use them instead of guessing.

## First, read the project's conventions

Read `Conventions.md` at the vault root if it exists. docs-vault fixes only `Journal/` and
`Decisions/`. Everything else is up to the project, and `Conventions.md` is where it
defines how the vault is laid out, what its notes carry and which rules bind work here. It
takes precedence over your defaults. Where it says nothing, look at how the vault is actually
organised before assuming anything.

## Which part of the vault answers what

- **Notes**, meaning every file outside `Journal/` and `Decisions/`, however the project
  organises them, hold **what is true now**.
- **`Journal/YYYY-MM-DD.md`** holds **what meaningful things happened** each day, and the
  work left open.
- **`Decisions/NNNNN-slug.md`** holds **why an important choice was made**, one
  choice per note.
- **Git** holds exactly what changed in the repo. What the agent ran or tried is kept
  nowhere, on purpose.

| Question | Where to look |
|---|---|
| What is true now? How is X configured? How does X work? | Notes |
| What happened today, or on a given day? | That day's journal |
| What happened with X over time? | The journal, plus the decisions about X |
| Why did we choose X? What have we decided about X? | `Decisions/` first, then the journal for the chronology |
| What remains open? | The journal's Follow-ups, via `/docs-vault:todos` |
| Why does this follow-up exist? | The Summary above it, in the day that raised it |

**Current-state questions go to the notes.** The journal and decisions are history, and
never the authority on the present: a decision says what was chosen then, not what is
true now. If you have to read history to find out whether something is *currently* true,
you have found a gap. A note should hold that fact, and filling the gap is a job for
`record`.

**A disagreement is a finding.** If a note says X and a newer journal day or decision says
Y, don't silently pick one. Report that the note may be stale, with both sources. The same
goes for the note and the system it describes: read the note before acting on the thing,
and when they disagree, don't assume the system is broken. The disagreement is the
finding, and the note gets rewritten.

## Reading the journal

A day file has a `## Summary` of the day's outcomes, and optionally `## Decisions`, which
links that day's decision notes, and `## Follow-ups`, which holds the open work as plain
checkboxes. Its `description:` is the day's headline, so a sweep of descriptions is a quick
index of the project's history. Today's file is still converging, and later calls to
`record` may refine it. Past days don't change, except for their boxes.

**The top-level unticked boxes under `## Follow-ups` across `Journal/` are the project's
TODO list.** A box is the one part of a past day that *is* current, because it is ticked
when the work is done. Nested boxes are subtasks. A box anywhere else, in the journal or in
a note, is an ordinary checklist and not project work. For the whole list as a table, with
a suggestion of what to do next, use `/docs-vault:todos`.

**Older days may use the previous format:** several `##` entries per day, with `### #decision`
blocks for calls made and `### #todo` blocks for open work. Read a `#decision` block as a
decision made that day, and the unticked boxes in a `#todo` block as open follow-ups.
`/docs-vault:todos` still lists those, marked as legacy.

## Reading decisions

Each note in `Decisions/` holds one choice, with a `## Why`. It is written on the day of
the choice and not changed afterwards. When the project changes direction, a newer
decision supersedes the old one and links it from `## Related`, so read the newest decision
on a subject, and follow its links back for the history.

**Don't undo a recorded decision unless asked.** If something is disabled, pinned or
deliberately missing and a decision explains why, someone made that call on purpose.

## Querying

**Use obsidian-cli, and check which vault it's pointed at.** Every project's vault is
named `docs`, so `vault=docs` is ambiguous, and by default the CLI targets whichever vault
was focused last. Before the first query in a session, run `obsidian vault` and check that
the path it reports is this project's `docs/`. If it isn't, or the command fails, use `rg`
and `fd`.

```bash
obsidian search:context query="path:Decisions connection pool" # decisions about a subject
obsidian search:context query="connection pool"                 # full text, with matches
obsidian read file="2026-09-25"                                 # one day
obsidian backlinks file="Connection pool"                       # what refers to a note
```

```bash
rg '^description:' docs/Journal/          # one headline per day
rg '^description:' docs/Decisions/        # one line per decision
rg -il 'connection pool' docs/Decisions/  # decisions about a subject
rg -A12 '^## Follow-ups' docs/Journal/    # follow-ups, with their day
rg -A3 '^### #decision' docs/Journal/     # decisions in older, legacy day files
rg -il 'connection pool' docs/            # full text
fd -F "Connection pool.md" docs/          # where a [[link]] actually lives
```

Note names often contain spaces, so quote them.

## Hand over to `record`

**Load `/docs-vault:record` before calling the work done** (`/docs-vault-record` if the
skills were copied into `.claude/skills/`) as soon as any of these is
true:

- you changed something outside the repo, such as a deployed system, a service, a setting
  or data
- you or the user made a choice whose reason will matter later, including a decision
  *not* to do something
- work was left unfinished, or an open follow-up was finished or reopened
- something tried and abandoned would otherwise be tried again
- a note turned out to be wrong, missing or out of date

If none of these is true, there is nothing to write, so don't load it. Routine code work
that git explains needs no record.
