# Arche Battery Modes

A small, auditable two-mode battery charge selector for Linux laptops.

| Mode | Start charging below | Stop charging above | Use |
|---|---:|---:|---|
| **Cockpit** | 60 % | 80 % | Laptop mostly plugged in: preserves battery health |
| **Nomade** | 0 % | 100 % | Before travelling: full charge |

Two entries in the application menu switch modes. Each switch asks for administrator authentication through polkit, then shows a desktop notification describing the **real** thresholds read back from the hardware. An optional systemd service restores the mode you explicitly chose at each boot.

Version 0.2.1 — **release candidate, pending independent review.**

## Requirements

- Linux exposing **both** files, readable and writable by root:
  - `/sys/class/power_supply/BAT0/charge_control_start_threshold`
  - `/sys/class/power_supply/BAT0/charge_control_end_threshold`
- `systemd`, `polkit` (`pkexec`) and a graphical polkit authentication agent (KDE Plasma provides one).
- Optional: `notify-send` (Debian/Ubuntu package `libnotify-bin`) for notifications.

## Compatibility and limits

- Threshold support depends on the hardware and kernel driver. ThinkPad laptops (`thinkpad_acpi`) are the main known case; some other vendors expose the same files. **Check that the two files above exist before installing.** The installer refuses otherwise.
- Only the first battery (`BAT0`) is handled. Laptops with a second battery (`BAT1`) are not covered.
- Some firmware only accepts certain values, or a start threshold of 0. The tool reads the values back and reports an error if the firmware did not keep them.
- On many ThinkPads, the thresholds are kept by the embedded controller across reboots. The boot service is then a safety net rather than a necessity.
- Thresholds control **when charging starts and stops**. They do not change discharge, performance or charging safety.
- Tested with Debian 13 and KDE Plasma 6. Other desktops should work if they provide a polkit agent and read `.desktop` files from `/usr/local/share/applications`.

## Other charge-threshold managers (read before installing)

Only **one** tool should manage the thresholds. Otherwise, each one silently overwrites the other.

- **KDE Plasma (PowerDevil):** *System Settings → Power Management → Advanced → Battery charge limit*, on supported hardware. Leave it unset, or do not install this tool. The installer cannot see this setting.
- **TLP:** the installer refuses when `tlp.service` is enabled **or** running. If TLP is installed but neither, it only prints a reminder to keep `START_CHARGE_THRESH_*` and `STOP_CHARGE_THRESH_*` unset.
- **Manual setups:** the installer refuses, names what it found, and **never** disables, edits or deletes it. It looks at:
  - `.service`, `.timer` and `.path` units in `/etc/systemd/system` and `/usr/local/lib/systemd/system` that write thresholds themselves;
  - programs or scripts those units run (any absolute path in their `Exec*=` lines) that mention thresholds;
  - units in those directories whose name contains `charge`, `battery` or `threshold`, even when what they run cannot be read. This may refuse a harmless unit: inspect it, and rename or remove it yourself if appropriate;
  - `/etc/udev/rules.d/*.rules`, `/etc/rc.local`, `/etc/crontab` and `/etc/cron.d/*`.

  To migrate: note the current values, disable the old setup yourself, install, then choose a mode.

### What the installer cannot detect

The detection is a conservative safety net, **not a guarantee**. It does not see:
- desktop settings (PowerDevil, GNOME) and vendor tools or daemons;
- compiled programs, or scripts that build the sysfs path indirectly without the usual file names;
- deeper call chains (a script that calls another script);
- user units (`~/.config/systemd/user`), units shipped by packages in `/usr/lib/systemd/system`, and anything started outside systemd, udev, cron or `rc.local`.

Check your system before installing. After installation, `arche-battery-mode status` showing `custom` instead of the mode you chose usually means another tool rewrote the thresholds.

## Install

Read the whole project first (it is short), then, from the project directory:

```sh
sudo sh ./install.sh
```

Installation does **not** change the thresholds. The boot service is enabled, but it does nothing until you choose a mode for the first time. The installer refuses to overwrite existing files, and checks the ownership and permissions of everything it installs.

## Use

From the application menu: **Mode Cockpit (60–80 %)** or **Mode Nomade (0–100 %)**.

From a terminal:

```sh
arche-battery-switch cockpit                 # same as the menu entry, with notification
/usr/local/sbin/arche-battery-mode status    # read-only, no privileges needed
/usr/local/sbin/arche-battery-mode mode      # prints cockpit, nomade or custom
```

The chosen mode is saved in `/var/lib/arche-battery-modes/mode` and restored at boot. If nothing was ever chosen, or the file is empty or invalid, the thresholds are left untouched.

## Uninstall

```sh
sudo sh ./uninstall.sh
```

This removes the installed files and the saved mode, and disables the service. **The current thresholds stay as they are.** Change them in your desktop settings if needed. The optional user-installed plasmoid must be removed separately from the KDE user session:

```sh
kpackagetool6 --type Plasma/Applet --remove org.arche.batterymodes
```

## Security model

- The privileged controller (`/usr/local/sbin/arche-battery-mode`) uses **fixed paths only**. No environment variable can redirect its reads or writes, even under `sudo -E`. It resets `PATH` and `IFS`, and accepts a closed list of arguments.
- Every privileged change goes through polkit's default `auth_admin` policy. No password-less rule is installed.
- The menu launcher (`arche-battery-switch`) runs as the user. Only the controller runs as root.
- Writes are ordered so that the start threshold always stays below the stop threshold. If a write fails, the previous values are restored when possible. Values are always read back.
- The saved mode is written atomically, in a root-only directory. Only the first line is read, and it must be exactly `cockpit` or `nomade`.
- Thresholds and saved mode stay consistent. The state location is checked, and its temporary file created, **before** any threshold is written. If saving still fails afterwards, the previous thresholds are written back and an error is reported. The same rollback happens when the firmware does not keep the requested values.
- The boot service is sandboxed (`ProtectSystem=strict`, no network, no capabilities). It can write only to `/sys`.

## Tests

The test bench uses a **fake sysfs** and a user namespace. It needs no root and never touches the real battery:

```sh
sh tests/run-tests.sh
```

It requires `unshare` (util-linux) with unprivileged user namespaces enabled. The privileged controller is tested on a copy, whose fixed paths are rewritten to point into a temporary directory.

## Optional KDE Plasma 6 panel widget (prototype)

An optional Plasma 6 plasmoid is bundled in `plasmoid/org.arche.batterymodes`. It reuses the existing controller and switcher; it does not need additional root privileges.

Install as your regular KDE user after installing the battery-mode controller:

```sh
kpackagetool6 --type Plasma/Applet --install ./plasmoid/org.arche.batterymodes
```

Then add **Arche Battery Modes** from the KDE panel widget selector. The plasmoid is a v0.1 prototype; visual behavior and notifications depend on the local Plasma session and require on-device validation.

## Ideas for later

- A "Terrier" storage mode around 40–50 % for long-term storage (not implemented).

## Credits and acknowledgements

- **Silus** — development and security hardening of the battery-mode controller, installer improvements, regression test bench, and independent review of the original implementation (69 simulated tests in the v0.2.1 candidate).
- **Aël** — system architecture collaboration, initial implementation and review, KDE Plasma 6 panel plasmoid prototype, documentation integration.
- **Kaëlys** — project direction, the original desktop/nomad use case, and practical testing on real hardware.
- **Renard** — the cheerful instigator of the battery button and proposer of the future *Terrier* mode. See [`FOX_NOTES.md`](FOX_NOTES.md).

This is a community project, not an official KDE, Lenovo, or AKG product. Credit describes project work, not a third-party endorsement.

## License

MIT. See `LICENSE`.
