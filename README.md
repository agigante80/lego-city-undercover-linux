# LEGO City Undercover – Linux / Steam / Proton Fix Notes

Fix log and configuration for running **LEGO City Undercover** (Steam App ID 578330)
on Linux with Steam/Proton on an NVIDIA Optimus laptop.

The game has several failure modes on Linux that are non-obvious to diagnose. This repo
documents every crash encountered, what caused it, and what fixed it — including a
late-game freeze at the Chapter 15 moon transition that is not reported anywhere else online.

## Path conventions used in this guide

| Variable | Meaning | Typical value |
|----------|---------|---------------|
| `$HOME` | Your home directory | `/home/<youruser>` |
| `$STEAM_LIBRARY` | Path to your Steam library | Find it in Steam → Settings → Storage. Default if you haven't added a library: `$HOME/.local/share/Steam` |

Commands that reference these variables can be run as-is in any shell where they are set,
or substitute your actual paths.

---

## Hardware this was tested on

| Component | Value |
|-----------|-------|
| Machine | [redacted] 17 R4 |
| OS | Ubuntu 24.04.4 LTS (Noble Numbat) |
| Desktop | GNOME 46.0 on X11 |
| Display 1 (internal) | Laptop panel — 2560×1440 (eDP-1, panel capable of 3840×2160) |
| Display 2 (external) | Samsung S34C65xU, 34" ultrawide — 3440×1440 @ 60 Hz (DP-1) |
| Kernel | 6.17.0-20-generic (HWE, based on upstream 6.17.13) |
| GPU (render) | NVIDIA GeForce GTX 1070 (Mobile), 8 GB VRAM |
| GPU (display) | Intel HD Graphics 530 (Skylake GT2, Optimus) |
| NVIDIA driver | `535.288.01-0ubuntu0.24.04.3` (`nvidia-driver-535-server`) |
| Mesa | `25.2.8-0ubuntu0.24.04.1` |
| Proton version | **3.7-8** (required — newer versions break the game) |
| Controller | SHANWAN Xbox360 clone (USB 045e:028e, spoofs Microsoft VID:PID) |

---

## Working launch options

```
__NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json PULSE_LATENCY_MSEC=240 PROTON_NO_ESYNC=1 PROTON_NO_FSYNC=1 WINEDLLOVERRIDES="xaudio2_7=n,b" PROTON_LOG=1 %command%
```

### Option A — Set via Steam (easiest)

1. Open Steam and go to your Library
2. Right-click **LEGO City Undercover** → **Properties**
3. In the **General** tab, find the **Launch Options** field at the bottom
4. Paste the full string above and close the window — Steam saves it automatically
5. Relaunch the game

> Changes made via the Steam UI take effect immediately on the next launch.
> No restart required.

### Option B — Edit the config file directly

The launch options are stored in:
```
~/.local/share/Steam/userdata/<your-steam-userid>/config/localconfig.vdf
```

Find the section for app `578330` and update the `"LaunchOptions"` key.

> ⚠️ **Steam overwrites this file when it exits.** You must kill Steam before editing,
> or your changes will be lost.

```bash
# 1. Kill Steam fully
pkill -f steam

# 2. Edit the file — search for 578330, then find "LaunchOptions" nearby
nano ~/.local/share/Steam/userdata/*/config/localconfig.vdf

# 3. Save, then start Steam normally — it will read your updated options
```

### Why each option is needed

| Option | Reason |
|--------|--------|
| `__NV_PRIME_RENDER_OFFLOAD=1` + `__VK_LAYER_NV_optimus=NVIDIA_only` + `__GLX_VENDOR_LIBRARY_NAME=nvidia` | Forces rendering on the NVIDIA GPU (Optimus). Without these the game runs on Intel and deadlocks. |
| `VK_ICD_FILENAMES=…/nvidia_icd.json` | Explicitly pins the NVIDIA Vulkan ICD — belt-and-suspenders for the above. |
| `PULSE_LATENCY_MSEC=240` | Raises the PulseAudio buffer. Without this, audio threads deadlock (`RtlpWaitForCriticalSection`) at heavy scene loads. |
| `PROTON_NO_ESYNC=1 PROTON_NO_FSYNC=1` | FSYNC is confirmed to crash the game on cutscenes (Proton issue #1961). |
| `WINEDLLOVERRIDES="xaudio2_7=n,b"` | Routes XAudio2 through Wine's own stub instead of Proton 3.7's buggy implementation. Required to get past the Chapter 15 moon transition. |
| `PROTON_LOG=1` | Writes `~/steam-578330.log` for diagnosing crashes. Remove once stable. |

---

## In-game resolution

Set the in-game resolution to **1280×720** (Options → Display → Screen Resolution).
This is the community-confirmed workaround for level-transition freezes in this game —
particularly important on dual-monitor setups with high-resolution displays.

The game stores this in:
```
<wine-prefix>/pfx/drive_c/users/steamuser/AppData/Roaming/Warner Bros. Interactive Entertainment/LEGO City Undercover/pcconfig.txt
```
(`ScreenWidth 1280`, `ScreenHeight 720`)

---

## Proton version

**Proton 3.7-8 is required.** Newer versions (GE-Proton, Proton 8+) cause immediate page
faults on launch. This is a known fragility of this port.

### Option A — Set via Steam (easiest)

1. Right-click **LEGO City Undercover** → **Properties**
2. Go to the **Compatibility** tab
3. Tick **Force the use of a specific Steam Play compatibility tool**
4. Select **Proton 3.7-8** from the dropdown
5. Close the window — Steam saves it automatically
6. **Restart Steam** for the change to take effect reliably

> If Proton 3.7-8 doesn't appear in the dropdown, it may not be installed.
> Install it via Steam → Settings → Steam Play → check that compatibility tools are enabled,
> or search for "Proton 3.7" in your Library.

### Option B — Edit the config file directly

The Proton version mapping is stored in:
```
~/.local/share/Steam/config/config.vdf
```

Find the `CompatToolMapping` section, locate app `578330`, and set `"name"` to `"proton_37"`.

> ⚠️ **Kill Steam before editing this file**, then restart Steam after saving.

```bash
pkill -f steam
nano ~/.local/share/Steam/config/config.vdf
# Search (Ctrl+W) for: 578330
# Set "name" to "proton_37"
# Save (Ctrl+O), exit (Ctrl+X), then restart Steam
```

### Proton 3.7-8 install manifest

The file below must exist or Steam silently falls back to a different Proton version:
```
<steam-library>/steamapps/appmanifest_420161.acf
```
If it goes missing, the game won't start and the log will be empty or show a page fault.
See [`lego-city-undercover-linux-fix.md`](lego-city-undercover-linux-fix.md) for how to
recreate it.

---

## SHANWAN Xbox360 controller fix

A SHANWAN Xbox360 clone controller (`045e:028e`, manufacturer string `"SHANWAN"`) floods
Wine's HID report queue with noisy analog axis events, adding thread pressure that can
contribute to audio deadlocks.

**Install once — never needs to be run again (requires `sudo apt install joystick` first):**
```bash
sudo ./shanwan-udev-setup.sh
```

This installs `/etc/udev/rules.d/99-shanwan-controller.rules`. After that, nothing more is
needed before each gaming session — udev automatically re-applies the deadzone:
- Every time the controller is plugged in
- On boot, if the controller is already connected

The deadzone is a runtime kernel parameter that resets when the device is removed, but the
udev rule resets it back every time the device is added.

**If you suspect it stopped working**, verify with:
```bash
evdev-joystick --showcal /dev/input/event23
# X/Y/RX/RY should show flatness: 4096 (=12.50%)
# If it shows 128, unplug and replug the controller — the rule should re-apply it
```

---

## Error log signatures

If you found this page by searching for one of these errors, here is what caused it and
where to find the fix in this repo.

**Game won't launch — wrong Proton version loaded (manifest missing)**
```
Unhandled exception: page fault on read access to 0x000000000000000c
err:service:device_notify_proc failed to get event, error 1726
```
→ `appmanifest_420161.acf` is missing. Steam silently fell back to an incompatible Proton
version. See [Second Incident](lego-city-undercover-linux-fix.md) in the fix log.

**Game won't launch — empty log file (`~/steam-578330.log` is 0 bytes)**
```
(log file is empty or not created)
```
→ Either the Proton manifest is missing (see above) or the Wine prefix was initialised by a
different Proton version. Check `compatdata/578330/version`. See fix log for both cases.

**Game crashes mid-session — audio thread deadlock**
```
err:ntdll:RtlpWaitForCriticalSection section 0x... "?" wait timed out in thread 003a, blocked by 0039, retrying (60 sec)
err:ntdll:RtlLeaveCriticalSection section 0x... is not acquired
wine: Unhandled page fault on read access to 0x0000000c at address 0x7bc45cbe
```
→ PulseAudio / XAudio2 threading deadlock. Fixed by `PULSE_LATENCY_MSEC=240`,
`PROTON_NO_ESYNC=1 PROTON_NO_FSYNC=1`, and `WINEDLLOVERRIDES="xaudio2_7=n,b"`.

**Game freezes at a specific scene (Chapter 15 moon transition, or museum / sewer / dojo)**
→ Same audio deadlock triggered by the heavy scene load. The `xaudio2_7=n,b` override is the
confirmed fix for the Chapter 15 moon transition specifically.

**Controller input causes HID report flooding**
```
err:hid_report:process_hid_report Device reports coming in too fast, last report not read yet!
```
→ Noisy analog axes on the SHANWAN Xbox360 clone. Fixed by the udev deadzone rule in this
repo. See [SHANWAN controller fix](#shanwan-xbox360-controller-fix) above.

**Game running on Intel GPU instead of NVIDIA**
```
(in DXVK log: Device: Intel(R) HD Graphics 530)
```
→ Optimus environment variables missing or `VK_ICD_FILENAMES` not set. Check launch options.

---

## Quick crash diagnosis

```bash
# 1. Check which Proton actually ran (wrong version = wrong prefix)
cat $STEAM_LIBRARY/steamapps/compatdata/578330/version

# 2. Check the game log for errors
tail -80 ~/steam-578330.log | grep -i "err:\|exception\|fault\|deadlock"

# 3. Confirm NVIDIA is rendering (add temporarily to launch options)
#    DXVK_HUD=devinfo
#    Should show "GeForce GTX 1070", not "Intel HD 530"

# 4. Verify launch options survived a Steam restart
grep LaunchOptions ~/.local/share/Steam/userdata/*/config/localconfig.vdf
```

---

## Known failure modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Game won't start, log is empty | Proton 3.7-8 manifest missing | Recreate `appmanifest_420161.acf` |
| Game won't start, log is empty | Wine prefix created by wrong Proton version | Delete/rename `compatdata/578330/` and let it rebuild |
| Audio deadlock crash mid-session | `PULSE_LATENCY_MSEC` too low or FSYNC enabled | Use options above |
| Game runs on Intel GPU | NVIDIA Optimus env vars missing or ineffective | Add `VK_ICD_FILENAMES` |
| Freeze at Chapter 15 moon transition | XAudio2 threading bug in Proton 3.7 | `WINEDLLOVERRIDES="xaudio2_7=n,b"` |

---

## Full incident log

See [`lego-city-undercover-linux-fix.md`](lego-city-undercover-linux-fix.md) for the complete
chronological record of every crash, root cause analysis, and fix applied.

---

## Repo contents

| File | Purpose |
|------|---------|
| `lego-city-undercover-linux-fix.md` | Full incident log |
| `shanwan-udev-setup.sh` | Install script for the SHANWAN udev rule |
| `udev/99-shanwan-controller.rules` | The udev rule itself |

## Sponsor

I build and maintain this in my own time. It is free, it stays free, and it gets maintained either way.

If it saved you some time and you feel like saying thanks, you can do that at [github.com/sponsors/agigante80](https://github.com/sponsors/agigante80). Entirely optional, and nothing about the project changes either way.
