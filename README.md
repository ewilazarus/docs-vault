# docs-vault

Claude Code skills for projects that keep a `docs/` folder as an Obsidian vault. They give
the vault three kinds of durable project memory:

- **Notes: what is true now.** Every note outside the two folders below, organised however
  the project likes, and rewritten in place when the facts change.
- **`Journal/`: what meaningful things happened.** One curated memo per day,
  `Journal/YYYY-MM-DD.md`.
- **`Decisions/`: why important choices were made.** One short note per choice,
  `Decisions/NNNNN-short-slug.md`, numbered across the vault and dated in its frontmatter.

Git records exactly what changed in the repo. Raw AI activity, meaning the commands run, the
files touched, the tests rerun and the approaches tried, is not project memory, so the vault
doesn't keep it. `record` is deliberately lossy: it keeps outcomes and drops execution, and
for routine work git already explains, it writes nothing at all.

Everything else (folders, templates, bases, tags, working rules) is up to each project, and
lives in `docs/Conventions.md`.

## The journal

A day file is a short memo, not a log:

```markdown
---
description: "Reworked authentication and settled on middleware authorization."
---

## Summary

- Reworked authorization around application middleware and expanded anonymous and
  expired-session coverage. A router-level approach was abandoned because nested routes
  made it unnecessarily complex.

## Decisions

- [[Decisions/00012-authorization-lives-in-middleware|Authorization lives in middleware]]

## Follow-ups

- [ ] Verify authentication behind the production reverse proxy.
```

- **Today's file converges.** Each bullet is a workstream or an outcome, not an AI session.
  A later `record` the same day refines the bullets already there instead of appending a new
  section, and keeps what you wrote in it yourself.
- **Past days are history.** Once the day is over, its prose doesn't change. Anything
  learned later goes in today's file.
- **Checkboxes stay live.** A follow-up's words record why work was left open that day,
  and its box records whether it still is. So a past day's boxes may be ticked, or
  unticked when work reopens, and nothing else about them changes.

## Decisions

A decision note holds one durable choice: what was decided, and why. The bar is high.
Where a responsibility lives or which database to use qualifies, but a rename or a routine
refactor doesn't. A decision is rationale, not current state: when the project changes
direction, the notes are rewritten and a new decision supersedes the old one, which stays
as it was.

## Follow-ups and `/todos`

Unfinished work is an ordinary Markdown checkbox under `## Follow-ups`, in the day it came
up, right below the Summary that explains it. There is no `#todo` tag, no todo folder and
no task database. The project's TODO list is a view derived from those boxes:
`/docs-vault:todos` lists every unticked top-level box under a `## Follow-ups` heading in
the journal, and it is the canonical view because it applies exactly those rules. A
checkbox anywhere else is just a checklist.

Obsidian Tasks sees every checkbox in the vault, and docs-vault doesn't try to change
that. To get close to the same scope there, limit a query to the journal's Follow-ups:

````markdown
```tasks
not done
path includes Journal/
heading includes Follow-ups
```
````

Tasks still lists nested subtasks as tasks of their own, and matches only the nearest
heading, so a box under a `###` heading inside Follow-ups falls out of this query. Neither
affects `/todos`.

Day files written before this format used `### #decision` and `### #todo` blocks. They are
left as they are: `recall` still reads them, and `/todos` still lists their open boxes,
marked as legacy.

The plugin ships seven skills:

| Skill | What it does |
|---|---|
| `init` | Run once, as `/docs-vault:init`. It surveys `docs/`, offers both plugins to the project through its settings, creates `Journal/` and `Decisions/`, writes `Conventions.md` with you, adds a short docs-vault section to the project's `CLAUDE.md`, and records the setup as the first journal entry. A bundled script makes the file changes, showing them first as a plan: it only adds what's missing, keeps any setting already set differently, and changes nothing on a second run. It never overwrites existing files. |
| `recall` | Read-only. Loads on its own before work the vault documents, or when you ask what happened, what was decided or what is open. It reads `Conventions.md`, answers what is true from the notes, what happened from the journal and why from the decisions, flags where they disagree, and hands over to `record` once there is something to write down. Its lookups run without permission prompts. |
| `todos` | Run as `/docs-vault:todos`. A bundled script lists every open follow-up in the journal as a table: the day it was raised, its text and its sub-items. Claude prints the table as-is and recommends the easiest item to pick up next. |
| `lint` | Run as `/docs-vault:lint`. A bundled script checks the whole vault, including what shell commands, Obsidian and merges wrote past the hooks: broken wikilinks, heading links and block links, bare `§` references, misnamed, future or malformed journal days, and decisions with a shared number, no `date:`, no `## Why` or no journal day linking them. Claude prints the table as-is, separates what can be fixed from history that stays as it is, and fixes nothing until you say so. |
| `graph` | Run as `/docs-vault:graph`, or ask to colour the graph view. It gives each kind of note its own colour in Obsidian's graph view, based on the layout in `Conventions.md`, then offers to reload Obsidian so the colours show. |
| `preset` | Run as `/docs-vault:preset`. It saves a vault's Obsidian settings (app, appearance, core and community plugins and their settings, hotkeys, graph, CSS snippets, and the sidebar layout without any open notes) as a named preset in `~/.config/docs-vault/presets/`, and applies one to another vault. It shows the changes first, lets you choose how to settle conflicts, installs missing community plugins fresh, and never copies notes or plugin code. |
| `record` | Rewrites notes when a fact changes, merges meaningful outcomes into today's journal, writes a decision note for a choice worth explaining, and adds or ticks follow-ups. Often it rightly writes nothing. It loads `recall` first, finds existing follow-ups with the `todos` script, and checks what it wrote with the `lint` script. |

## Hooks

When installed as a plugin, `docs-vault` also ships hooks, so the skills don't depend on
Claude remembering to load them:

- **Reading `docs/`** without `recall` loaded adds a reminder to load it.
- **Writing `docs/`** without `record` (or `init`) loaded is blocked until Claude loads it.
  Subagents count separately, because they don't share the parent's context. Obsidian's
  own settings in `docs/.obsidian/` are exempt, because they aren't notes.
- **Editing a past journal day** is blocked unless the only changes tick or untick
  checkboxes, at any depth and without touching their text, or re-point a broken
  `[[link]]` while keeping its displayed text. Creating a backdated day file is blocked
  too. Today's day file may be rewritten freely. A future day can't be written at all:
  the journal records what happened, and plans belong in the project's notes. "Today" is
  the machine's local date, so work recorded after midnight goes in the new day's file.
- **Decisions** are created as `Decisions/NNNNN-slug.md`, taking the next number, with
  `date:` set to today in their frontmatter. One may be refined on the day it was made. After that, the same rule as a past journal day applies, because a changed
  mind is a new decision.
- **Each note Claude writes is linted** straight after the write, with the `lint` script
  limited to that note. Any errors, such as a broken link or a day without a Summary, go
  back to Claude to fix while the note is still in hand. Warnings are left to
  `/docs-vault:lint`, since a note may be only part-way written.
- **Section references** are links. A write that adds a bare `§4.2` outside a link or code
  is blocked, with a hint to write `[[Spec#4.2 Assertion|Spec §4.2]]` instead. References
  already in a file don't count, so old notes can still be edited.

The past-day check enforces the *shape* of a change, not its meaning. It lets any
checkbox's state change, and nothing else, without parsing Markdown to prove the box sits
under `## Follow-ups`. Deciding which boxes are project work is `/todos`'s job.

The hooks are a bash script and need `jq`, which recent macOS ships and most Linux
distributions package. If `jq` is missing or anything goes wrong, the hooks let the action
through and report a hook error. They never lock you out of your own docs.

**The hooks guard Claude's file-editing tools, not the shell.** They only see Read, Write,
Edit and their kin, so a Bash command that writes into `docs/` bypasses them, as do your
own edits in Obsidian. That is deliberate: shell commands remain an escape hatch, and need
the same trust they always did.

It builds on [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills) for the
Markdown, Bases and CLI know-how.

## Install in a project

Interactively, from any project:

```
/plugin marketplace add kepano/obsidian-skills
/plugin marketplace add ewilazarus/docs-vault
/plugin install docs-vault@docs-vault
```

`docs-vault` depends on kepano's `obsidian` plugin, so the install brings it along.
Claude Code only resolves a dependency from a marketplace you've already added, so add
kepano's first. Without it, the install fails with `Is the "obsidian-skills" marketplace
added?`.

Then run `/docs-vault:init`. Among other things, it adds the settings below to the project.

To offer both plugins to everyone who works on the project, declare both marketplaces in
its `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "obsidian-skills": {
      "source": { "source": "github", "repo": "kepano/obsidian-skills" }
    },
    "docs-vault": {
      "source": { "source": "github", "repo": "ewilazarus/docs-vault" }
    }
  },
  "enabledPlugins": {
    "obsidian@obsidian-skills": true,
    "docs-vault@docs-vault": true
  }
}
```

Alternatively, copy each folder under `skills/` into the project's `.claude/skills/` as
`docs-vault-init`, `docs-vault-recall`, `docs-vault-record`, `docs-vault-todos`, `docs-vault-lint`, `docs-vault-graph` and `docs-vault-preset`. The prefix keeps `init` from
clashing with Claude Code's built-in `/init`. Copied skills don't get the hooks or the
dependency, so install kepano's obsidian-skills yourself.

## Tests

The hook and the `init`, `todos` and `lint` scripts have tests, which need only bash, `jq`
and git:

```bash
bash tests/run.sh
```

On macOS, `/bin/bash tests/run.sh` also checks them against bash 3.2.
