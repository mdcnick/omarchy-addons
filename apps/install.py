#!/usr/bin/env python3
"""Install the wallpaper Apps widget, removing the earlier bar button."""
import json
from datetime import datetime
from pathlib import Path
import shutil

source = Path(__file__).resolve().parent / 'plugin'
config = Path.home() / '.config' / 'omarchy' / 'shell.json'
destination = config.parent / 'plugins' / 'local.desktop-apps'
stamp = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
if destination.exists():
    backup_dir = config.parent / 'backups' / ('desktop-apps-' + stamp)
    backup_dir.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(destination, backup_dir)
destination.mkdir(parents=True, exist_ok=True)
for name in ('manifest.json', 'DesktopApps.qml'):
    shutil.copy2(source / name, destination / name)
# Read immediately before updating so other desktop customizations are preserved.
data = json.loads(config.read_text())
backup = config.with_name('shell.json.bak.desktop-apps.' + stamp)
shutil.copy2(config, backup)
for entries in data.get('bar', {}).get('layout', {}).values():
    entries[:] = [item for item in entries if item.get('id') != 'local.apps']
plugins = data.setdefault('plugins', [])
if not any(item.get('id') == 'local.desktop-apps' for item in plugins):
    plugins.append({'id': 'local.desktop-apps'})
if 'disabledPlugins' in data:
    data['disabledPlugins'] = [item for item in data['disabledPlugins'] if item != 'local.desktop-apps']
config.write_text(json.dumps(data, indent=2) + '\n')
print('Installed:', destination)
print('Configuration backup:', backup)
