---
name: graph
description: Colour-code the Obsidian graph view of this project's docs/ vault, one colour per kind of note, by writing colour groups to docs/.obsidian/graph.json. Use when the user runs /docs-vault:graph or asks to colour, colour-code or recolour the graph view, or to update it after the vault's layout changes.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/graph.sh *), Bash(${CLAUDE_SKILL_DIR}/../recall/scripts/obsidian.sh *)
---

# Colour the graph view

The graph view's colours live in `colorGroups` in `docs/.obsidian/graph.json`. This skill
sets them from how the vault is organised, so each kind of note reads at a glance.

A bundled script reads and writes them, so you choose the groups and it does the rest:

```bash
${CLAUDE_SKILL_DIR}/scripts/graph.sh show
${CLAUDE_SKILL_DIR}/scripts/graph.sh set [--replace | --add] '<query>=#RRGGBB'...
```

Run it from the project root.

## 1. Survey

```bash
sed -n '/^## Layout/,/^## /p' docs/Conventions.md
fd . docs -t d -d 2 -E .obsidian 2>/dev/null || find docs -maxdepth 2 -type d -not -path '*/.obsidian*'
fd -e md -d 1 . docs 2>/dev/null || find docs -maxdepth 1 -name '*.md'
${CLAUDE_SKILL_DIR}/scripts/graph.sh show
pgrep -xq Obsidian && echo "Obsidian is running"
```

**If the vault already has colour groups, someone chose them.** Show them, and ask whether
to replace them or add to them.

## 2. Pick the groups

Base the groups on the layout in `Conventions.md`, or on the folders if it has no Layout
section. Useful defaults:

- **One colour per top-level folder.** A folder is usually one kind of note.
- **A colour for root notes that act as entry points,** such as a home or index note and
  `Conventions.md`. Match them with `file:Home OR file:Conventions`.
- **A muted grey for `Journal/`.** The journal links to everything and would otherwise
  dominate the graph.
- **A colour of its own for `Decisions/`,** so the choices stand out among the notes they
  link to.
- **A split within a folder where it means something,** such as core concepts versus
  the layers built on them. Match those notes by name.

Use hues that stay distinct on both light and dark themes. Keep to about six groups;
beyond that the colours stop being easy to tell apart.

Show the user the mapping as a table (colour, query, what it covers) before writing it.

## 3. Write the groups

Once the user agrees, pass the groups to the script in order, as `query=#RRGGBB`:

```bash
${CLAUDE_SKILL_DIR}/scripts/graph.sh set \
  'file:Home OR file:Conventions=#F5A623' 'path:Journal=#8A8F98' \
  'path:Decisions=#D68A46' 'path:Concepts=#4C8BF5'
```

- **The first matching group wins,** so list narrower queries before broader ones. A group
  that picks a few notes out of a folder goes before that folder's group.
- **Queries use Obsidian's search syntax:** `path:`, `file:`, `tag:`, joined with `OR`.
- **Existing groups** need the user's choice from step 1: `--replace` swaps them all for
  these, and `--add` keeps them, appends these, and recolours any whose query is already
  there. Without either, the script refuses and lists them.

It converts the colours to the integers Obsidian stores, keeps every other setting in
`graph.json`, creates the file if needed, and opens the Groups panel in graph settings so
the user can see what was added. Show the user the table it prints.

## 4. Reload Obsidian

Obsidian reads `graph.json` only at startup, and writes its in-memory settings back when
they change. If Obsidian is running, the new colours won't show until it reloads, and
they're lost if the user touches a graph setting in the meantime.

Offer to reload it. With the user's OK, run the recall skill's script, which reloads only
once it has checked that the Obsidian CLI targets this vault:

```bash
${CLAUDE_SKILL_DIR}/../recall/scripts/obsidian.sh reload
```

If it didn't reload, pass on what it says. Afterwards, run `graph.sh show` to check that
the new groups survived the reload.

## Nothing to record

The colours are per-user display settings. `init` keeps `graph.json` out of git, because
Obsidian rewrites it whenever the graph is zoomed, so each user runs this skill for
themselves. Don't write a journal entry unless the user asks for one.
