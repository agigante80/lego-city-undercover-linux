# Lego City Undercover – Linux Steam Fix Notes
Last updated: 2026-04-12

## System Info
- **Machine**: 2017 Intel/NVIDIA gaming laptop
- **OS**: Ubuntu 24.04.4 LTS (Noble Numbat)
- **Desktop**: GNOME 46.0 on X11
- **Display 1 (internal)**: Laptop panel, 2560×1440 active (eDP-1, capable of 3840×2160)
- **Display 2 (external)**: Samsung S34C65xU 34" ultrawide, 3440×1440 @ 60 Hz (DP-1)
- **Game resolution**: 1280×720 (set in-game; stored in `pcconfig.txt` in the Wine prefix)
- **Kernel**: 6.17.0-20-generic (HWE, based on upstream 6.17.13)
- **GPU (render)**: NVIDIA GeForce GTX 1070 (Mobile), 8 GB VRAM, PCI 01:00.0
- **GPU (display)**: Intel HD Graphics 530 (Skylake GT2, Optimus)
- **NVIDIA driver**: `535.288.01-0ubuntu0.24.04.3` (`nvidia-driver-535-server`)
- **Mesa**: `25.2.8-0ubuntu0.24.04.1`
- **Kernel also tested**: 6.14.0-37-generic (older — was working before driver switch)
- **Proton**: 3.7-8 set for this game (`proton_37` in config.vdf) ✓
- **Steam App ID**: 578330
- **Game path**: `$STEAM_LIBRARY/steamapps/common/LEGO City Undercover/`
- **Proton prefix**: `$STEAM_LIBRARY/steamapps/compatdata/578330/`

## What Was Broken
- Game stopped working after a kernel update (6.14 → 6.17) and/or Mesa 25.2.8 update
- Log showed repeated `RtlpWaitForCriticalSection` deadlocks (audio thread) then crash
- Root cause: game was running on Intel Vulkan (Mesa) instead of NVIDIA — missing `__VK_LAYER_NV_optimus=NVIDIA_only` in launch options
- `nvidia-prime` package was in `rc` (removed) state — no `prime-run` available

## What Was Fixed (2026-04-06)
### ✅ Done
1. **Steam launch options updated** in:
   `$HOME/.local/share/Steam/userdata/55676049/config/localconfig.vdf`

   **New launch options:**
   ```
   __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia PULSE_LATENCY_MSEC=60 PROTON_LOG=1 %command%
   ```
   Key additions vs before:
   - `__VK_LAYER_NV_optimus=NVIDIA_only` — forces DXVK/Vulkan to use NVIDIA GPU (was missing!)
   - `PULSE_LATENCY_MSEC=60` — fixes audio thread deadlock (later raised to 120, see below)

2. **Proton 3.7 confirmed** as the selected compatibility tool in:
   `$HOME/.local/share/Steam/config/config.vdf` (already set to `proton_37`)

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
   `$STEAM_LIBRARY/steamapps/appmanifest_420161.acf`
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
mv $STEAM_LIBRARY/steamapps/compatdata/578330 \
   $STEAM_LIBRARY/steamapps/compatdata/578330.bak-ge-proton
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

## Third Incident (2026-04-12) — Freeze at Chapter 15 Moon Transition

**Symptom**: Game freezes at a specific, reproducible trigger in Chapter 15 "Far Above the
Call of Duty": stepping into the shield on top of the tower that transitions the player to
the moon. Hard freeze — must kill the process.

**Root cause**: Two concurrent problems, confirmed from `~/steam-578330.log`:

1. **Audio thread deadlock** (`RtlpWaitForCriticalSection`) — same deadlock pattern as before,
   but triggered earlier and harder at this heavy scene-load event. Threads 0x39/0x3a/0x3b/0x3c
   block waiting for a PulseAudio critical section held by thread 0x39; after 60 s timeouts
   chain, the main thread (0x25) crashes with a page fault.
   `PULSE_LATENCY_MSEC=120` was insufficient for this scene's audio load.

2. **Explicit Vulkan ICD not set** — `__VK_LAYER_NV_optimus=NVIDIA_only` routes Vulkan through
   the Optimus layer but does not explicitly pin the ICD file. Adding
   `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json` removes any ambiguity about
   which Vulkan driver loads.

Note: SHANWAN deadzone (flatness 4096) was verified as active before the session —
not a contributor this time.

**Fix applied (2026-04-12)**:

Updated launch options — two changes:
- `PULSE_LATENCY_MSEC` raised from 120 → **240** (doubles audio buffer for heavy scene transitions)
- Added `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json` (explicit NVIDIA ICD)

```
__NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json PULSE_LATENCY_MSEC=240 PROTON_NO_ESYNC=1 PROTON_NO_FSYNC=1 PROTON_LOG=1 %command%
```

**Community research note (2026-04-12)**: The exact Chapter 15 freeze is unreported publicly,
but it is the same class of bug as confirmed level-transition crashes at the museum (Ch.10),
sewer, dojo, and "Dirty Work" scenes. The most widely confirmed community workaround for that
class is **lowering resolution to 1280×720 before entering the transition marker**, reported
working across PC, Steam Deck, and Xbox. Sources: Steam Community threads 1319961618831079047
and 3489752656793261208. Active controller input at transition markers was also independently
confirmed to trigger identical hangs on Steam Deck.

**✅ RESOLVED (2026-04-12)** — adding `WINEDLLOVERRIDES="xaudio2_7=n,b"` to launch options
fixed the freeze. Confirmed by reconnecting the SHANWAN controller after the transition
succeeded — it loaded correctly, proving the controller was not a factor. Root cause was
purely the XAudio2 threading deadlock in Proton 3.7's built-in XAudio2 implementation;
the override routes to Wine's own stub, bypassing the deadlock.

---

## Current Working Configuration (2026-04-12 rev 3)

### Launch options
File: `~/.local/share/Steam/userdata/55676049/config/localconfig.vdf`
Search for app `578330` → `"LaunchOptions"` key.

```
__NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json PULSE_LATENCY_MSEC=240 PROTON_NO_ESYNC=1 PROTON_NO_FSYNC=1 WINEDLLOVERRIDES="xaudio2_7=n,b" PROTON_LOG=1 %command%
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
`$STEAM_LIBRARY/steamapps/appmanifest_420161.acf`

If missing, recreate it:
```bash
cat > $STEAM_LIBRARY/steamapps/appmanifest_420161.acf << 'EOF'
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
| `$STEAM_LIBRARY/steamapps/appmanifest_420161.acf` | Proton 3.7-8 install manifest |
| `$STEAM_LIBRARY/steamapps/compatdata/578330/` | Wine prefix (delete to reset) |
| `/etc/udev/rules.d/99-shanwan-controller.rules` | SHANWAN deadzone/fuzz rule |
| `~/shanwan-udev-setup.sh` | Script to install the udev rule (run with sudo) |
| `/usr/share/vulkan/icd.d/nvidia_icd.json` | NVIDIA Vulkan ICD |
| `/etc/default/grub` | GRUB boot config |
