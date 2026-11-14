#!/bin/sh
# Uninstall Arche Battery Modes. Run as root.
# SPDX-License-Identifier: MIT
#
# Removes only the files installed by install.sh and the saved mode.
# Charge thresholds are LEFT AS THEY ARE: the firmware keeps the last values.
# Use your desktop's power settings or write the sysfs files to change them.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
D=${DESTDIR:-}
[ "$(id -u)" -eq 0 ] || { echo 'uninstall.sh: run as root' >&2; exit 1; }

if [ -z "$D" ]; then
  systemctl disable arche-battery-mode.service 2>/dev/null || :
fi
for t in /usr/local/sbin/arche-battery-mode /usr/local/bin/arche-battery-switch \
         /etc/systemd/system/arche-battery-mode.service \
         /usr/local/share/applications/arche-cockpit.desktop /usr/local/share/applications/arche-nomade.desktop \
         /usr/local/share/doc/arche-battery-modes/README.md /usr/local/share/doc/arche-battery-modes/LICENSE \
         /var/lib/arche-battery-modes/mode; do
  if [ -e "$D$t" ] || [ -L "$D$t" ]; then rm -f "$D$t"; echo "removed $t"; fi
done
rmdir "$D/usr/local/share/doc/arche-battery-modes" "$D/var/lib/arche-battery-modes" 2>/dev/null || :
[ -n "$D" ] || systemctl daemon-reload
echo 'Uninstalled. Charge thresholds were left unchanged.'
