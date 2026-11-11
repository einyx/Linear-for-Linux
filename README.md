# Linear on Linux

[Linear](https://linear.app) only ships for macOS and Windows. It is an Electron app though, so the macOS `.dmg` already holds all of the app's JavaScript, which runs anywhere. It is just attached to a macOS runtime. This repo swaps in the Linux runtime and fixes what breaks. You get a real Linux app. No Wine, no VM, no emulation.

## Run it

1. Download the `.dmg` from [linear.app/download](https://linear.app/download)
2. Install what you need: `sudo apt install curl python3`
3. Run `./linear-linux.sh "Linear.dmg"`
4. Open Linear from your app menu and sign in

That is it. The script installs to `~/Applications/linear`, adds a desktop entry, registers the `linear://` sign-in handler, and tests the build before it tells you it worked. Run `./uninstall.sh` to undo it.

Set `INSTALL_DIR=` to install somewhere else. You need x86-64. Tested on Pop!\_OS (Ubuntu base) with Linear 1.32.8 and Electron 44.9.1.

## The icon

The script pulls Linear's real app icon out of the `.dmg` and installs it into the hicolor icon theme at `~/.local/share/icons/hicolor/<size>x<size>/apps/linear-desktop.png`, in every size a launcher might ask for. The desktop entry references the theme by name, so the launcher picks the resolution it needs instead of scaling one big image.

The name is `linear-desktop` and not `linear` on purpose. Themes such as WhiteSur already ship an icon called `linear` for something else, and a theme entry beats hicolor, so the app would end up with the wrong picture.

If the `.dmg` has no icon, it falls back to the Linear glyph from `linear.app/favicon.ico`.

## It does not show up in the menu

Some desktops only rescan the desktop database on a shell restart. On GNOME, press `Alt+F2`, type `r`, and hit Enter. On KDE, the menu usually picks it up right away.

To check whether the entry is valid without guessing:

```sh
desktop-file-validate ~/.local/share/applications/linear.desktop
```

No output means the entry is fine and the desktop just needs a refresh.

## What works

| | |
|---|---|
| ✅ | The full app: issues, projects, views, search, keyboard shortcuts. |
| ✅ | Sign-in with Google, Microsoft, SSO, or email |
| ✅ | Notifications and dock/taskbar unread badge |
| ✅ | `linear://` deep links, including the sign-in callback |
| ✅ | Desktop updates, because Linear's updater already ships Linux code |
| ❌ | macOS trackpad extras: force press, haptics, and three-finger swipe navigation. The app detects that the native modules are missing and ignores them. |
| ❌ | Auto-update when the Linux runtime is newer than the macOS one. Run the script again with a newer `.dmg`. |

## Build it yourself

If you would rather not run the script, the conversion takes four steps:

1. Extract the `.dmg` with a modern `7zz`. The `p7zip` in most distros cannot read its LZFSE compression.
2. Read the Electron version out of `Electron Framework.framework/.../Info.plist`, then download that exact Linux build.
3. Unzip the Linux runtime into your install folder, delete `resources/default_app.asar`, and copy `app.asar` plus `app.asar.unpacked` from the bundle into the runtime's `resources/`.
4. Repack `app.asar` without the three macOS-only native modules (`desktop-haptics`, `desktop-force-press`, `desktop-swipe-navigation`). They are optional dependencies loaded in a `try/catch`, so they can also just be left in place.
5. Extract `icon.icns` from the bundle as a PNG and install it into the hicolor icon theme.

`linear-linux.sh` has the exact commands, with comments explaining each one.

## The helper scripts

| | |
|---|---|
| `icns-to-png.py` | Pulls the PNG out of the macOS `.icns`. Uses Pillow if it is installed, otherwise scans the file for PNG chunks by itself. |
| `ico-to-png.py` | Same idea for the `.ico` fallback. |
| `install-icon.py` | Writes the icon into the hicolor theme at every size a launcher might request. |

None of them need a compiler. Pillow is used when it is there, and there is a pure-Python fallback when it is not.

## Why this is simpler than most ports

Unlike most Electron ports, Linear needs no patching and no native compilation:

- **No platform patch.** Linear's API accepts Linux clients. The main process already handles `linux` explicitly: it opens external links with `xdg-open`, resolves home directories for Linux, detects the distro, and ships AppImage code in its updater.
- **No native modules to rebuild.** The only `.node` binaries are macOS trackpad features. There is no database, no keychain, no crypto extension.
- **No renderer bundle.** The desktop app is a thin shell that loads `https://linear.app` in an Electron window, so the UI is always current.

## Notes

- Nothing here gets around licensing or sign-in. You use your own account and the app talks to Linear's real servers.
- Linear's code belongs to Linear. Do not commit `app.asar` or the `.dmg`. The `.gitignore` covers both.
- Running the script again is safe. It wipes and rebuilds the install folder and leaves your login and local data in `~/.config/Linear` alone.
- `./uninstall.sh --purge` also removes the local app data and login.
