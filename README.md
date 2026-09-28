# docs-vault

> **Archived.** docs-vault is continued as [neoarchivist](https://github.com/ewilazarus/neoarchivist),
> rebuilt around one agent and a Rust CLI. Install that instead.

A Claude Code plugin for projects that keep a `docs/` folder as an Obsidian vault. One
agent, the **vault-keeper**, keeps the vault, and it gives the project three kinds of
durable project memory:

- **Notes: what is true now.** Every note outside the two folders below, organised however
  the project likes, and rewritten in place when the facts change.
- **`Journal/`: what meaningful things happened.** One curated memo per day,
  `Journal/YYYY-MM-DD.md`.
- **`Decisions/`: why important choices were made.** One short note per choice,
  `Decisions/NNNNN-short-slug.md`, numbered across the vault and dated in its frontmatter.

Git records exactly what changed in the repo. Raw AI activity, meaning the commands run, the
files touched, the tests rerun and the approaches tried, is not project memory, so the vault
doesn't keep it. Recording is deliberately lossy: it keeps outcomes and drops execution, and
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
  A later record the same day refines the bullets already there instead of appending a new
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
left as they are: the keeper still reads them, and `/todos` still lists their open boxes,
marked as legacy.

## The vault-keeper

Reading a vault costs context: answering one question can mean reading five notes, a few
journal days and a decision, and recording one piece of work means rereading the notes it
touches. So the main Claude never opens `docs/`. It sends the `docs-vault:vault-keeper`
agent a request, and gets back a short answer:

- **Ask**, in the foreground: `{"kind": "ask", "question": "…"}`. The keeper reads what it
  needs and replies with the answer, the `[[links]]` it rests on, and anywhere the notes,
  the journal, the decisions and the system disagree.
- **Record**, in the background, once there's something worth keeping. The brief carries
  what git can't show: facts that changed, each decision and why, what was tried and
  dropped, what's left open and how to tell it's done, follow-ups finished, and notes found
  wrong. The keeper reads git for the rest, then writes, or explains why nothing needs
  writing.
- **Questions go through Claude.** A subagent can't talk to you, so when the keeper needs
  an answer, its reply says `input-required` with its questions. Claude asks you, then
  resumes the same keeper with your answers.

Both directions are JSON, checked by `scripts/contract.sh`. A hook refuses a request that
doesn't fit, saying exactly what's missing ("`decided[0]` needs `why`"), and sends back a
reply that doesn't fit. The reply states follow the A2A task states: `completed`,
`input-required`, `failed`. The main Claude learns the format from the `keeper-contract`
skill, the only docs-vault skill it can see. It loads only when needed, so a session that
never touches the vault carries just a few lines about it, from the project's `CLAUDE.md`.

The keeper's own rules, for looking things up and for recording, live in `keeper/` and are
handed to it as it starts. Its instructions and the contract are in
`agents/vault-keeper.md`.

## Commands

You can also go to the keeper directly. These run inside it, so their work stays out of
the main conversation, and their result comes back to you in Markdown:

| Command | What it does |
|---|---|
| `/docs-vault:init` | Run once per project. It surveys `docs/`, offers both plugins to the project through its settings, creates `Journal/` and `Decisions/`, writes `Conventions.md` with you, adds a short docs-vault section to the project's `CLAUDE.md`, can set up the git checks, and records the setup as the first journal entry. A bundled script makes the file changes, shown first as a plan: it only adds what's missing, keeps any setting already set differently, and changes nothing on a second run. Its questions come to you in one round. |
| `/docs-vault:ask <question>` | Look something up yourself: what is true from the notes, what happened from the journal, why from the decisions, with links and any disagreements. |
| `/docs-vault:record` | Runs in the main conversation, since only it knows what happened: Claude turns the conversation into a record request and sends it to the keeper in the background. |
| `/docs-vault:todos` | A bundled script lists every open follow-up in the journal as a table: the day it was raised, its text and its sub-items. The keeper shows it as-is and recommends the easiest item to pick up next. |
| `/docs-vault:lint` | A bundled script checks the whole vault, including what shell commands, Obsidian and merges wrote past the hooks: broken wikilinks, heading links and block links, bare `§` references, misnamed, future or malformed journal days, and decisions with a shared number, no `date:`, no `## Why` or no journal day linking them. It shows the table, separates what can be fixed from history that stays as it is, and fixes nothing until you say so. |
| `/docs-vault:graph` | Gives each kind of note its own colour in Obsidian's graph view, based on the layout in `Conventions.md`. A bundled script writes the colours, keeping your other graph settings and any groups you chose unless you say otherwise, and it offers to reload Obsidian. |
| `/docs-vault:preset` | Saves a vault's Obsidian settings (app, appearance, core and community plugins and their settings, hotkeys, graph, CSS snippets, and the sidebar layout without any open notes) as a named preset in `~/.config/docs-vault/presets/`, and applies one to another vault. It shows the changes first, lets you choose how to settle conflicts, installs missing community plugins fresh, and never copies notes or plugin code. |

## Hooks

The plugin's hooks hold the design in place, so none of it depends on Claude remembering:

- **Only the keeper touches `docs/`.** Reads and writes from the main Claude, or any other
  agent, are refused and pointed at the keeper. Obsidian's own settings in
  `docs/.obsidian/` are exempt, because they aren't notes.
- **The keeper starts with its rules,** and each request and reply is checked against the
  contract, as above.
- **The keeper's own commands run without prompts:** the plugin's scripts, read-only git
  commands and `date`, each on its own. A plugin agent can't carry permission rules, so
  the hook approves exactly those. Anything combined with `&&`, a pipe, a substitution or
  a redirection still asks you.
- **Editing a past journal day** is blocked unless the only changes tick or untick
  checkboxes, at any depth and without touching their text, or re-point a broken
  `[[link]]` while keeping its displayed text. Creating a backdated day file is blocked
  too. Today's day file may be rewritten freely. A future day can't be written at all:
  the journal records what happened, and plans belong in the project's notes. "Today" is
  the machine's local date, so work recorded after midnight goes in the new day's file.
- **Decisions** are created as `Decisions/NNNNN-slug.md`, taking the next number, with
  `date:` set to today in their frontmatter. "Next" counts the decisions on every local
  and remote-tracking branch too, so two branches don't both take the same number. One may be refined on the day it was made. After that, the same rule as a past journal day applies, because a changed
  mind is a new decision.
- **Each note the keeper writes is linted** straight after the write, with the `lint` script
  limited to that note. Any errors, such as a broken link or a day without a Summary, go
  back to the keeper to fix while the note is still in hand. Warnings are left to
  `/docs-vault:lint`, since a note may be only part-way written.
- **Merges are linted too.** After Claude runs `git merge`, `pull`, `rebase` or
  `cherry-pick`, the notes it changed in `docs/` are linted the same way. That is where a
  decision number taken on two branches, or a link to a note renamed on the other side,
  first shows up. Claude reports it, and asks before renumbering a decision.
- **A reminder to record, before finishing.** If a session used the keeper, then changed
  project files outside `docs/`, and hasn't sent it a record request since, Claude is asked
  once, as it stops, whether any of it is worth recording. Often the answer is no, and it
  says so in a line. A record request or the reminder clears it, so it comes back only
  after new changes. To turn it off, set `DOCS_VAULT_STOP_REMINDER=off`, for example in the
  `env` of `.claude/settings.local.json`.
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

## Checking every commit

To hold the rules for everyone's edits, not only Claude's, run `/docs-vault:init` and
accept its `--checks` option. It copies three scripts into the project's `.docs-vault/`,
where git can run them without the plugin:

- **A pre-commit hook** runs `.docs-vault/check.sh --staged`. The commit fails if a note it
  changes has lint errors, or if it rewrites a past journal day or an older decision,
  beyond ticking a checkbox or re-pointing a link. Each clone installs its own hook, so
  each teammate runs `/docs-vault:init` once. `git commit --no-verify` skips it, for a
  deliberate migration.
- **On GitHub, a workflow** runs `.docs-vault/check.sh --range` on every push and pull
  request, and judges each commit as of the day it was authored, so rebased work isn't
  mistaken for a rewrite. Elsewhere, run the same command in your CI.

Only notes a commit changes are linted, so older problems don't block anyone. Running
`init` again updates the copies when the plugin changes.

It builds on [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills) for the
Markdown, Bases and CLI know-how.

## Install in a project

In one command, with the `claude` CLI on your PATH:

```bash
curl -fsSL https://raw.githubusercontent.com/ewilazarus/docs-vault/main/bootstrap.sh | bash
```

It adds both marketplaces and installs `docs-vault` for you, in every project, bringing
kepano's `obsidian` plugin along. Run it again to update. Add `-s -- --project`, from a
project's root, to declare the plugins in that project's `.claude/settings.json` instead,
so everyone who opens it is offered them. To read the script before running it:

```bash
curl -fsSLO https://raw.githubusercontent.com/ewilazarus/docs-vault/main/bootstrap.sh
less bootstrap.sh
bash bootstrap.sh --dry-run    # prints the commands without running them
bash bootstrap.sh
```

Then restart Claude Code and run `/docs-vault:init` in the project.

Or interactively, from any project:

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

## Tests

The hook and every bundled script have tests, which need only bash, `jq` and git:

```bash
bash tests/run.sh
```

On macOS, `/bin/bash tests/run.sh` also checks them against bash 3.2. CI runs them on
every push: on macOS under bash 3.2 and bash 5 with the system's BSD tools, and on Ubuntu
with GNU tools and mawk.
