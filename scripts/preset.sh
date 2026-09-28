#!/usr/bin/env bash
# Save a docs/ vault's Obsidian settings as a named preset, and apply one to another vault.
#
#   preset.sh list
#   preset.sh save  <name> [vault]           snapshot the vault's settings
#   preset.sh plan  <name> [vault]           show what apply would change, change nothing
#   preset.sh apply <name> [vault] [--prefer preset]
#
# The vault defaults to ./docs. Presets live in $DOCS_VAULT_PRESETS, or else
# ${XDG_CONFIG_HOME:-~/.config}/docs-vault/presets/<name>/, mirroring .obsidian/.
#
# A preset holds settings only, never notes or plugin code. Community plugins are saved as
# their IDs plus their data.json, so they can be installed fresh. From workspace.json it
# keeps only the layout (sidebars and ribbon), never which notes are open.
#
# apply merges key by key. A key the vault doesn't set yet takes the preset's value. A key
# the vault already sets to something else is a conflict: the vault keeps its value unless
# --prefer preset is given. The layout is one conflict as a whole: a vault that already has
# one keeps it unless --prefer preset is given, and its open notes are kept either way.
# Needs jq 1.6 or later. Written for bash 3.2, which macOS still ships.

set -euo pipefail

command -v jq >/dev/null || { echo "preset.sh needs jq" >&2; exit 2; }

presets=${DOCS_VAULT_PRESETS:-${XDG_CONFIG_HOME:-$HOME/.config}/docs-vault/presets}

# Settings files merged key by key. Anything else in .obsidian/ is left alone.
settings="app.json appearance.json core-plugins.json daily-notes.json hotkeys.json types.json graph.json"
# graph.json keys that only record where the user last left the view.
graph_volatile='["scale", "close", "search"]'

# workspace.json keys that make up the layout. The rest (main, active, lastOpenFiles) is
# the session: which notes are open, in a particular vault.
layout_keys='["left", "right", "left-ribbon"]'

die() { echo "$*" >&2; exit 2; }

# The layout part of a workspace.json, with any note references and search text removed.
layout_of() {
  jq --argjson keep "$layout_keys" '
    with_entries(select(.key as $k | $keep | index($k)))
    | walk(if type == "object" then
        del(.file)
        | if has("query") then .query = "" else . end
        | if has("searchQuery") then .searchQuery = "" else . end
      else . end)' "$1"
}

# A main area with one empty tab, for a vault that has no workspace.json yet.
empty_main='{"main": {"id": "d0c5a0170000main", "type": "split", "direction": "vertical",
  "children": [{"id": "d0c5a0170000tabs", "type": "tabs", "children": [{"id": "d0c5a0170000leaf",
  "type": "leaf", "state": {"type": "empty", "state": {}, "icon": "lucide-file", "title": "New tab"}}]}]}}'

usage() { sed -n '4,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

vault_config() {
  local vault=${1:-docs}
  [ -d "$vault" ] || die "No vault at $vault."
  echo "$vault/.obsidian"
}

preset_dir() {
  case "$1" in "" | */* | .*) die "Preset names are plain words, like 'mine'." ;; esac
  echo "$presets/$1"
}

# Treat a missing file, empty values and the volatile graph keys the same way everywhere.
read_json() {
  local file=$1
  if [ -f "$file" ]; then
    case "$(basename "$file")" in
      graph.json) jq --argjson drop "$graph_volatile" 'with_entries(select(.key as $k | $drop | index($k) | not))' "$file" ;;
      *) cat "$file" ;;
    esac
  else
    echo '{}'
  fi
}

# Every settings file the preset holds, relative to its directory.
preset_files() {
  local dir=$1 f
  for f in $settings community-plugins.json; do
    [ -f "$dir/$f" ] && echo "$f"
  done
  [ -f "$dir/layout.json" ] && echo layout.json
  if [ -d "$dir/plugins" ]; then
    (cd "$dir" && find plugins -mindepth 2 -maxdepth 2 -name data.json | sort)
  fi
  if [ -d "$dir/snippets" ]; then
    (cd "$dir" && find snippets -maxdepth 1 -name '*.css' | sort)
  fi
  return 0
}

# --- list --------------------------------------------------------------------------------

cmd_list() {
  [ -d "$presets" ] || { echo "No presets saved yet ($presets)."; return 0; }
  local d found=
  for d in "$presets"/*/; do
    [ -d "$d" ] || continue
    found=1
    printf '%s\t%s files\n' "$(basename "$d")" "$(preset_files "${d%/}" | wc -l | tr -d ' ')"
  done
  [ -n "$found" ] || echo "No presets saved yet ($presets)."
}

# --- save --------------------------------------------------------------------------------

cmd_save() {
  local name=$1 config dir f plugin
  config=$(vault_config "${2:-}")
  dir=$(preset_dir "$name")
  [ -e "$dir" ] && die "Preset '$name' already exists at $dir. Remove it first to replace it."
  mkdir -p "$dir"

  for f in $settings; do
    [ -f "$config/$f" ] && read_json "$config/$f" | jq . > "$dir/$f"
  done

  if [ -f "$config/community-plugins.json" ]; then
    cp "$config/community-plugins.json" "$dir/community-plugins.json"
    for plugin in $(jq -r '.[]' "$config/community-plugins.json"); do
      if [ -f "$config/plugins/$plugin/data.json" ]; then
        mkdir -p "$dir/plugins/$plugin"
        cp "$config/plugins/$plugin/data.json" "$dir/plugins/$plugin/data.json"
      fi
    done
  fi

  [ -f "$config/workspace.json" ] && layout_of "$config/workspace.json" > "$dir/layout.json"

  if [ -d "$config/snippets" ]; then
    for f in "$config"/snippets/*.css; do
      [ -f "$f" ] || continue
      mkdir -p "$dir/snippets"
      cp "$f" "$dir/snippets/"
    done
  fi

  echo "Saved preset '$name' to $dir:"
  preset_files "$dir" | sed 's/^/  /'
}

# --- plan and apply ----------------------------------------------------------------------

# Merge preset $2 into vault $1. Prints the merged object.
merge_object() {
  jq -n --argjson v "$1" --argjson p "$2" --arg prefer "$3" '
    def unset: . == null or . == [] or . == {} or . == "";
    reduce ($p | keys[]) as $k ($v;
      if (.[$k] | unset) or $prefer == "preset" then .[$k] = $p[$k] else . end)'
}

# One line per key: "add <key>" or "conflict <key> vault=<v> preset=<p>".
changes_object() {
  jq -rn --argjson v "$1" --argjson p "$2" '
    def unset: . == null or . == [] or . == {} or . == "";
    $p | keys[] as $k
    | if $v[$k] == $p[$k] then empty
      elif ($v[$k] | unset) then "add \($k)"
      elif $v[$k] != $p[$k] then "conflict \($k) vault=\($v[$k] | tojson) preset=\($p[$k] | tojson)"
      else empty end'
}

# Colour groups whose path: folders don't exist in the target vault.
missing_graph_paths() {
  local vault=$1 file=$2 folder
  for folder in $(jq -r '.colorGroups[]?.query' "$file" | grep -o 'path:[^ )]*' | sed 's/^path://' | sort -u); do
    [ -d "$vault/$folder" ] || echo "$folder"
  done
  return 0
}

cmd_plan_or_apply() {
  local mode=$1 name=$2 vault=${3:-docs} prefer=${4:-vault}
  local config dir rel target vault_json preset_json changes plugin missing any=
  config=$(vault_config "$vault")
  dir=$(preset_dir "$name")
  [ -d "$dir" ] || die "No preset named '$name' in $presets."

  while IFS= read -r rel; do
    target="$config/$rel"
    case "$rel" in
      snippets/*)
        if [ -f "$target" ]; then
          cmp -s "$dir/$rel" "$target" || echo "$rel: exists and differs, kept the vault's"
        else
          any=1; echo "$rel: new file"
          [ "$mode" = apply ] && mkdir -p "$(dirname "$target")" && cp "$dir/$rel" "$target"
        fi
        continue
        ;;
      layout.json)
        target="$config/workspace.json"
        if [ ! -f "$target" ]; then
          any=1; echo "workspace.json: new file, layout only"
          [ "$mode" = apply ] &&
            jq --argjson main "$empty_main" '$main + .' "$dir/layout.json" > "$target"
        elif [ "$(layout_of "$target" | jq -S .)" != "$(jq -S . "$dir/layout.json")" ]; then
          any=1
          case "$mode:$prefer" in
            apply:preset)
              echo "workspace.json: conflict layout -> took preset, open notes kept"
              jq --slurpfile p "$dir/layout.json" '. + $p[0]' "$target" > "$target.tmp"
              mv "$target.tmp" "$target"
              ;;
            apply:vault) echo "workspace.json: conflict layout -> kept vault" ;;
            *) echo "workspace.json: conflict layout (the vault already has one)" ;;
          esac
        fi
        continue
        ;;
      community-plugins.json)
        vault_json=$(cat "$target" 2>/dev/null || echo '[]')
        changes=$(jq -rn --argjson v "$vault_json" --slurpfile p "$dir/$rel" '$p[0] - $v | .[] | "add \(.)"')
        if [ -n "$changes" ]; then
          any=1; echo "$rel:"; echo "$changes" | sed 's/^/  /'
          [ "$mode" = apply ] &&
            jq -n --argjson v "$vault_json" --slurpfile p "$dir/$rel" '$v + ($p[0] - $v)' > "$target"
        fi
        continue
        ;;
    esac

    vault_json=$(read_json "$target")
    preset_json=$(cat "$dir/$rel")
    changes=$(changes_object "$vault_json" "$preset_json")
    [ -n "$changes" ] || continue
    any=1
    if [ ! -f "$target" ]; then
      echo "$rel: new file, $(echo "$changes" | wc -l | tr -d ' ') settings"
      if [ "$mode" = apply ]; then
        mkdir -p "$(dirname "$target")"
        echo "$preset_json" | jq . > "$target"
      fi
      continue
    fi
    echo "$rel:"
    case "$mode:$prefer" in
      apply:preset) echo "$changes" | sed -e 's/^/  /' -e 's/^\(  conflict .*\)$/\1 -> took preset/' ;;
      apply:vault) echo "$changes" | sed -e 's/^/  /' -e 's/^\(  conflict .*\)$/\1 -> kept vault/' ;;
      *) echo "$changes" | sed 's/^/  /' ;;
    esac
    if [ "$mode" = apply ]; then
      mkdir -p "$(dirname "$target")"
      # Merge into the full file, so the volatile graph keys the vault has are kept.
      merge_object "$(cat "$target" 2>/dev/null || echo '{}')" "$preset_json" "$prefer" > "$target.tmp"
      mv "$target.tmp" "$target"
    fi
  done < <(preset_files "$dir")

  if [ -f "$dir/graph.json" ]; then
    missing=$(missing_graph_paths "$vault" "$dir/graph.json")
    [ -z "$missing" ] ||
      echo "graph.json: colour groups match folders this vault doesn't have: $(echo $missing)"
  fi

  if [ -f "$dir/community-plugins.json" ]; then
    for plugin in $(jq -r '.[]' "$dir/community-plugins.json"); do
      [ -f "$config/plugins/$plugin/manifest.json" ] || echo "not installed: $plugin"
    done
  fi

  [ -n "$any" ] || echo "Nothing to change: the vault already has every setting in '$name'."
}

# --- dispatch ----------------------------------------------------------------------------

[ $# -ge 1 ] || usage
command=$1; shift
case "$command" in
  list) cmd_list ;;
  save) [ $# -ge 1 ] || usage; cmd_save "$1" "${2:-}" ;;
  plan) [ $# -ge 1 ] || usage; cmd_plan_or_apply plan "$1" "${2:-docs}" ;;
  apply)
    [ $# -ge 1 ] || usage
    name=$1; shift
    vault=docs prefer=vault
    while [ $# -gt 0 ]; do
      case "$1" in
        --prefer) prefer=${2:-}; shift 2 || usage ;;
        *) vault=$1; shift ;;
      esac
    done
    case "$prefer" in vault | preset) ;; *) usage ;; esac
    cmd_plan_or_apply apply "$name" "$vault" "$prefer"
    ;;
  *) usage ;;
esac
