# ASUS Zenbook Duo (2025) Utilities

A collection of scripts for the ASUS Zenbook Duo UX8406CA (2025) running Linux (Fedora + GNOME + Wayland).

---

## 1. Lower Touchscreen Toggle

A robust bash script that gracefully toggles touch functionality on the lower display **without disabling the ASUS active stylus**.

### The Problem
Standard display or input toggling on the Zenbook Duo completely disables the second screen's I2C controller, unbinding both finger touch and the active stylus simultaneously. Wayland and `libinput` also automatically switch to phantom `UNKNOWN` or `Touchpad` alias nodes if you selectively lock the physical controller.

### The Solution
This script scans for all active `ELAN9009` multi-touch event nodes, bypassing stylus interfaces. It dynamically compiles a tiny native `C` binary that locks those nodes using a kernel `EVIOCGRAB` hold — preventing finger touches from reaching the display server while leaving the stylus fully operational. Running the script again kills the lock and restores touch.

### Prerequisites
- Linux (GNOME + Wayland; `evdev` grabs operate at the kernel level across all distributions)
- `gcc` (usually pre-installed via build-essentials)
- `libnotify-bin` (`notify-send`) for desktop toast notifications

### Installation

1. Clone or download this repository (e.g. to `~/projects/touch toggle/`).
2. Make files executable:
   ```bash
   chmod +x toggle-lower-touch.sh install.sh
   ```
3. Run the installer to configure passwordless sudo:
   ```bash
   ./install.sh
   ```

### Setup Keyboard Shortcut (GNOME)

1. Open **Settings → Keyboard → View and Customize Shortcuts → Custom Shortcuts**
2. Click **Add Shortcut**
3. Name: `Toggle Lower Touch`
4. Command (note the `sudo` prefix and quotes for paths with spaces):
   ```bash
   sudo "/path/to/touch toggle/toggle-lower-touch.sh"
   ```
5. Click **Set Shortcut...** and bind your desired hotkey (e.g. `Ctrl+Shift+T`).

### Logging
Toast notifications indicate current state (`Lower Touchscreen DISABLED` / `ENABLED`). Lock state is maintained via `/tmp/duo_touch_grabber.pid`.

---

## 2. Auto-Wallpaper Switcher

Automatically applies appropriate wallpapers when the Zenbook Duo changes orientation or screen mode. Powered by a `systemd` user service that monitors the [zenbook-duo-linux](https://github.com/zakstam/zenbook-duo-linux) daemon log.

### Modes

| Mode | Trigger | Behavior |
|------|---------|----------|
| **Laptop** | Keyboard attached | One image zoomed to fill the upper screen (2880×1800) |
| **Dual** | Keyboard removed | One image spanned across both vertical screens (2880×3600) |
| **Desktop** | Screen rotated 90° | One image spanned across both side-by-side screens (3600×2880) |
| **Sharing** | Screen flipped 180° | Two images stitched top-to-top (one rotated 180° for the person across) |

### Prerequisites
- [zenbook-duo-linux](https://github.com/zakstam/zenbook-duo-linux) daemon running (provides `/tmp/duo/duo.log`)
- `ImageMagick` (installed automatically by the installer)
- GNOME + Wayland

### Installation

```bash
chmod +x install-wallpaper.sh
./install-wallpaper.sh
```

This will:
- Install `ImageMagick`
- Create wallpaper directories under `~/Pictures/ZenbookWallpapers/`
- Write a default config to `~/.config/zenbook-wallpaper/config`
- Install and enable the `zenbook-wallpaper` systemd user service

### Adding Wallpapers

Place images (`.jpg`, `.png`, `.jpeg`) in the appropriate subfolder:

```
~/Pictures/ZenbookWallpapers/
  Laptop/    ← single-screen wallpapers
  Dual/      ← tall portrait images (or any — auto-cropped)
  Desktop/   ← wide landscape images (or any — auto-cropped)
  Sharing/   ← images for sharing/tent mode
```

### Configuration

Edit `~/.config/zenbook-wallpaper/config` — changes take effect immediately without restarting the service.

```bash
# Disable the wallpaper switcher entirely
ENABLED=false

# Use a specific image instead of random for a mode
DUAL_MODE=default
DUAL_DEFAULT_IMAGE=/home/you/Pictures/ZenbookWallpapers/Dual/panoramic.jpg

# Other modes follow the same pattern:
# LAPTOP_MODE=random|default    LAPTOP_DEFAULT_IMAGE=
# DESKTOP_MODE=random|default   DESKTOP_DEFAULT_IMAGE=
# SHARING_MODE=random|default   SHARING_DEFAULT_IMAGE=
```

### Service Management

```bash
# Stop/start without uninstalling
systemctl --user stop zenbook-wallpaper.service
systemctl --user start zenbook-wallpaper.service

# Disable/enable on login
systemctl --user disable zenbook-wallpaper.service
systemctl --user enable zenbook-wallpaper.service

# View logs
journalctl --user -u zenbook-wallpaper.service -f
```

---

## Acknowledgements

These utilities were developed with the assistance of [Google Gemini](https://gemini.google.com).
