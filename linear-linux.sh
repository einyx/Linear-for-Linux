#!/usr/bin/env bash
# Install the official Linear desktop app on Linux.
#
# Linear only ships macOS and Windows builds. Both are Electron apps, so the
# macOS .dmg already contains all of the app's JavaScript. This script swaps in
# the matching Linux Electron runtime and skips the macOS-only native modules.
# The result is a real Linux app: no Wine, no VM, no emulation.
set -euo pipefail

DMG="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications/linear}"
CACHE_DIR="${CACHE_DIR:-$SCRIPT_DIR/.cache}"
DESKTOP_FILE="${DESKTOP_FILE:-$HOME/.local/share/applications/linear.desktop}"
RES="Linear/Linear.app/Contents/Resources"

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1;36m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }

[[ -n "$DMG" ]] || die "usage: $0 <path-to-linear.dmg>   (INSTALL_DIR=$INSTALL_DIR)"
[[ -f "$DMG" ]] || die "no such file: $DMG"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$CACHE_DIR"


step "Checking prerequisites"

for cmd in curl tar python3; do
  command -v "$cmd" >/dev/null || die "'$cmd' not found. Please install it."
done

# 7zz (or a recent p7zip) is needed to read the .dmg. Modern p7zip can handle
# it, but the official static build is more reliable with UDIF/LZFSE images.
SEVENZZ="$(command -v 7zz || command -v 7z || true)"
if [[ -z "$SEVENZZ" ]]; then
  SEVENZZ="$CACHE_DIR/7zz"
  if [[ ! -x "$SEVENZZ" ]]; then
    info "7zz not found, downloading the official static build (LZFSE support)"
    curl -fsSL -o "$WORK/7z.tar.xz" https://www.7-zip.org/a/7z2501-linux-x64.tar.xz \
      || die "could not download 7zz; install it manually and re-run"
    tar xf "$WORK/7z.tar.xz" -C "$CACHE_DIR" 7zz
    chmod +x "$SEVENZZ"
  fi
fi
info "7zz:  $SEVENZZ"


step "Reading Electron version from the .dmg"

"$SEVENZZ" e "$DMG" \
  "Linear/Linear.app/Contents/Frameworks/Electron Framework.framework/Versions/A/Resources/Info.plist" \
  -o"$WORK/fw" -y >/dev/null || die "could not read the .dmg (is it a Linear disk image?)"
EL_VER="$(grep -A1 CFBundleVersion "$WORK/fw/Info.plist" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
[[ -n "$EL_VER" ]] || die "could not determine the Electron version"
info "Electron $EL_VER"

step "Fetching the Linux Electron runtime"

ZIP="$CACHE_DIR/electron-v$EL_VER-linux-x64.zip"
if [[ ! -f "$ZIP" ]]; then
  URL="https://github.com/electron/electron/releases/download/v$EL_VER/electron-v$EL_VER-linux-x64.zip"
  info "downloading $URL"
  curl -fL --progress-bar -o "$ZIP.part" "$URL" || die "download failed"
  mv "$ZIP.part" "$ZIP"
else
  info "using cached $(basename "$ZIP")"
fi

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
"$SEVENZZ" x "$ZIP" -o"$INSTALL_DIR" -y >/dev/null
chmod +x "$INSTALL_DIR/electron"
rm -f "$INSTALL_DIR/resources/default_app.asar"   # the "welcome to Electron" demo


step "Extracting the app payload"

"$SEVENZZ" x "$DMG" "$RES/app.asar" "$RES/app.asar.unpacked" \
  -o"$WORK/dmg" -y >/dev/null
cp -r "$WORK/dmg/$RES/app.asar" "$WORK/dmg/$RES/app.asar.unpacked" \
      "$INSTALL_DIR/resources/"

# The app is a thin shell that loads https://linear.app in an Electron window.
# Its only native modules are macOS trackpad extras (haptics, force press,
# swipe navigation). They are optional dependencies loaded in a try/catch, so
# on Linux they are simply never used. Dropping them avoids shipping Mach-O
# binaries that cannot load on Linux.
#
# The .node files live inside app.asar, with the unpacked folder holding the
# real bytes. So the archive has to be repacked, and its offsets in the header
# mean it cannot be edited in place. Extract first, then remove the modules
# from both the extracted tree and the unpacked folder, then repack.
if command -v npx >/dev/null && command -v node >/dev/null; then
  info "stripping macOS-only native modules from app.asar"
  rm -rf "$WORK/asar"
  npx --yes @electron/asar extract "$INSTALL_DIR/resources/app.asar" "$WORK/asar" >/dev/null 2>&1 \
    || die "could not unpack app.asar"

  rm -rf "$WORK/asar/node_modules/@linear/desktop-haptics" \
         "$WORK/asar/node_modules/@linear/desktop-force-press" \
         "$WORK/asar/node_modules/@linear/desktop-swipe-navigation"

  rm -rf "$INSTALL_DIR/resources/app.asar.unpacked/node_modules/@linear/desktop-haptics" \
         "$INSTALL_DIR/resources/app.asar.unpacked/node_modules/@linear/desktop-force-press" \
         "$INSTALL_DIR/resources/app.asar.unpacked/node_modules/@linear/desktop-swipe-navigation"

  rm -f "$INSTALL_DIR/resources/app.asar"
  npx --yes @electron/asar pack "$WORK/asar" "$INSTALL_DIR/resources/app.asar" >/dev/null 2>&1 \
    || die "could not repack app.asar"
else
  info "node/npx not found, keeping the macOS native modules in app.asar"
  info "(they are loaded in a try/catch and are simply ignored on Linux)"
fi

"$SEVENZZ" e "$DMG" "Linear/Linear.app/Contents/Info.plist" -o"$WORK/appinfo" -y >/dev/null 2>&1 || true
APP_VER="$(grep -A1 CFBundleShortVersionString "$WORK/appinfo/Info.plist" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"
info "Linear ${APP_VER:-?} payload installed"


step "Installing launcher and desktop entry"

cat > "$INSTALL_DIR/linear.sh" <<EOF
#!/usr/bin/env bash
DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
exec "\$DIR/electron" --ozone-platform-hint=auto "\$@"
EOF
chmod +x "$INSTALL_DIR/linear.sh"

# Icon: the macOS bundle ships Linear's real app icon as an .icns, a dark
# rounded square with the silver Linear glyph. It is self contained, so it
# reads correctly on both light and dark desktops.
#
# Linear's web favicon is the bare glyph with a white fill, which vanishes on
# a light theme. It is kept as a fallback for when the .dmg has no icon.
ICON="$INSTALL_DIR/linear-icon.png"
rm -f "$ICON"

if "$SEVENZZ" e "$DMG" "Linear/Linear.app/Contents/Resources/icon.icns" -o"$WORK" -y >/dev/null 2>&1; then
  if python3 "$SCRIPT_DIR/icns-to-png.py" "$WORK/icon.icns" "$ICON" 2>/dev/null; then
    info "icon: Linear app icon from the .dmg"
  else
    rm -f "$ICON"
  fi
fi

if [[ ! -f "$ICON" ]] && curl -fsSL -o "$WORK/favicon.ico" "https://linear.app/favicon.ico" 2>/dev/null \
   && [[ -s "$WORK/favicon.ico" ]]; then
  if python3 "$SCRIPT_DIR/ico-to-png.py" "$WORK/favicon.ico" "$ICON" 2>/dev/null; then
    info "icon: Linear glyph from linear.app"
  else
    rm -f "$ICON"
  fi
fi

# Install the icon into the hicolor theme so launchers can pick the size they
# need instead of scaling one big PNG.
#
# The name is "linear-desktop" and not "linear" on purpose. Themes such as
# WhiteSur already ship an icon called "linear" for something else, and the
# theme wins over the hicolor fallback, which would show the wrong picture.
THEME_ROOT="${THEME_ROOT:-$HOME/.local/share/icons/hicolor}"
ICON_THEME_NAME="linear-desktop"
if [[ -f "$ICON" ]]; then
  if python3 "$SCRIPT_DIR/install-icon.py" "$ICON" "$THEME_ROOT" "$ICON_THEME_NAME" 2>/dev/null; then
    info "icon theme: $THEME_ROOT/<size>x<size>/apps/$ICON_THEME_NAME.png"
  else
    ICON_THEME_NAME=""
  fi
else
  info "no icon found, the desktop entry will use the generic app icon"
fi

mkdir -p "$(dirname "$DESKTOP_FILE")"
# Prefer the theme name so the launcher picks the size it needs. Fall back to
# the raw file, and to no icon key at all rather than a missing path.
if [[ -n "$ICON_THEME_NAME" ]]; then
  ICON_LINE="Icon=$ICON_THEME_NAME"
elif [[ -f "$ICON" ]]; then
  ICON_LINE="Icon=$ICON"
else
  ICON_LINE=""
  info "no icon installed, the desktop entry will use the generic app icon"
fi
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Linear
GenericName=Issue Tracker
Comment=The issue tracking tool for modern product development
Exec=$INSTALL_DIR/linear.sh %U
$ICON_LINE
Terminal=false
Categories=Development;IDE;
StartupNotify=true
StartupWMClass=Linear
MimeType=x-scheme-handler/linear;
Keywords=issue;tracker;product;development;tasks;
EOF

command -v update-desktop-database >/dev/null && update-desktop-database "$(dirname "$DESKTOP_FILE")" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -f -t "$THEME_ROOT" 2>/dev/null || true

command -v xdg-mime >/dev/null && xdg-mime default "$(basename "$DESKTOP_FILE")" x-scheme-handler/linear 2>/dev/null || true

# GNOME Shell caches the desktop database and only rescans it on demand, so a
# freshly installed app can be missing from the app grid until the shell is
# restarted. On Wayland, `Alt+F2` then `r` does that. Restart the shell
# automatically when it is safe to do so.
if [[ "${XDG_CURRENT_DESKTOP:-}" == *"GNOME"* ]] && command -v gnome-shell >/dev/null \
   && pgrep -x gnome-shell >/dev/null; then
  if [[ "${XDG_SESSION_TYPE:-}" == "x11" ]]; then
    info "restarting gnome-shell so the app appears in the menu right away"
    ( sleep 1; pkill -x gnome-shell ) >/dev/null 2>&1 &
  else
    info "restart gnome-shell (Alt+F2, then r) to see Linear in the app grid"
  fi
fi


step "Smoke-testing the app"

# Launch Electron as Node and make sure the bundled main process can be
# loaded and that its entry point parses. If the payload were broken or a
# required module were missing, this fails immediately.
ELECTRON_RUN_AS_NODE=1 "$INSTALL_DIR/electron" -e "
  const path = require('path');
  const root = process.argv[1];
  const pkg = require(path.join(root, 'resources', 'app.asar', 'package.json'));
  if (!pkg.main) throw new Error('package.json has no main entry');
  new Function(require('fs').readFileSync(
    path.join(root, 'resources', 'app.asar', pkg.main), 'utf8'));
  console.log('    ' + pkg.name + ' ' + pkg.version + ' payload parses');
" "$INSTALL_DIR" || die "smoke test failed, the app would not start"

printf '\n\033[32m✓ Linear %s is installed.\033[0m\n' "$APP_VER"
printf '  Launch it from your application menu, or run:\n    %s\n\n' "$INSTALL_DIR/linear.sh"
