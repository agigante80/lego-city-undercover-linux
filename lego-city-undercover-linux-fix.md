# Lego City Undercover – Linux Steam Fix Notes
Last updated: 2026-04-12

## System Info
- **GPU**: Intel HD 530 (integrated) + NVIDIA GTX 1070 Mobile (Optimus)
- **NVIDIA driver**: 535.288.01 (server variant — `nvidia-driver-535-server`)
- **Mesa**: 25.2.8
- **Kernel installed**: 6.17.0-20-generic (current), 6.14.0-37-generic (older — was working)
- **Proton**: 3.7 set for this game (`proton_37` in config.vdf) ✓
- **Steam App ID**: 578330
- **Game path**: `/media/500GB/SteamLibrary/steamapps/common/LEGO City Undercover/`
- **Proton prefix**: `/media/500GB/SteamLibrary/steamapps/compatdata/578330/`

## What Was Broken
- Game stopped working after a kernel update (6.14 → 6.17) and/or Mesa 25.2.8 update
- Log showed repeated `RtlpWaitForCriticalSection` deadlocks (audio thread) then crash
- Root cause: game was running on Intel Vulkan (Mesa) instead of NVIDIA — missing `__VK_LAYER_NV_optimus=NVIDIA_only` in launch options
- `nvidia-prime` package was in `rc` (removed) state — no `prime-run` available

## What Was Fixed (2026-04-06)
### ✅ Done
1. **Steam launch options updated** in:
   `[redacted]/.local/share/Steam/userdata/55676049/config/localconfig.vdf`

   **New launch options:**
   ```
   __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia PULSE_LATENCY_MSEC=60 PROTON_LOG=1 %command%
   ```
   Key additions vs before:
   - `__VK_LAYER_NV_optimus=NVIDIA_only` — forces DXVK/Vulkan to use NVIDIA GPU (was missing!)
   - `PULSE_LATENCY_MSEC=60` — fixes audio thread deadlock (later raised to 120, see below)

2. **Proton 3.7 confirmed** as the selected compatibility tool in:
   `[redacted]/.local/share/Steam/config/config.vdf` (already set to `proton_37`)

### ✅ Done (2026-04-06 follow-up)
3. **nvidia-prime** is now installed (`ii` status confirmed).

### ⚠️ New Issue (2026-04-06) — NVIDIA module not loading on 6.14.0-37
**Root cause**: After switching to `nvidia-driver-535-server`, the kernel modules for that
driver only exist for `6.17.0-20-generic`. The old 580 driver modules for `6.14.0-37` were
removed. Booting into `6.14.0-37-generic` means `nvidia.ko` cannot load → `nvidia-smi` fails
→ game falls back to Intel Vulkan → Proton 3.7 crashes.

**Fix Option A — Reboot into 6.17.0-20-generic (recommended, needs reboot):**
```bash
sudo sed -i 's/GRUB_TIMEOUT_STYLE=hidden/GRUB_TIMEOUT_STYLE=menu/' /etc/default/grub
sudo sed -i 's/GRUB_TIMEOUT=0/GRUB_TIMEOUT=5/' /etc/default/grub
sudo update-grub
# Reboot → Advanced options for Ubuntu → 6.17.0-20-generic
# Verify:
uname -r        # expect: 6.17.0-20-generic
nvidia-smi      # expect: GPU listed
```

**Fix Option B — Install nvidia-535-server modules for current kernel (no reboot):**
```bash
sudo apt install linux-modules-nvidia-535-server-6.14.0-37-generic
# If package not found in apt, try DKMS rebuild instead:
# sudo dkms install nvidia/535.288.01 -k 6.14.0-37-generic
sudo modprobe nvidia
nvidia-smi      # expect: GPU listed
```

4. **If NVIDIA Vulkan is still not being used**, add this to launch options:
   ```
   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
   ```

5. **If deadlock persists**, add to launch options:
   ```
   PROTON_NO_ESYNC=1 PROTON_NO_FSYNC=1
   ```

## Second Incident (2026-04-12) — Proton 3.7-8 Not Starting

**Symptom**: Game won't launch at all — page fault crash then RPC service crash in log.

**Root cause**: `appmanifest_420161.acf` was missing from the secondary Steam library.
Without it, Steam doesn't recognise Proton 3.7-8 as installed and silently falls back to
GE-Proton10-34, which is incompatible with this game.

Key log signatures when this happens:
- `Unhandled exception: page fault on read access to 0x000000000000000c`
- `err:service:device_notify_proc failed to get event, error 1726`

**Fix applied (2026-04-12)**:

1. Created the missing manifest:
   `/media/500GB/SteamLibrary/steamapps/appmanifest_420161.acf`
   (StateFlags=4, installdir="Proton 3.7", appid=420161, LastOwner=55676049)

2. Restarted Steam — it re-read the manifest and re-registered Proton 3.7-8.

**No other config changes needed** — `config.vdf` (proton_37 mapping) and
`localconfig.vdf` (launch options) were still correct from the 2026-04-06 fix.

### ⚠️ Follow-up (2026-04-12) — Empty log / prefix incompatibility

After the manifest fix, Proton 3.7-8 loaded but wrote an empty log and the game still didn't start.

**Root cause**: GE-Proton10-34 had previously run and initialized the Wine prefix.
The prefix `version` file contained `GE-Proton10-34`, causing Proton 3.7-8 to bail silently.

**Fix**: Renamed the corrupt prefix as backup and let Proton 3.7-8 create a fresh one:
```bash
mv /media/500GB/SteamLibrary/steamapps/compatdata/578330 \
   /media/500GB/SteamLibrary/steamapps/compatdata/578330.bak-ge-proton
```
Save games are stored in Steam Cloud (`userdata/55676049/578330/remote/`) — not in the prefix.

### ⚠️ Follow-up (2026-04-12) — Audio deadlock at specific scene

`PULSE_LATENCY_MSEC=60` got past the intro but a more audio-intensive scene re-triggered the
`RtlpWaitForCriticalSection` deadlock (threads 003b/003c/003d blocked by 003a → page fault).
A controller was also flooding HID reports (`Device reports coming in too fast`) adding thread pressure.

**Fix**: updated launch options to:
```
__NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia PULSE_LATENCY_MSEC=120 PROTON_NO_ESYNC=1 PROTON_NO_FSYNC=1 PROTON_LOG=1 %command%
```
Changes: `PULSE_LATENCY_MSEC` 60→120, added `PROTON_NO_ESYNC=1 PROTON_NO_FSYNC=1`.

### ⚠️ Follow-up (2026-04-12) — SHANWAN controller flooding HID queue

A SHANWAN Xbox360 clone controller (`045e:028e`, manufacturer string `"SHANWAN"`) was
connected and flooding Wine's HID report queue with events from noisy analog axes.
Log signature: `err:hid_report:process_hid_report Device reports coming in too fast, last report not read yet!`
This adds thread pressure at the worst possible moment, triggering the deadlock above.

**The SHANWAN spoofs the real Xbox360 VID:PID** — distinguish it via manufacturer string only.

**Fix: udev rule + evdev-joystick deadzone**

Install dependency:
```bash
sudo apt install joystick
```

Run the setup script (once, with sudo):
```bash
sudo ~/shanwan-udev-setup.sh
```

This installs `/etc/udev/rules.d/99-shanwan-controller.rules` which applies on every plug-in:
- `--deadzone 4096` — ignores stick movement within ~12.5% of centre (kills jitter events)
- `--fuzz 64` — kernel-level noise filter on all analog axes

After running: unplug and replug the controller to apply immediately.
The rule file and setup script live at:
- `/etc/udev/rules.d/99-shanwan-controller.rules`
- `~/shanwan-udev-setup.sh`

---

## Current Working Configuration (2026-04-12)

### Launch options
File: `~/.local/share/Steam/userdata/55676049/config/localconfig.vdf`
Search for app `578330` → `"LaunchOptions"` key.

```
__NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia PULSE_LATENCY_MSEC=120 PROTON_NO_ESYNC=1 PROTON_NO_FSYNC=1 PROTON_LOG=1 %command%
```

To edit directly (close Steam first, or it will overwrite on exit):
```bash
nano ~/.local/share/Steam/userdata/55676049/config/localconfig.vdf
# search: Ctrl+W → 578330 → find "LaunchOptions" nearby
```

### Proton version
File: `~/.local/share/Steam/config/config.vdf`
Search for `578330` → should show `"name" "proton_37"`.

To edit directly:
```bash
nano ~/.local/share/Steam/config/config.vdf
# search: Ctrl+W → 578330
```

### Proton 3.7-8 manifest (must exist or Steam falls back to wrong Proton)
`/media/500GB/SteamLibrary/steamapps/appmanifest_420161.acf`

If missing, recreate it:
```bash
cat > /media/500GB/SteamLibrary/steamapps/appmanifest_420161.acf << 'EOF'
"AppState"
{
	"appid"		"420161"
	"Universe"		"1"
	"name"		"Proton 3.7-8"
	"StateFlags"		"4"
	"installdir"		"Proton 3.7"
	"LastUpdated"		"0"
	"SizeOnDisk"		"0"
	"buildid"		"0"
	"LastOwner"		"55676049"
	"AutoUpdateBehavior"		"0"
	"AllowOtherDownloadsWhileRunning"		"0"
	"ScheduledAutoUpdate"		"0"
}
EOF
```

---

## Testing Checklist
- [ ] Open Steam → verify launch options show the current string above
- [ ] Launch game — check it starts without crashing
- [ ] Optional: add `DXVK_HUD=devinfo` to launch options temporarily to confirm NVIDIA GPU shows in overlay
- [ ] Log is at: `~/steam-578330.log` (auto-generated by `PROTON_LOG=1`)

## Key Files
| File | Purpose |
|------|---------|
| `~/steam-578330.log` | Game log (regenerated each launch) |
| `~/.local/share/Steam/userdata/55676049/config/localconfig.vdf` | Steam per-user config (launch options) |
| `~/.local/share/Steam/config/config.vdf` | Steam global config (Proton version mapping) |
| `/media/500GB/SteamLibrary/steamapps/appmanifest_420161.acf` | Proton 3.7-8 install manifest |
| `/media/500GB/SteamLibrary/steamapps/compatdata/578330/` | Wine prefix (delete to reset) |
| `/etc/udev/rules.d/99-shanwan-controller.rules` | SHANWAN deadzone/fuzz rule |
| `~/shanwan-udev-setup.sh` | Script to install the udev rule (run with sudo) |
| `/usr/share/vulkan/icd.d/nvidia_icd.json` | NVIDIA Vulkan ICD |
| `/etc/default/grub` | GRUB boot config |
