#!/usr/bin/env bash
# Install Portal for the current user. No sudo: it symlinks the plugin into
# Omarchy's user plugin directory and puts the CLI on your PATH.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/yendor.portal"
BIN_DIR="$HOME/.local/bin"

mkdir -p "$(dirname "$PLUGIN_DIR")" "$BIN_DIR"

if [[ -e "$PLUGIN_DIR" && ! -L "$PLUGIN_DIR" ]]; then
  echo "refusing to replace $PLUGIN_DIR — it exists and is not a symlink" >&2
  exit 1
fi
ln -sfn "$SRC" "$PLUGIN_DIR"
ln -sfn "$SRC/bin/omarchy-portal" "$BIN_DIR/omarchy-portal"

# A user plugin is inert until it is listed in shell.json. Service plugins give
# no visible sign of this: the shell reloads the plugin, reports nothing wrong,
# and simply never instantiates it. Do it here so nobody has to find that out.
python3 - "$HOME/.config/omarchy/shell.json" <<'PY'
import json, collections, os, sys, shutil
path = sys.argv[1]
if not os.path.exists(path):
    print("  note: no shell.json yet — add {\"id\": \"yendor.portal\"} to its plugins array")
    raise SystemExit(0)
shutil.copyfile(path, path + ".bak")
with open(path) as fh:
    cfg = json.load(fh, object_pairs_hook=collections.OrderedDict)
plugins = cfg.get("plugins") or []
if any(isinstance(p, dict) and p.get("id") == "yendor.portal" for p in plugins):
    print("  shell.json: already enabled")
else:
    plugins.append(collections.OrderedDict([("id", "yendor.portal")]))
    cfg["plugins"] = plugins
    with open(path, "w") as fh:
        json.dump(cfg, fh, indent=2)
        fh.write("\n")
    print("  shell.json: enabled (backup at shell.json.bak)")
PY

echo "Portal installed."
echo "  plugin : $PLUGIN_DIR -> $SRC"
echo "  cli    : $BIN_DIR/omarchy-portal"
echo
echo "Saving a file under ~/.config/omarchy/plugins/ reloads plugins automatically."
echo "If it does not pick up, run: omarchy-shell shell rescanPlugins"
echo
echo "Test it now with:  omarchy-portal status"
