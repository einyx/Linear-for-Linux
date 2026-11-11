#!/usr/bin/env bash
# Remove the Linear install created by linear-linux.sh.
# Your Linear login and local app data are left alone unless you pass --purge.
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications/linear}"
DESKTOP_FILE="${DESKTOP_FILE:-$HOME/.local/share/applications/linear.desktop}"
THEME_ROOT="${THEME_ROOT:-$HOME/.local/share/icons/hicolor}"
DATA_DIR="$HOME/.config/Linear"

echo "This will remove:"
echo "  $INSTALL_DIR"
echo "  $DESKTOP_FILE"
echo "  $THEME_ROOT/<size>x<size>/apps/linear-desktop.png"
[[ "${1:-}" == "--purge" ]] && echo "  $DATA_DIR  (local app data and login)"
read -rp "Continue? [y/N] " reply
[[ "$reply" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

pkill -f "^$INSTALL_DIR/electron" 2>/dev/null || true
sleep 1
rm -rf "$INSTALL_DIR" "$DESKTOP_FILE"
rm -f "$THEME_ROOT"/*/apps/linear-desktop.png "$THEME_ROOT"/*/apps/linear.png
[[ "${1:-}" == "--purge" ]] && rm -rf "$DATA_DIR"

command -v update-desktop-database >/dev/null && update-desktop-database "$(dirname "$DESKTOP_FILE")" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -f -t "$THEME_ROOT" 2>/dev/null || true
echo "Done."
