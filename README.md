# docs-vault

Claude Code skills for projects that keep a `docs/` folder as an Obsidian vault. They fix
only two things:

- **The journal.** `docs/journal/YYYY-MM-DD.md`, append-only. It records what was done,
  decided and left open, while the rest of the vault holds what is true now.
- **Two tags.** `#decision` for each call made, with its reason. `#todo` for each block of
  open work, whose unticked boxes form the project's TODO list.

Everything else (folders, templates, bases, other tags, working rules) is up to each
project, and lives in `docs/Conventions.md`.

The plugin ships three skills:

| Skill | What it does |
|---|---|
| `init` | Run once, as `/docs-vault:init`. It surveys `docs/`, enables obsidian-skills, creates the journal, writes `Conventions.md` with you, and records the setup as the first journal entry. It never overwrites existing files. |
| `recall` | Read-only. Loads on its own before work the vault documents, or when you ask what was decided or what is open. It reads `Conventions.md`, queries the notes and journal, and hands over to `record` once there is something to write down. Its lookups run without permission prompts. |
| `record` | Writes journal entries with `#decision` and `#todo`, ticks finished todos, and rewrites or creates notes when a fact changes. It loads `recall` first. |

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

Alternatively, copy both `skills/` folders into the project's `.claude/skills/`. In that case the commands
are `/docs-vault-init`, `/docs-vault-recall` and `/docs-vault-record`, taken from the
folder names. The init skill adds the obsidian-skills entries itself if they are missing.
