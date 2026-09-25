# docs-vault

Claude Code skills for projects that keep a `docs/` folder as an Obsidian vault. They fix
only two things:

- **The journal.** `docs/journal/YYYY-MM-DD.md`, append-only. It records what was done,
  decided and left open, while the rest of the vault holds what is true now.
- **Two tags.** `#decision` for each call made, with its reason. `#todo` for each block of
  open work, whose unticked boxes form the project's TODO list.

Everything else (folders, templates, bases, other tags, working rules) is up to each
project, and lives in `docs/Conventions.md`.

The plugin ships four skills:

| Skill | What it does |
|---|---|
| `init` | Run once, as `/docs-vault:init`. It surveys `docs/`, enables obsidian-skills, creates the journal, writes `Conventions.md` with you, and records the setup as the first journal entry. It never overwrites existing files. |
| `recall` | Read-only. Loads on its own before work the vault documents, or when you ask what was decided or what is open. It reads `Conventions.md`, queries the notes and journal, and hands over to `record` once there is something to write down. Its lookups run without permission prompts. |
| `todos` | Run as `/docs-vault:todos`. A bundled script lists every open journal todo as a table: the day it was raised, its `#todo` block, its text and sub-items. Claude prints the table as-is and recommends the easiest item to pick up next. |
| `record` | Writes journal entries with `#decision` and `#todo`, ticks finished todos, and rewrites or creates notes when a fact changes. It loads `recall` first. |

## Hooks

When installed as a plugin, `docs-vault` also ships hooks, so the skills don't depend on
Claude remembering to load them:

- **Reading `docs/`** without `recall` loaded adds a reminder to load it.
- **Writing `docs/`** without `record` (or `init`) loaded is blocked until Claude loads it.
  Subagents count separately, because they don't share the parent's context.
- **Editing a past journal day** is blocked unless the only change ticks a `- [ ]` box or
  re-points a broken `[[link]]` while keeping its displayed text. Creating a backdated day
  file is blocked too.

The hooks are a bash script and need `jq`, which recent macOS ships and most Linux
distributions package. If `jq` is missing or anything goes wrong, the hooks let the action
through and report a hook error. They never lock you out of your own docs. They only see
Claude's file tools, so Bash commands and your own edits in Obsidian are unaffected.

It builds on [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills) for the
Markdown, Bases and CLI know-how.

## Install in a project

Interactively, from any project:

```
/plugin marketplace add ewilazarus/docs-vault
/plugin install docs-vault@docs-vault
```

Then run `/docs-vault:init`. It adds kepano's obsidian-skills to the project's
settings if they are missing.

To pin both for everyone who works on the project, add both marketplaces to its
`.claude/settings.json`:

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
`docs-vault-init`, `docs-vault-recall`, `docs-vault-record` and `docs-vault-todos`. The prefix keeps `init` from
clashing with Claude Code's built-in `/init`. The init skill adds the obsidian-skills
entries itself if they are missing. Copied skills don't get the hooks.
