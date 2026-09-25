---
name: preset
description: Save the Obsidian settings of this project's docs/ vault as a named preset, or apply a saved preset so a new vault looks and behaves like one you already have. Settings only, never notes or vault structure. Use when the user runs /docs-vault:preset, or asks to save, capture, reuse, copy or apply their Obsidian settings, set-up or look to another vault.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/preset.sh *)
---

# Obsidian setting presets

A preset is a snapshot of a vault's Obsidian settings, kept outside any project. The
plugin ships no opinions of its own. Whatever a preset holds, the user chose.

A bundled script does the saving and merging, so both behave the same way every time:

```bash
${CLAUDE_SKILL_DIR}/scripts/preset.sh list
${CLAUDE_SKILL_DIR}/scripts/preset.sh save  <name> [vault]
${CLAUDE_SKILL_DIR}/scripts/preset.sh plan  <name> [vault]
${CLAUDE_SKILL_DIR}/scripts/preset.sh apply <name> [vault] [--prefer preset]
```

Run it from the project root. The vault defaults to `docs`. Presets live in
`~/.config/docs-vault/presets/<name>/`, which `$XDG_CONFIG_HOME` or `$DOCS_VAULT_PRESETS`
can move.

## What a preset holds

- **Settings files:** `app.json`, `appearance.json`, `core-plugins.json`,
  `daily-notes.json`, `hotkeys.json`, `types.json` and `graph.json`. For `graph.json` it
  leaves out the zoom level and the last search, which only record where the view was left.
- **Community plugins:** their IDs and each plugin's `data.json` settings, never their code.
  `apply` reports them as not installed, and they're installed fresh.
- **CSS snippets** from `snippets/`.

Never notes, folders or `Conventions.md`, and never workspace state.

## Save

1. Ask for a name if the user didn't give one. Suggest a plain word such as `mine`.
2. Run `preset.sh save <name>`. It refuses to replace an existing preset. If the user
   wants to replace one, show them its path and let them delete it.
3. Report the files it saved and where the preset lives.

## Apply

1. **No name given:** run `preset.sh list`. With one preset, offer it. With several, ask
   which one.
2. **Plan first.** Run `preset.sh plan <name>` and show the user its output. Nothing
   changes yet. `add` lines fill in settings the vault doesn't have. `conflict` lines are
   settings the vault already sets differently.
3. **Settle conflicts.** If there are any, ask whether to keep the vault's values (the
   default) or take the preset's (`--prefer preset`). The choice applies to every conflict
   in the run.
4. **Apply** with `preset.sh apply <name>`, plus `--prefer preset` if chosen. It's safe to
   re-run.
5. **Install missing plugins.** For each `not installed:` line, offer to install it through
   the Obsidian CLI. This downloads third-party code, so get the user's OK for each one.
   Check first that `obsidian vault` reports this project's `docs/`. Then run:

   ```bash
   obsidian plugin:install id=<id>
   obsidian plugin:enable id=<id> filter=community
   ```

   If the CLI isn't available or restricted mode is on, give the user the plugin IDs to
   install from Obsidian's Community plugins settings. Their saved settings are already
   in place.
6. **Graph colours.** If the plan says colour groups match folders this vault doesn't have,
   offer `/docs-vault:graph` to recolour the graph for this vault's layout.
7. **Reload Obsidian.** Obsidian reads these files only at startup, and writes its
   in-memory settings back over them when a setting changes. If it's running, offer
   `obsidian command id=app:reload`, after `obsidian vault` confirms the target.
   Otherwise ask the user to run **Reload app without saving** from the command palette.

## Nothing to record

Settings aren't vault content. Most of these files are gitignored as personal settings,
and git records the rest. Don't write a journal entry unless the user asks for one.
