#!/bin/sh
# Install Arche Battery Modes. Run as root from the project directory, AFTER review.
# SPDX-License-Identifier: MIT
#
# Non-intrusive by design:
# - does NOT change charge thresholds (the service is enabled, not started);
# - refuses to overwrite any existing file;
# - refuses when another charge-threshold manager is detected, and never
#   disables or removes it.
# DESTDIR (packaging and tests only) installs into a staging root and skips the
# hardware checks and systemctl calls.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin   # test-hook
export PATH
umask 022
cd "$(dirname "$0")"
D=${DESTDIR:-}
check_services=$([ -z "$D" ] && echo 1 || echo 0)   # test-hook

[ "$(id -u)" -eq 0 ] || { echo 'install.sh: run as root' >&2; exit 1; }
die() { echo "install.sh: $*" >&2; exit 1; }

if [ -z "$D" ]; then
  for f in charge_control_start_threshold charge_control_end_threshold; do
    [ -f "/sys/class/power_supply/BAT0/$f" ] || die "BAT0 does not expose $f; hardware not supported"
  done
  command -v pkexec >/dev/null || die 'pkexec (polkit) is required'
  command -v notify-send >/dev/null || echo 'install.sh: note: notify-send not found; menu entries will work without notifications' >&2
fi

# ---- Other charge-threshold managers -------------------------------------
# Best effort, conservative: anything that looks like it manages thresholds
# blocks the installation. Nothing is ever disabled or removed. The limits of
# this detection are documented in README ("Other charge-threshold managers").

# TLP: refuse if its service is enabled OR currently active (it may have been
# started by hand, or enabled through a path systemctl reports differently).
if [ "$check_services" = 1 ]; then
  if systemctl is-enabled --quiet tlp.service 2>/dev/null || systemctl is-active --quiet tlp.service 2>/dev/null; then
    die 'TLP is enabled or running and also manages charge thresholds; choose one tool (nothing was changed)'
  fi
fi
if command -v tlp >/dev/null 2>&1; then
  echo 'install.sh: note: TLP is installed (service not enabled nor running). Make sure START_CHARGE_THRESH_* / STOP_CHARGE_THRESH_* stay unset.' >&2
fi

mentions_thresholds() {
  grep -qs -e 'charge_control_' -e 'charge_start_threshold' -e 'charge_stop_threshold' "$1"
}

conflicts=
add_conflict() { conflicts="$conflicts
  - $1"; }

# systemd units managed by the administrator. For each unit:
#   (a) the unit itself writes thresholds;
#   (b) a program or script it executes (any absolute path in Exec*= lines)
#       mentions thresholds;
#   (c) its name looks like a charge or battery manager.
for dir in /etc/systemd/system /usr/local/lib/systemd/system; do
  for unit in "$D$dir"/*.service "$D$dir"/*.timer "$D$dir"/*.path; do
    [ -f "$unit" ] || continue
    name=${unit##*/}
    case "$name" in arche-battery-mode.service) continue ;; esac
    if mentions_thresholds "$unit"; then add_conflict "$name (writes thresholds)"; continue; fi
    found=
    set -f   # split Exec lines into words without glob expansion
    for word in $(sed -n 's/^[[:space:]]*Exec[A-Za-z]*=//p' "$unit"); do
      while :; do case "$word" in [-@:+!]*) word=${word#?} ;; *) break ;; esac; done
      case "$word" in /*) ;; *) continue ;; esac
      if [ -f "$D$word" ] && mentions_thresholds "$D$word"; then found=$word; break; fi
    done
    set +f
    if [ -n "$found" ]; then add_conflict "$name (runs $found, which writes thresholds)"; continue; fi
    case "$name" in
      *charge*|*battery*|*threshold*) add_conflict "$name (name suggests a charge manager; inspect it)" ;;
    esac
  done
done
# Other places where thresholds are commonly set at boot.
for f in "$D"/etc/udev/rules.d/*.rules "$D"/etc/rc.local "$D"/etc/crontab "$D"/etc/cron.d/*; do
  [ -f "$f" ] || continue
  if mentions_thresholds "$f"; then add_conflict "${f#"$D"} (writes thresholds)"; fi
done
[ -z "$conflicts" ] || die "something already manages charge thresholds:$conflicts
Migrate manually first (see README). Nothing was changed, nothing was disabled."

TARGETS="/usr/local/sbin/arche-battery-mode /usr/local/bin/arche-battery-switch
/etc/systemd/system/arche-battery-mode.service
/usr/local/share/applications/arche-cockpit.desktop /usr/local/share/applications/arche-nomade.desktop
/usr/local/share/doc/arche-battery-modes/README.md /usr/local/share/doc/arche-battery-modes/LICENSE"
for t in $TARGETS; do
  [ ! -e "$D$t" ] && [ ! -L "$D$t" ] || die "refusing to overwrite $t"
done

# Destination directories must not be writable by other users.
for dir in /usr/local/sbin /usr/local/bin /etc/systemd/system /usr/local/share/applications; do
  [ -d "$D$dir" ] || continue
  perm=$(stat -c '%a' "$D$dir"); owner=$(stat -c '%u' "$D$dir")
  [ "$owner" = 0 ] || die "$dir is not owned by root"
  case "$perm" in *[2367]) die "$dir is writable by other users" ;; esac
done

install -D -o root -g root -m 755 bin/arche-battery-mode    "$D/usr/local/sbin/arche-battery-mode"
install -D -o root -g root -m 755 bin/arche-battery-switch  "$D/usr/local/bin/arche-battery-switch"
install -D -o root -g root -m 644 systemd/arche-battery-mode.service "$D/etc/systemd/system/arche-battery-mode.service"
for m in cockpit nomade; do
  install -D -o root -g root -m 644 "desktop/arche-$m.desktop" "$D/usr/local/share/applications/arche-$m.desktop"
done
install -D -o root -g root -m 644 README.md "$D/usr/local/share/doc/arche-battery-modes/README.md"
install -D -o root -g root -m 644 LICENSE   "$D/usr/local/share/doc/arche-battery-modes/LICENSE"

# Verify ownership and permissions of everything installed.
for t in $TARGETS; do
  case "$t" in */sbin/*|*/bin/*) want='0:0 755' ;; *) want='0:0 644' ;; esac
  got=$(stat -c '%u:%g %a' "$D$t")
  [ "$got" = "$want" ] || die "unexpected ownership/permissions on $t: $got (expected $want)"
done

if [ -z "$D" ]; then
  systemctl daemon-reload
  systemctl enable arche-battery-mode.service   # enabled for next boots only; not started
fi

cat <<'MSG'

Installed. Charge thresholds were NOT changed.
Choose a mode from the application menu (Mode Cockpit / Mode Nomade),
or: arche-battery-switch cockpit
Check: /usr/local/sbin/arche-battery-mode status
MSG
