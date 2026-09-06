# Apps dock for Omarchy

Move the pointer to the bottom-center edge of any monitor to reveal a small
rounded Apps dock. Click Apps to expand the searchable icon drawer in place.
The dock slides away after the pointer leaves; the drawer stays open until
closed or an app is launched. Click ×, or press Escape while searching, to close.

A slim bottom-edge handle marks the hover target. The dock appears over ordinary
windows on every screen, reserves no workspace space, and only captures pointer
input in its visible area and the small edge target. Opening the drawer never
creates a full-screen overlay. Installed apps come from Omarchy's app library.

## Install

Run `python3 install.py`, then `omarchy restart shell`. Restarting ensures
the shell loads the new QML even when hot reload retains an older instance.
The installer backs up the shell configuration and any previous widget version,
installs the user plugin, enables it, and removes the earlier Apps bar button.
Other settings are preserved. No extra packages are required.

## Undo

Run `omarchy plugin disable local.desktop-apps` to hide the dock.
The source is included in this repository under `apps/plugin/`.
