---
name: record
description: Write to this project's docs/ Obsidian vault. It rewrites or creates notes when what is true changes, merges meaningful outcomes into today's journal memo, writes a Decisions/ note for a choice whose reason matters, and adds or ticks follow-up checkboxes. Use after changing anything outside the repo, after a decision worth keeping, when work is left unfinished, when a note turns out wrong or missing, and when the user says "write it down", "log this", "record that", "add a follow-up" or "update the docs".
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/../todos/scripts/todos.sh), Bash(${CLAUDE_SKILL_DIR}/../lint/scripts/lint.sh *)
---

# Record to the docs vault

`docs/` is an Obsidian vault. Every path below is relative to it.

**If `/docs-vault:recall` isn't loaded in this session, load it first**
(`/docs-vault-recall` if the skills were copied into `.claude/skills/`). It covers the
project's `Conventions.md`, what notes, the journal and decisions each hold, and how to
find the note you're about to change. This skill doesn't repeat any of that.

## Record outcomes, not activity

**Record the durable outcomes that git can't explain.** Git records exactly what changed
in the repo, and the session transcript records what the agent did. Neither of those is
project memory, and this skill is not a transcript summariser. Each outcome worth keeping
has one home:

| What the work produced | Where it goes |
|---|---|
| A **current fact**: something is true now that wasn't, or a note was wrong | The note that owns it, rewritten in place |
| A **meaningful event**: part of how the project got here | Today's journal, under `## Summary` |
| An **important decision**: a durable choice whose reason could matter later | A new note in `Decisions/`, linked from today's journal |
| A **follow-up**: concrete unfinished work worth resuming | An unticked box under today's journal `## Follow-ups` |

One session may produce any mix of these, or none. **Writing nothing is a correct outcome.**
If you fixed an obvious bug, the tests pass, no documented fact changed, no choice needs
explaining and nothing is left open, git is enough. Say so, and stop.

**Be deliberately lossy.** Keep outcomes, compress hard, and discard the execution. Effort
spent is not a reason to record something. Leave out:

- the commands run, and the files opened or touched;
- repeated test runs, and failures that taught nothing;
- routine implementation mechanics, trivial refactors and minor implementation choices;
- hypotheses that were dropped, conversational reasoning, and narration of what the
  agent did.

Keep a failed approach only when knowing it failed would stop someone repeating it:
"Switched authorization to middleware after testing the router layer; nested routes made
the router approach impractical." Never "The first command used the wrong flag and had to
be rerun."

## How to record

1. Check today's date with `date +%F`, even if you know the date the session started. A
   session can run past midnight, and then the work after midnight belongs to the new
   day's memo. Never write a journal day in the future: the journal records what happened,
   and plans belong in the project's notes.
2. Read the notes that own any fact the work changed.
3. Read today's `Journal/YYYY-MM-DD.md` if it exists: its Summary, Decisions and
   Follow-ups.
4. If a durable choice was made, search `Decisions/` for one that already covers it.
5. If work was left open or finished, look for the follow-up that already covers it, in
   today's file and in earlier days. The `todos` script lists every open one with the day
   that raised it, by the same rules as `/docs-vault:todos`:

   ```bash
   "${CLAUDE_SKILL_DIR}/../todos/scripts/todos.sh"
   ```

   To reopen finished work, find its ticked box with `rg -n '^[-*+] \[[xX]\]' docs/Journal/`.
6. Sort what the session produced into the four kinds above. Most of it will be none of
   them.
7. Rewrite the notes whose facts changed.
8. Create a decision only where one is justified.
9. Add new follow-ups, and tick the ones this work finished.
10. Merge the story into today's Summary.
11. Check what you wrote with the `lint` script, naming each note you created or changed,
    relative to `docs/`:

    ```bash
    "${CLAUDE_SKILL_DIR}/../lint/scripts/lint.sh" --only "Journal/2026-09-28.md" --only "Decisions/00012-authorization-lives-in-middleware.md"
    ```

    It checks links, headings, `§` references and the shape of journal days and decisions,
    and reports only on those notes. Fix every error it reports in them. If you renamed,
    moved or deleted a note, run it without `--only` too, because links to it elsewhere
    may now be broken; fix those by piping them to the new target. Then read what you
    wrote once more, and make sure nothing is said twice.

Don't write a kind just because this list names it.

If the skills were copied into `.claude/skills/`, the scripts are in the sibling folders
`docs-vault-todos/scripts/` and `docs-vault-lint/scripts/` instead.

## Writing notes

Everything outside `Journal/` and `Decisions/` describes **what is true now**. Rewrite
notes in place when that changes.

- **Follow the project's conventions.** Put a note where `Conventions.md` says, with the
  name, frontmatter and template it asks for. Where the conventions are silent, match
  the neighbouring notes. If the vault has no pattern either, ask instead of inventing one.
- **No history in a note.** Don't write "used to be", resolved incidents or superseded
  designs. If how it changed is worth knowing, that belongs in today's Summary. A lesson
  that is still true counts as current knowledge, and it stays.
- **No open work in a note.** A note may state a present fact ("the nightly export fails
  on large inputs"). "Not done yet" is a follow-up in today's journal.
- **Link from the journal to a note** when the Summary describes a change it now reflects.
- **Point at the exact place, with a link.** Link a section of a note with a heading link
  that keeps the reference as its text: `[[Spec#4.2 Assertion|Spec §4.2]]`, or
  `[[#4.2 Assertion|§4.2]]` within the same note. Never leave a bare `§4.2`, "RFC-0001
  §69", "see the section below" or "the entry above", because they break silently when the
  note is reorganised, and a link shows up in backlinks. Inside a table, escape the pipe
  as `\|`. A section of an outside document gets a Markdown link to its URL. The hook
  refuses a change that adds a bare `§` reference.

Don't restructure existing notes to fit a convention unless the user asks.

## Today's journal

There is one file per day, `Journal/YYYY-MM-DD.md`. It is a **curated daily memo** that
answers "what meaningful things happened today?", never "what did the agent do today?".
Someone opening it six months from now should be able to read it comfortably.

```markdown
---
description: "Reworked authentication and settled on middleware authorization."
---

## Summary

- Reworked authorization around application middleware and expanded anonymous and
  expired-session coverage. A router-level approach was evaluated but abandoned because
  nested routes made it unnecessarily complex.
- Simplified session loading and updated the architecture notes to match.

## Decisions

- [[Decisions/00012-authorization-lives-in-middleware|Authorization lives in middleware]]

## Follow-ups

- [ ] Verify authentication behind the production reverse proxy.
- [ ] Add an integration test covering an expired session during token refresh.
```

- **`## Summary` is required. `## Decisions` and `## Follow-ups` appear only when they have
  something in them,** in that order. An empty heading says nothing.
- **One bullet per workstream or outcome, never one per session.** Several sessions on the
  same subject converge into one bullet. A normal day has 1–5 bullets and stays under
  roughly 200–300 words. Lead with the outcome, in plain prose.
- **The `description:` is the day's headline** in one line. Don't repeat the date, because
  the filename already has it. Update it when the day's headline materially changes.
- **`## Decisions` holds links only.** The reason lives in the decision note. The Summary
  may say what was chosen, but doesn't argue it again.
- **No tags for structure.** The section headings carry the meaning, so don't write
  `#decision` or `#todo`. Older day files may still use them, and they stay as they are.
- **Don't add a byline.** `git log` records who wrote what.

### Today's memo converges

Today's file stays open until the day ends. **A later `record` call on the same day never
appends another section.** It merges:

1. Read the current Summary, Decisions and Follow-ups.
2. If the new work continues a workstream a bullet already covers, refine that bullet so it
   states the outcome as it now stands.
3. Add a bullet only for a meaningfully distinct outcome.
4. Remove obvious duplication. Reuse the decision links and follow-ups already there.
5. Update the `description:` if the day's headline changed.

The same bullet, as a day's work on authorization lands:

```markdown
- Investigated moving authorization into middleware.
```

```markdown
- Implemented authorization in middleware after comparing it with a router-level approach.
```

```markdown
- Reworked authorization around application middleware and added anonymous and
  expired-session coverage. A router-level approach was abandoned because nested routes
  made it unnecessarily complex.
```

**The user writes in this file too, in Obsidian.** It is not generated output. Make targeted
edits rather than rewriting the file. Keep the facts and observations already there, even
the ones this session didn't produce. Keep the user's wording where you can, and don't
regenerate the whole Summary to fit one new bullet in.

### Past days are history

> [!danger] A past day's prose never changes
> Once its day has passed, a journal file is evidence of what was known then. Don't rewrite
> its Summary, change its decision links or follow-up wording, add a follow-up or decision
> to it after the fact, or append a retrospective. Don't create a backdated day file.
> Anything learned later goes in today's file.
>
> **Checkbox state is the exception.** A follow-up's words record why the work was left
> open that day. Its box records whether it is *still* open, so the box stays live: tick
> `- [ ]` → `- [x]` when the work is done, untick it when the work genuinely reopens, and
> do the same for nested boxes. Change the box and nothing else. If a link breaks, **pipe**
> it to the new target and keep its displayed text.

## Follow-ups

Unfinished work is a plain Markdown checkbox under `## Follow-ups` in the day it came up,
right below the Summary that explains it. It takes no tag, ID, owner, priority or status,
and there is no task file or folder. The heading is what makes it project work, and
`/docs-vault:todos` or Obsidian Tasks read it as it is.

```markdown
## Follow-ups

- [ ] Verify authentication through the production proxy.
  - Confirm forwarded headers are handled correctly.
  - [x] Verify locally.
  - [ ] Verify against a production-equivalent proxy configuration.
```

- **Only a top-level box is a follow-up.** Nested bullets are its context, and nested boxes
  are its subtasks.
- **Make it checkable.** Write it in the imperative, as the concrete next action or what it
  is waiting on, with the evidence someone needs to know when it's done.
- **Don't duplicate one.** If today's Follow-ups or an open box on an earlier day already
  covers the work, leave that one where it is. Don't copy it into today.
- **A box anywhere else is just a checklist.** A checkbox in a note isn't a project
  follow-up, and open work doesn't go in notes.

**Finishing a follow-up** from any day:

1. Find its box in the day that raised it.
2. Tick it, and its nested boxes as they stand. Leave its words, and that day's Summary,
   alone.
3. If finishing it was meaningful, say so in today's Summary.
4. Rewrite any note whose facts changed.

Don't move a follow-up into today because it was finished today. If finished work turns
out to need more, untick the original box instead of raising a duplicate.

## Decisions

A decision note answers **"why did we choose this?"** Keep the bar high: a durable choice
whose reason someone will need later, such as which storage engine to use, where a
responsibility lives, a rule the project follows, or something deliberately not done.
Renaming, moving a helper, picking between equivalent idioms, fixing a typo or choosing
the obvious API is not a decision note. If it needs saying at all, a clause in the Summary
is enough.

Name it `Decisions/NNNNN-short-slug.md`: the next five-digit number across `Decisions/`
(one more than the highest there, starting at `00001`), then a short lowercase slug.
Numbers are never reused, even when a decision is deleted. The date doesn't go in the
name, because the journal that links the decision already dates it; it goes in the
`date:` frontmatter, which is required.

```markdown
---
description: "Keep authorization policy outside route handlers."
date: 2026-09-27
---

# Authorization lives in middleware

Authorization is enforced by application middleware rather than individual route handlers.

## Why

Keeping authorization outside the routing layer avoids duplicating checks and works more
cleanly with nested routes.

## Related

- [[Journal/2026-09-27]]
```

- **It needs a title that states the choice, what was decided, and `## Why`.** Add
  `## Context`, `## Consequences` or `## Related` only when they add something. There is
  no status, owner, approver, priority, review date or scoring of alternatives.
- **Link it from today's journal** under `## Decisions`, with an aliased wikilink:
  `[[Decisions/00012-authorization-lives-in-middleware|Authorization lives in middleware]]`.
- **A decision records rationale, not current state.** The notes say what is true now, and
  they get rewritten. A decision made today may be refined today. After that it stays as
  it was written, even when the project changes direction. Then write a new decision,
  link the old one from its Related section (`- Supersedes [[Decisions/00004-use-postgres|Use Postgres]]`),
  rewrite the notes the change affects, and summarise the change in today's journal.

## If the vault isn't set up

If `Journal/` or `Decisions/` doesn't exist, create it along with the first file it gets.
If `Conventions.md` doesn't exist, mention `/docs-vault:init` (or `/docs-vault-init`) once
and carry on. Don't bootstrap the vault yourself.
