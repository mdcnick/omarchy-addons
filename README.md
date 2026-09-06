# Omarchy Add-ons

Two desktop additions built for Omarchy's Quickshell shell and Lua-based Hyprland configuration.

## System resources

A transparent CPU, memory, storage, and network strip directly below the existing top bar. It reserves 36 pixels for itself, stays visible across workspaces, follows theme colors, and shows process rankings and a 60-second history on hover. Samples refresh every two seconds.

The default target is HDMI-A-1 (the center Acer in the original setup), falling back to the middle connected screen. Set `RESOURCE_MONITOR` in the widget's launch environment to select another output. Network app rankings cover TCP; interface totals include other traffic. Process visibility depends on normal user permissions.

```sh
python3 resources/install.py
hyprctl reload
hyprctl configerrors
```

Log out and in, or start the widget immediately:

```sh
quickshell -p "$HOME/.config/quickshell/acer-resources/shell.qml" -n -d
```

If an instance is already running, stop that widget with `quickshell kill -p "$HOME/.config/quickshell/acer-resources/shell.qml"` before starting it again. Do not run duplicate instances.

To undo, stop the widget and remove its `acer-resources/shell.qml` launch line from `~/.config/hypr/autostart.lua`. The installer prints the backup location; restore that copy only if you want to undo all later edits to the same file.

## Apps dock

An auto-hiding dock at the bottom center of each monitor, opening a searchable app drawer. It uses the existing Omarchy app library.

```sh
python3 apps/install.py
omarchy restart shell
```

Disable with `omarchy plugin disable local.desktop-apps`. See [dock details](apps/README.md).

## Requirements and compatibility

Requires Linux, Python 3, Quickshell, and Omarchy with the Quickshell plugin system and Lua Hyprland configuration. `ss` from iproute2 provides TCP activity details. No Python packages or root access are required. Tested on the author's Omarchy desktop on September 6, 2026; older Waybar-based Omarchy installations are not supported. Shell internal APIs may change between releases.

Installers back up the files they modify. Install only the additions you want. This repository includes widget code only, without the original user's monitor layout, accounts, or desktop settings.
