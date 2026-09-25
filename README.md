# docs-vault

Claude Code skills for projects that keep a `docs/` folder as an Obsidian vault. They fix
only two things:

- **The journal.** `docs/journal/YYYY-MM-DD.md`, append-only. It records what was done,
  decided and left open, while the rest of the vault holds what is true now.
- **Two tags.** `#decision` for each call made, with its reason. `#todo` for each block of
  open work, whose unticked boxes form the project's TODO list.

Everything else (folders, templates, bases, other tags, working rules) is up to each
project, and lives in `docs/Conventions.md`.

The plugin ships two skills:

| Skill | What it does |
|---|---|
| `docs-vault-init` | Run once, as `/docs-vault-init`. It surveys `docs/`, enables obsidian-skills, creates the journal, writes `Conventions.md` with you, and records the setup as the first journal entry. It never overwrites existing files. |
| `docs-vault` | Runs on its own whenever work touches the vault. It reads `Conventions.md`, keeps the journal, and follows the tag rules. |

It builds on [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills) for the
Markdown, Bases and CLI know-how.

## Install in a project

Add both marketplaces to the project's `.claude/settings.json`:

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

Alternatively, copy both `skills/` folders into the project's `.claude/skills/`. Then run
`/docs-vault-init`. It adds the obsidian-skills entries itself if they are missing.
