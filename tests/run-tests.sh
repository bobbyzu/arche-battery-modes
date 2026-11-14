#!/bin/sh
# Test bench for Arche Battery Modes. NO real root, NO real battery.
# SPDX-License-Identifier: MIT
#
# Re-executes itself inside an unprivileged user + mount namespace (unshare -rm):
# "root" there has no privilege on the real system. Everything happens in a
# temporary directory with a fake sysfs. The privileged controller is tested on a
# COPY whose lines tagged "fixed-path" are rewritten to point into that directory.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)

if [ "${ARCHE_TEST_INNER:-}" != 1 ]; then
  command -v unshare >/dev/null || { echo 'SKIP: unshare not available' >&2; exit 77; }
  unshare -rm true 2>/dev/null || { echo 'SKIP: unprivileged user namespaces disabled' >&2; exit 77; }
  exec unshare -rm env ARCHE_TEST_INNER=1 sh "$0" "$@"
fi

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
ok=0; ko=0
check() { if eval "$2"; then ok=$((ok+1)); echo "ok    $1"; else ko=$((ko+1)); echo "FAIL  $1"; fi; }

SYS=$W/sys/class/power_supply
STATE_DIR=$W/var/lib/arche-battery-modes
CTL=$W/ctl
sed -e "/fixed-path/s|/sys/class/power_supply|$SYS|" \
    -e "/fixed-path/s|/var/lib/arche-battery-modes|$STATE_DIR|" \
    "$HERE/bin/arche-battery-mode" > "$CTL"
grep -q "$SYS" "$CTL" && grep -q "$STATE_DIR" "$CTL" || { echo 'cannot build test copy'; exit 1; }
chmod 755 "$CTL"   # installed with mode 755; the launcher executes it directly

fresh() {
  rm -rf "$W/sys" "$W/var"; mkdir -p "$SYS/BAT0" "$W/var/lib"
  printf '%s\n' "$1" > "$SYS/BAT0/charge_control_start_threshold"
  printf '%s\n' "$2" > "$SYS/BAT0/charge_control_end_threshold"
}
rd() { echo "$(cat "$SYS/BAT0/charge_control_start_threshold")-$(cat "$SYS/BAT0/charge_control_end_threshold")"; }
saved() { cat "$STATE_DIR/mode" 2>/dev/null || echo none; }
ro() { mount --bind "$1" "$1" && mount -o remount,ro,bind "$1" "$1"; }

echo '== Controller: basic modes'
fresh 0 100; sh "$CTL" cockpit >/dev/null
check 'cockpit applies 60-80 and saves the mode' '[ "$(rd)" = 60-80 ] && [ "$(saved)" = cockpit ]'
sh "$CTL" nomade >/dev/null
check 'nomade applies 0-100 and saves the mode' '[ "$(rd)" = 0-100 ] && [ "$(saved)" = nomade ]'
check 'state directory is 700, state file is 600' '[ "$(stat -c %a "$STATE_DIR")" = 700 ] && [ "$(stat -c %a "$STATE_DIR/mode")" = 600 ]'
check 'mode reports nomade' '[ "$(sh "$CTL" mode)" = nomade ]'
fresh 50 90
check 'mode reports custom for 50-90' '[ "$(sh "$CTL" mode)" = custom ]'
check 'status mentions thresholds and active mode' 'sh "$CTL" status | grep -q "50-90%; active mode: custom"'

echo '== Controller: write ordering (no invalid intermediate pair)'
sed 's|^write_threshold() { printf .%s\\n. "\$2" > "\$1"; }|write_threshold() { printf "%s\\n" "$2" > "$1" \&\& echo "$(cat "$START") $(cat "$END")" >> "'"$W"'/trace"; }|' "$CTL" > "$W/ctl-trace"
grep -q trace "$W/ctl-trace" || { echo 'cannot instrument'; exit 1; }
for case in "0 100 cockpit" "60 80 nomade" "70 90 cockpit" "40 50 nomade" "40 50 cockpit" "60 80 cockpit"; do
  set -- $case; fresh "$1" "$2"; : > "$W/trace"
  sh "$W/ctl-trace" "$3" >/dev/null 2>&1
  bad=$(awk '$1 >= $2' "$W/trace" | wc -l)
  check "$1-$2 -> $3: every intermediate pair valid" '[ "$bad" -eq 0 ] && [ -s "$W/trace" -o "$1-$2" = 60-80 ]'
done

echo '== Controller: injected failures'
fresh 60 80; ro "$SYS/BAT0/charge_control_end_threshold"
sh "$CTL" nomade >/dev/null 2>&1; rc=$?
check 'first write fails: error, thresholds unchanged, nothing saved' '[ $rc -ne 0 ] && [ "$(rd)" = 60-80 ] && [ "$(saved)" = none ]'
umount "$SYS/BAT0/charge_control_end_threshold"
fresh 60 80; ro "$SYS/BAT0/charge_control_start_threshold"
sh "$CTL" nomade >/dev/null 2>&1; rc=$?
check 'second write fails: error, full rollback, nothing saved' '[ $rc -ne 0 ] && [ "$(rd)" = 60-80 ] && [ "$(saved)" = none ]'
umount "$SYS/BAT0/charge_control_start_threshold"
sed 's|^write_threshold() { printf .%s\\n. "\$2" > "\$1"; }|write_threshold() { v=$2; [ "$v" = 80 ] \&\& v=79; printf "%s\\n" "$v" > "$1"; }|' "$CTL" > "$W/ctl-liar"
fresh 0 100; sh "$W/ctl-liar" cockpit >/dev/null 2>&1; rc=$?
check 'firmware keeps another value: error, previous thresholds back, nothing saved' '[ $rc -ne 0 ] && [ "$(saved)" = none ] && [ "$(rd)" = 0-100 ]'
fresh 0 100; printf 'abc\n' > "$SYS/BAT0/charge_control_end_threshold"
sh "$CTL" cockpit >/dev/null 2>&1; rc=$?
check 'non-numeric threshold read: refused, nothing written' '[ $rc -ne 0 ] && [ "$(cat "$SYS/BAT0/charge_control_start_threshold")" = 0 ]'
fresh 0 100; rm "$SYS/BAT0/charge_control_end_threshold"
sh "$CTL" cockpit >/dev/null 2>&1; rc=$?
check 'unsupported hardware: clear error' '[ $rc -ne 0 ]'

echo '== Controller: restore only an explicitly saved mode'
fresh 0 100; out=$(sh "$CTL" restore 2>&1); rc=$?
check 'no saved mode: exit 0, thresholds unchanged' '[ $rc -eq 0 ] && [ "$(rd)" = 0-100 ]'
fresh 0 100; mkdir -m 700 -p "$STATE_DIR"; : > "$STATE_DIR/mode"; sh "$CTL" restore >/dev/null 2>&1; rc=$?
check 'empty saved mode: exit 0, thresholds unchanged' '[ $rc -eq 0 ] && [ "$(rd)" = 0-100 ]'
printf 'rm -rf /\n' > "$STATE_DIR/mode"; sh "$CTL" restore >/dev/null 2>&1; rc=$?
check 'invalid saved mode: exit 0, unchanged, nothing executed' '[ $rc -eq 0 ] && [ "$(rd)" = 0-100 ]'
printf 'cockpit' > "$STATE_DIR/mode"; sh "$CTL" restore >/dev/null 2>&1
check 'saved mode without newline restored' '[ "$(rd)" = 60-80 ]'
printf 'nomade\ncockpit\n' > "$STATE_DIR/mode"; sh "$CTL" restore >/dev/null 2>&1
check 'only the first line counts' '[ "$(rd)" = 0-100 ]'
fresh 60 80; mkdir -p "$STATE_DIR"; printf 'nomade\n' > "$W/elsewhere"; ln -s "$W/elsewhere" "$STATE_DIR/mode"
sh "$CTL" restore >/dev/null 2>&1; rc=$?
check 'symlinked state file: refused, unchanged' '[ $rc -ne 0 ] && [ "$(rd)" = 60-80 ]'
fresh 60 80; mkdir -p "$W/target"; ln -s "$W/target" "$STATE_DIR"
sh "$CTL" nomade >/dev/null 2>&1; rc=$?
check 'symlinked state directory: mode not saved through it' '[ $rc -ne 0 ] && [ ! -e "$W/target/mode" ]'
rm -f "$STATE_DIR"

echo '== Controller: arguments and environment'
fresh 60 80
for a in '' Cockpit 'cockpit;id' '--help' '../x' 'restore extra'; do
  sh "$CTL" "$a" >/dev/null 2>&1; rc=$?
  check "argument '$a' refused, unchanged" '[ $rc -eq 2 ] && [ "$(rd)" = 60-80 ]'
done
echo precious > "$W/victim"; mkdir -p "$W/evil"
printf '#!/bin/sh\ntouch %s/evil-ran\nexec /usr/bin/mktemp "$@"\n' "$W" > "$W/evil/mktemp"; chmod 755 "$W/evil/mktemp"
fresh 60 80
ARCHE_STATE_FILE="$W/victim" ARCHE_SYSFS_ROOT="$W/nowhere" ARCHE_BATTERY=BAT9 STATE="$W/victim" BASE="$W/nowhere" PATH="$W/evil:$PATH" sh "$CTL" nomade >/dev/null 2>&1
check 'environment ignored: victim file untouched' '[ "$(cat "$W/victim")" = precious ]'
check 'environment ignored: real (fake) sysfs changed' '[ "$(rd)" = 0-100 ]'
check 'PATH reset: planted mktemp never ran' '[ ! -e "$W/evil-ran" ]'
check 'installed controller contains no ARCHE_ variable' '! grep -q "ARCHE_" "$HERE/bin/arche-battery-mode"'

echo '== Launcher: notification after real read-back'
mkdir -p "$W/fakebin"
SW=$W/switch
sed "/fixed-path/s|/usr/local/sbin/arche-battery-mode|$CTL|" "$HERE/bin/arche-battery-switch" > "$SW"
cat > "$W/fakebin/notify-send" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$W/notes"
EOF
mkpk() { printf '#!/bin/sh\n%s\n' "$1" > "$W/fakebin/pkexec"; chmod 755 "$W/fakebin/pkexec" "$W/fakebin/notify-send"; }
run_sw() { : > "$W/notes"; PATH="$W/fakebin:$PATH" sh "$SW" "$@" >/dev/null 2>&1; }
mkpk 'exec "$@"'
fresh 0 100; run_sw cockpit; rc=$?
check 'success: exit 0, "activé" notification' '[ $rc -eq 0 ] && grep -q "Mode Cockpit activé" "$W/notes"'
mkpk 'exit 126'
fresh 0 100; run_sw cockpit; rc=$?
check 'authentication dismissed: failure notification, mode shown' '[ $rc -eq 1 ] && grep -q "annulée.*nomade" "$W/notes"'
mkpk 'exit 127'
fresh 0 100; run_sw nomade; rc=$?
check 'authorization refused: failure notification' '[ $rc -eq 1 ] && grep -q "refusée" "$W/notes"'
mkpk 'exit 0'
fresh 0 100; run_sw cockpit; rc=$?
check 'pkexec says ok but thresholds differ: failure notification' '[ $rc -eq 1 ] && grep -q "ne correspondent pas" "$W/notes"'
mkpk 'touch '"$W"'/pk-called'
run_sw 'cockpit;id'; rc=$?
check 'launcher rejects bad argument before calling pkexec' '[ $rc -eq 2 ] && [ ! -e "$W/pk-called" ]'

echo '== Installer and uninstaller (DESTDIR staging, no systemctl)'
D=$W/root; rm -rf "$D"; mkdir -p "$D"
DESTDIR=$D sh "$HERE/install.sh" >/dev/null 2>&1; rc=$?
check 'install succeeds into staging' '[ $rc -eq 0 ]'
perms=$(cd "$D" && find . -type f -exec stat -c '%n %u:%g %a' {} + | sort | tr '\n' ';')
check 'controller and launcher root 755' 'echo "$perms" | grep -q "./usr/local/sbin/arche-battery-mode 0:0 755" && echo "$perms" | grep -q "./usr/local/bin/arche-battery-switch 0:0 755"'
check 'service, menu entries, docs root 644' '[ "$(echo "$perms" | tr ";" "\n" | grep -c " 0:0 644$")" -eq 5 ]'
check 'no saved mode created by install' '[ ! -e "$D/var/lib/arche-battery-modes/mode" ]'
DESTDIR=$D sh "$HERE/install.sh" >/dev/null 2>&1; rc=$?
check 'second install refuses to overwrite' '[ $rc -ne 0 ]'
D2=$W/root2; rm -rf "$D2"; mkdir -p "$D2/etc/systemd/system"
printf '[Service]\nExecStart=/bin/sh -c "echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold"\n' > "$D2/etc/systemd/system/old-charge.service"
DESTDIR=$D2 sh "$HERE/install.sh" > "$W/out" 2>&1; rc=$?
check 'existing threshold unit: refused, named, left in place' '[ $rc -ne 0 ] && grep -q old-charge.service "$W/out" && [ -f "$D2/etc/systemd/system/old-charge.service" ] && [ ! -e "$D2/usr/local/sbin/arche-battery-mode" ]'
D3=$W/root3; rm -rf "$D3"; mkdir -p "$D3/usr/local/sbin"; chmod 777 "$D3/usr/local/sbin"
DESTDIR=$D3 sh "$HERE/install.sh" >/dev/null 2>&1; rc=$?
check 'world-writable destination directory: refused' '[ $rc -ne 0 ] && [ ! -e "$D3/usr/local/sbin/arche-battery-mode" ]'
mkdir -p "$D/var/lib/arche-battery-modes"; echo cockpit > "$D/var/lib/arche-battery-modes/mode"
DESTDIR=$D sh "$HERE/uninstall.sh" >/dev/null 2>&1; rc=$?
left=$(cd "$D" && find . -type f | wc -l)
check 'uninstall removes every installed file and the saved mode' '[ $rc -eq 0 ] && [ "$left" -eq 0 ]'

echo '== v0.2.1 regression: saving the mode fails'
fresh 60 80; mkdir -m 700 -p "$STATE_DIR"; ro "$STATE_DIR"
sh "$CTL" nomade >/dev/null 2>&1; rc=$?
check 'state directory not writable: refused BEFORE touching thresholds' '[ $rc -ne 0 ] && [ "$(rd)" = 60-80 ] && [ "$(saved)" = none ]'
umount "$STATE_DIR"
fresh 60 80; mkdir -p "$STATE_DIR/mode"
sh "$CTL" nomade >/dev/null 2>&1; rc=$?
check 'state path is a directory: refused, thresholds unchanged' '[ $rc -ne 0 ] && [ "$(rd)" = 60-80 ] && [ -d "$STATE_DIR/mode" ]'
sed 's|mv -f "\$tmp" "\$STATE"|false|' "$CTL" > "$W/ctl-nosave"; chmod 755 "$W/ctl-nosave"
grep -q '&& false' "$W/ctl-nosave" || { echo 'cannot inject save failure'; exit 1; }
fresh 0 100; mkdir -m 700 -p "$STATE_DIR"; echo nomade > "$STATE_DIR/mode"
out=$(sh "$W/ctl-nosave" cockpit 2>&1); rc=$?
check 'save fails after thresholds changed: previous thresholds restored' '[ $rc -ne 0 ] && [ "$(rd)" = 0-100 ]'
check 'save fails: previous saved mode kept, consistent with thresholds' '[ "$(saved)" = nomade ]'
check 'save fails: message says thresholds were restored' 'echo "$out" | grep -q "previous thresholds (0-100) restored"'
check 'save fails: no temporary file left behind' '[ -z "$(find "$STATE_DIR" -name ".mode.*")" ]'
sed -e 's|mv -f "\$tmp" "\$STATE"|false|' -e 's|^rollback() {.*|rollback() { return 1; }|' "$CTL" > "$W/ctl-nosave2"
fresh 0 100; rm -rf "$STATE_DIR"
out=$(sh "$W/ctl-nosave2" cockpit 2>&1); rc=$?
check 'save AND rollback fail: explicit error asking to check status' '[ $rc -ne 0 ] && echo "$out" | grep -q "could not restore previous thresholds"'

echo '== v0.2.1 regression: other charge managers (installer)'
PROJ=$W/proj; rm -rf "$PROJ"; mkdir -p "$PROJ"
for x in bin systemd desktop README.md LICENSE; do ln -s "$HERE/$x" "$PROJ/$x"; done
mkdir -p "$W/fakesys"
sed -e "/test-hook/s|^PATH=|PATH=$W/fakesys:|" -e "/test-hook/s|^check_services=.*|check_services=1|" "$HERE/install.sh" > "$PROJ/install.sh"
[ "$(grep -c "$W/fakesys\|^check_services=1" "$PROJ/install.sh")" -eq 2 ] || { echo 'cannot build installer test copy'; exit 1; }
fakectl() { printf '#!/bin/sh\ncase "$*" in\n  *is-enabled*) exit %s ;;\n  *is-active*) exit %s ;;\nesac\nexit 0\n' "$1" "$2" > "$W/fakesys/systemctl"; chmod 755 "$W/fakesys/systemctl"; }
inst() { rm -rf "$W/r"; mkdir -p "$W/r"; [ -n "${1:-}" ] && eval "$1"; DESTDIR="$W/r" sh "$PROJ/install.sh" > "$W/out" 2>&1; }
fakectl 1 1
mkunit() { mkdir -p "$W/r$(dirname "$1")"; printf '[Service]\nType=oneshot\nExecStart=%s\n' "$2" > "$W/r$1"; }
mkscript() { mkdir -p "$W/r$(dirname "$1")"; printf '#!/bin/sh\n%s\n' "$2" > "$W/r$1"; }
inst 'mkunit /etc/systemd/system/local-boot.service "/usr/local/sbin/local-boot restore"; mkscript /usr/local/sbin/local-boot "echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold"'; rc=$?
check "unit running an external script that writes thresholds: refused (reported case)" '[ $rc -ne 0 ] && grep -q "local-boot.service (runs /usr/local/sbin/local-boot" "$W/out" && [ ! -e "$W/r/usr/local/sbin/arche-battery-mode" ]'
check 'conflicting unit and script left untouched' '[ -f "$W/r/etc/systemd/system/local-boot.service" ] && grep -q charge_control_ "$W/r/usr/local/sbin/local-boot"'
inst 'mkunit /etc/systemd/system/boot-tweaks.service "-/bin/sh /usr/local/lib/tweaks.sh"; mkscript /usr/local/lib/tweaks.sh "for f in charge_start_threshold; do :; done"'; rc=$?
check 'Exec prefix "-" and script passed to an interpreter: detected' '[ $rc -ne 0 ] && grep -q "runs /usr/local/lib/tweaks.sh" "$W/out"'
inst 'mkunit /etc/systemd/system/laptop-charge-mode.service "/usr/local/sbin/opaque-binary"'; rc=$?
check 'unit whose name suggests a charge manager (opaque program): refused' '[ $rc -ne 0 ] && grep -q "laptop-charge-mode.service (name suggests" "$W/out"'
inst 'mkunit /usr/local/lib/systemd/system/thresholds.timer "/usr/local/sbin/x"'; rc=$?
check 'timer in /usr/local/lib/systemd/system also scanned' '[ $rc -ne 0 ] && grep -q "thresholds.timer" "$W/out"'
inst 'mkdir -p "$W/r/etc/udev/rules.d"; echo "ACTION==\"add\", ATTR{charge_control_end_threshold}=\"80\"" > "$W/r/etc/udev/rules.d/99-battery.rules"'; rc=$?
check 'udev rule writing thresholds: refused' '[ $rc -ne 0 ] && grep -q "99-battery.rules" "$W/out"'
inst 'mkunit /etc/systemd/system/backup.service "/usr/local/sbin/backup --all"; mkscript /usr/local/sbin/backup "rsync -a /home /mnt"'; rc=$?
check 'unrelated unit and script: installation accepted' '[ $rc -eq 0 ] && [ -e "$W/r/usr/local/sbin/arche-battery-mode" ]'
fakectl 0 1; inst; rc=$?
check 'TLP enabled: refused' '[ $rc -ne 0 ] && grep -q "TLP is enabled or running" "$W/out"'
fakectl 1 0; inst; rc=$?
check 'TLP running but not enabled: refused' '[ $rc -ne 0 ] && grep -q "TLP is enabled or running" "$W/out"'
fakectl 1 1; printf '#!/bin/sh\nexit 0\n' > "$W/fakesys/tlp"; chmod 755 "$W/fakesys/tlp"; inst; rc=$?
check 'TLP installed but inactive: installed with a note' '[ $rc -eq 0 ] && grep -q "TLP is installed" "$W/out"'
rm -f "$W/fakesys/tlp"

echo '== Static checks'
check 'service starts only with a saved mode' 'grep -q "^ConditionPathExists=/var/lib/arche-battery-modes/mode" "$HERE/systemd/arche-battery-mode.service"'
check 'service does not make /sys read-only' '! grep -q "^ProtectKernelTunables" "$HERE/systemd/arche-battery-mode.service"'
check 'installer never starts the service (no --now)' '! grep -v "^ *#" "$HERE/install.sh" | grep -q -- "--now"'
check 'menu entries call the user-side launcher' '[ "$(grep -h "^Exec=" "$HERE"/desktop/*.desktop | grep -c "^Exec=/usr/local/bin/arche-battery-switch ")" -eq 2 ]'
check 'no password-less polkit rule shipped' '[ -z "$(find "$HERE" -name "*.rules" -o -name "*.policy")" ]'

echo "== $ok passed, $ko failed"
[ "$ko" -eq 0 ]
