---
name: init
description: Bootstrap a project's docs/ folder as an Obsidian vault for the recall and record skills. It sets up the journal, writes the project's Conventions.md with the user, adds a docs-vault section to the project's CLAUDE.md, and offers the plugins to everyone on the project through its settings. Run once per project, when the user asks to set up, initialise or bootstrap the docs vault.
disable-model-invocation: true
---

# Bootstrap the docs vault

This sets up a project so the `recall` and `record` skills can operate it. They fix only
the journal and its `#decision` and `#todo` tags. Everything else is defined by the
`Conventions.md` you write here, together with the user.

**Never overwrite or move an existing file.** Where something already exists, adopt it,
report it, and move on. The one exception is the marked docs-vault section in `CLAUDE.md`,
which this skill owns and may replace. Do the steps in order. Show the user the plan from step 1 before
you change anything.

**Create files with the Write tool, not shell redirection.** Write refuses to replace a
file you haven't read, which enforces the rule above. Permission checks also treat a
heredoc or `>` into the project as a possible overwrite, and may block it.

## 1. Survey what exists

From the project root:

```bash
ls -la docs/ docs/.obsidian docs/journal 2>&1 | head -40
test -f docs/Conventions.md && sed -n '1,40p' docs/Conventions.md
fd . docs -t d -d 2 -E .obsidian 2>/dev/null || find docs -maxdepth 2 -type d -not -path '*/.obsidian*'
cat .claude/settings.json 2>/dev/null
cat .gitignore 2>/dev/null | grep -n obsidian
ls CLAUDE.md .claude/CLAUDE.md AGENTS.md 2>/dev/null
grep -n 'docs-vault:start' CLAUDE.md .claude/CLAUDE.md AGENTS.md 2>/dev/null
git rev-parse --is-inside-work-tree 2>/dev/null || echo "not a git repo"
pgrep -xq Obsidian && echo "Obsidian is running"
```

Report what is already in place and what this run would add. If `docs/` already holds
notes, the conventions describe *those notes as they are*. Don't propose restructuring them
here. That is a separate job, and only if the user asks.

## 2. Offer the plugins to everyone on the project

`docs-vault` depends on kepano's `obsidian` plugin, from the `obsidian-skills` marketplace,
and Claude Code installs it along with `docs-vault`. It only does that from a marketplace
that is already added, so the project should declare both. Then anyone who opens the
project is offered the plugins. If `.claude/settings.json` doesn't already have these keys,
merge them in, keeping everything else the file contains:

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

Plugins load at session start, so tell the user the change takes effect for others on
their next session.

## 3. Create the journal

```bash
mkdir -p docs/journal
```

If the user uses Obsidian's Daily notes plugin, point it at the journal: set `"folder":
"journal/"` in `docs/.obsidian/daily-notes.json`, merging into that file if it exists.

**Obsidian reads `.obsidian/*.json` only at startup, and writes its in-memory settings
back when they change.** If the survey found Obsidian running, an edit to those files
won't show until it reloads, and it can be lost if the user changes a setting in the
meantime. After the last `.obsidian` edit in this run, offer to reload it. With the user's
OK, run `obsidian command id=app:reload`, after `obsidian vault` confirms the CLI targets
this project's `docs/`. Otherwise ask them to run **Reload app without saving** from the
command palette.

## 4. Write `Conventions.md` with the user

Start from this skill's `assets/Conventions.md`, and fill it in from what the survey found
and what the user tells you. Ask about the things you can't infer, and ask them together,
not one by one:

- **Layout:** which folders exist or should exist, and what each one holds. Don't give
  decisions or open questions a folder of their own, such as ADRs or question notes. The
  journal's `#decision` and `#todo` blocks hold them, and the skills only look there.
- **Notes:** how notes are named, which frontmatter they carry, and whether there are
  templates. If there are, record the folder they live in. If the user has no preference
  on frontmatter, offer a single `description:` line. The journal's day files and
  `Conventions.md` already carry one, so `rg '^description:' docs/` indexes the whole vault.
- **Tags and callouts:** anything beyond `#decision` and `#todo`, and where it goes.
- **Rules:** anything that binds work on this project. Examples are what needs
  confirming first, what must never be done, and how to reach the systems the vault
  documents.

Leave a section out if the user has no answer for it yet. An empty heading is not
a convention. Keep each rule an instruction, followed by its reason. **Don't restate
the journal rules from `record` here.** A copy is one more place that goes stale.

If `docs/Conventions.md` already exists, don't rewrite it. Offer only the additions the
survey turned up.

## 5. Point Claude at the vault from `CLAUDE.md`

`CLAUDE.md` loads in every session. Hooks only fire when Claude touches `docs/`, and
skills only load when a request matches them. This section covers the case neither one
catches: work that changes something the vault documents without ever opening `docs/`.

The section is this skill's `assets/CLAUDE-section.md`. Use it as it is, markers included,
so a later run can find it and update it. **Don't add the skills' rules or the project's
conventions to it.** They live in the skills and in `docs/Conventions.md`, and a copy
here would go stale while loading into every session.

Pick the file from the survey, and show the user the change before writing it:

- **A `CLAUDE.md` exists, at the root or in `.claude/`, and has the markers:** replace the
  text between them with the asset if it differs. Leave the rest of the file alone.
- **A `CLAUDE.md` exists without the markers:** append the section after a blank line.
- **Only `AGENTS.md` exists:** ask the user which option they want. Creating a
  `CLAUDE.md` makes Claude Code stop reading `AGENTS.md` on its own, so either:
  - create `CLAUDE.md` with `@AGENTS.md` on its first line, which keeps `AGENTS.md`
    loaded, followed by the section. Recommend this one, because the section names Claude
    Code commands that other agents reading `AGENTS.md` can't use; or
  - append the section to `AGENTS.md`.
- **Neither exists:** create `CLAUDE.md` at the project root containing just the section.

## 6. Keep Obsidian's per-user state out of git

Add the lines `.gitignore` doesn't already cover, even if the project isn't a git repo
yet, because they matter from its first commit. Say what each group holds rather than
just naming "Obsidian files". A user who doesn't know what's in `.obsidian/` can't
judge whether it belongs in the repo.

- **Personal settings, ignored by default.** Each user's open panes, the graph view's
  settings, their editor preferences such as the default view mode, and their theme and
  fonts. Obsidian rewrites these whenever someone clicks around, zooms the graph or
  changes a preference, so
  they'd churn on every commit, and they aren't the project's to set. Graph colours stay per-user as a result, and
  `/docs-vault:graph` sets them for whoever runs it:

  ```gitignore
  docs/.obsidian/workspace.json
  docs/.obsidian/workspace-mobile.json
  docs/.obsidian/graph.json
  docs/.obsidian/app.json
  docs/.obsidian/appearance.json
  ```

- **Community plugins, offered** if the survey found any. Their code and the list of enabled plugins
  are usually personal installs:

  ```gitignore
  docs/.obsidian/plugins/
  docs/.obsidian/community-plugins.json
  ```

  Leave these out if the project wants to share its plugins, and say so in `Conventions.md`.

## 7. Record the setup

Load `/docs-vault:record`, then write today's journal entry the way it describes. It should have a `##` title in
the past tense, a line of prose on what was set up, and a `### #decision` block for each
real choice made in step 4, with its reason. Put anything left for later, such as
conventions the user wants to settle once the project grows, in a `### #todo` block.

## 8. Hand over

Tell the user to open `docs/` as a vault in Obsidian (Open folder as vault), and that
`recall` and `record` take over from here. If the layout has more than one folder, mention that `/docs-vault:graph` colour-codes the graph view by folder. Summarise what was created, what was already there, and
what was skipped.
