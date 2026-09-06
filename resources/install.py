#!/usr/bin/env python3
"""Install the resource strip without replacing other desktop settings."""
import argparse
import json
import shutil
from datetime import datetime
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--config-dir', type=Path, default=Path.home() / '.config')
args = parser.parse_args()
config = args.config_dir.expanduser().resolve()
auto = config / 'hypr/autostart.lua'
if not auto.exists():
    parser.error('Expected an existing Omarchy Lua configuration: ' + str(auto))
source = Path(__file__).resolve().parent
dest = config / 'quickshell/acer-resources'
backup = config / 'omarchy/backups' / ('resource-strip-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
backup.mkdir(parents=True)
shutil.copy2(auto, backup / 'autostart.lua')
if dest.exists():
    shutil.copytree(dest, backup / 'acer-resources')
dest.mkdir(parents=True, exist_ok=True)
for name in ('shell.qml', 'metrics.py'):
    shutil.copy2(source / name, dest / name)
# Preserve existing startup entry on upgrades.
text = auto.read_text()
if 'acer-resources/shell.qml' not in text:
    import shlex
    command = 'quickshell -p ' + shlex.quote(str(dest / 'shell.qml')) + ' -n -d'
    auto.write_text(text.rstrip() + '\n\n-- Transparent resource strip below the top bar.\no.launch_on_start(' + json.dumps(command) + ')\n')
print('Installed:', dest)
print('Backup:', backup)
print('Run hyprctl reload and hyprctl configerrors, then log out and in to start the strip.')
print('For immediate startup: quickshell -p ' + str(dest / 'shell.qml') + ' -n -d')
