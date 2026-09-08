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

echo "Portal installed."
echo "  plugin : $PLUGIN_DIR -> $SRC"
echo "  cli    : $BIN_DIR/omarchy-portal"
echo
echo "Saving a file under ~/.config/omarchy/plugins/ reloads plugins automatically."
echo "If it does not pick up, run: omarchy-shell shell rescanPlugins"
echo
echo "Test it now with:  omarchy-portal status"
