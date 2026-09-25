---
name: graph
description: Colour-code the Obsidian graph view of this project's docs/ vault, one colour per kind of note, by writing colour groups to docs/.obsidian/graph.json. Use when the user runs /docs-vault:graph or asks to colour, colour-code or recolour the graph view, or to update it after the vault's layout changes.
---

# Colour the graph view

The graph view's colours live in `colorGroups` in `docs/.obsidian/graph.json`. This skill
sets them from how the vault is organised, so each kind of note reads at a glance.

## 1. Survey

```bash
sed -n '/^## Layout/,/^## /p' docs/Conventions.md
fd . docs -t d -d 2 -E .obsidian 2>/dev/null || find docs -maxdepth 2 -type d -not -path '*/.obsidian*'
fd -e md -d 1 . docs 2>/dev/null || find docs -maxdepth 1 -name '*.md'
jq '.colorGroups' docs/.obsidian/graph.json 2>/dev/null
pgrep -xq Obsidian && echo "Obsidian is running"
```

**If `colorGroups` already has entries, someone chose them.** Show them, and ask whether
to replace them or add to them.

## 2. Pick the groups

Base the groups on the layout in `Conventions.md`, or on the folders if it has no Layout
section. Useful defaults:

- **One colour per top-level folder.** A folder is usually one kind of note.
- **A colour for root notes that act as entry points,** such as a home or index note and
  `Conventions.md`. Match them with `file:Home OR file:Conventions`.
- **A muted grey for `journal/`.** The journal links to everything and would otherwise
  dominate the graph.
- **A split within a folder where it means something,** such as core concepts versus
  the layers built on them. Match those notes by name.

Use hues that stay distinct on both light and dark themes. Keep to about six groups;
beyond that the colours stop being easy to tell apart.

Show the user the mapping as a table (colour, query, what it covers) before writing it.

## 3. Write `graph.json`

Set only `colorGroups`. Keep every other key in the file, because they hold the user's
graph settings. Create the file if it doesn't exist.

```json
"colorGroups": [
  { "query": "file:Home OR file:Conventions", "color": { "a": 1, "rgb": 16098851 } },
  { "query": "path:journal", "color": { "a": 1, "rgb": 9080728 } },
  { "query": "path:Concepts", "color": { "a": 1, "rgb": 5016565 } }
]
```

- **The first matching group wins,** so list narrower queries before broader ones. A group
  that picks a few notes out of a folder goes before that folder's group.
- **`rgb` is the colour as an integer.** `#4C8BF5` becomes `0x4C8BF5`, which is `5016565`.
- **Queries use Obsidian's search syntax:** `path:`, `file:`, `tag:`, joined with `OR`.

Setting `"collapse-color-groups": false` leaves the Groups panel open in graph settings,
so the user can see what was added.

## 4. Reload Obsidian

Obsidian reads `graph.json` only at startup, and writes its in-memory settings back when
they change. If Obsidian is running, the new colours won't show until it reloads, and
they're lost if the user touches a graph setting in the meantime.

Offer to reload it. With the user's OK, check that `obsidian vault` reports this project's
`docs/`, then run:

```bash
obsidian command id=app:reload
```

Afterwards, check that `colorGroups` in `graph.json` still has the new groups. If the CLI
isn't available, ask the user to run **Reload app without saving** from the command palette.

## Nothing to record

The colours are display settings, and git records the change. Don't write a journal entry
unless the user asks for one.
