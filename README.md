# FF Mobile Optimizer

**A Free Fire performance optimizer for Android — driven from your PC over ADB. No root. Fully reversible.**

[![CI](https://github.com/tharukanavod12345678-dev/free-fire-optimizer/actions/workflows/ci.yml/badge.svg)](https://github.com/tharukanavod12345678-dev/free-fire-optimizer/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6.svg)](#requirements)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE.svg)](#requirements)
[![Android 12+](https://img.shields.io/badge/Android-12%2B%20(SDK%2031%2B)-3DDC84.svg)](#requirements)

> Also available: **[සිංහල guide](docs/README.si.md)**

---

## What this is

A PowerShell tool that connects to your Android phone over ADB (USB or Wi-Fi) and applies
**real, measurable Android-level optimizations** for Free Fire:

| Tweak | What it does |
|---|---|
| **Per-game performance mode** | `cmd game mode performance` — Android's GameManager gives the game CPU/GPU priority |
| **Game resolution downscale** | `cmd game downscale 0.75` — renders the **game only** at 75% of the pixels. Your phone UI stays sharp |
| **Animation scales off** | Snappier menus, less CPU spent on compositing |
| **AOT compile** | `cmd package compile -m speed` — fewer stutters, faster loads |
| **Background Wi-Fi scanning off** | Less network jitter → more stable ping |
| **Background apps stopped** | More RAM and CPU left for the game |
| **Touch response latency** | Lower long-press / multi-tap timeouts |
| **Bloat app restriction** *(Full)* | `appops` deny on Facebook/Netflix/LinkedIn-style background hogs |
| **Fixed performance mode** *(Full)* | Stable clocks — note: this is *consistency*, not raw speed |
| **Bloat removal** *(Custom, opt-in)* | `pm uninstall --user 0` — reversible from the tool or Play Store |
| **Screen resolution override** *(Custom, opt-in)* | `wm size` / `wm density`, with one-command reset |
| **ANGLE renderer** *(Experimental, opt-in)* | Route the game through Google's ANGLE GLES→Vulkan driver. **Measure before/after — it can help or hurt** |

### What it deliberately does *not* do

- ❌ **No cheats.** No aimbot, no memory editing, no injection, no modified APK, no game file edits.
  The tool only touches Android settings — the game itself is never touched, so there is nothing for
  anti-cheat to detect in the game.
- ❌ **No kernel/root tricks.** No governors, no overclocking, no thermal-policy hacks by default.
- ❌ **No snake oil.** We skip `debug.hwui.renderer` (it only affects Android UI, *not* games) and
  fake "touch sampling rate" props (sampling rate is a hardware feature; ADB can't raise it).

---

## Requirements

| | |
|---|---|
| **PC** | Windows 10 / 11, PowerShell 5.1 or 7+ *(no admin rights needed on the PC)* |
| **Phone** | Android **12+** (SDK 31+), Free Fire `com.dts.freefireth` and/or Free Fire MAX `com.dts.freefiremax` |
| **Cable / link** | A USB **data** cable, or Wi-Fi ADB (wireless debugging) |
| **adb** | Auto-downloaded from Google's official platform-tools if missing (or bring your own with `-AdbPath`) |

---

## Quick start (5 minutes)

### 1. Prepare the phone

1. Settings → **About phone** → tap **Build number** 7 times
2. Settings → System → **Developer options** → **USB debugging** = ON
3. Plug in the USB cable → choose **File transfer / MTP** on the phone
4. Accept the **"Allow USB debugging?"** popup (tick *Always allow*)

### 2. Prepare the PC

Download `src/FFMobileOptimizer.ps1` and `src/FF Mobile Optimizer.bat` into the **same folder**.

> If Windows blocked the download: right-click the `.ps1` → **Properties** → **Unblock**.

### 3. Run it

**Double-click `FF Mobile Optimizer.bat`**, then:

```
1) Connect / reconnect phone
2) Scan        - see what is not optimized (change nothing)
3) Optimize    - Safe profile (recommended)
```

Review the plan it prints, answer `y`, and you're done.

### 4. Play

Close Free Fire first (the tool warns you if it's running), let it apply, **restart the game**,
then **unplug the cable** and play. USB charging heats the phone — and heat is the #1 cause of FPS drops.

---

## Undo — always available

Every change is recorded **with its previous value** before it is made:

```
%LOCALAPPDATA%\FFMobileOptimizer\pending-<serial>.json
```

- **Menu → `6) Restore`** undoes *everything* you have applied since the last restore
  (Safe + Full + Custom runs combined), or:
- `.\FFMobileOptimizer.ps1 -Mode Restore`

Then reboot the phone so every setting is re-read. Don't delete that folder — it *is* your undo.

> **Rebooting does not undo anything.** Android settings live in a database and survive reboots
> (verified: animation scales, game mode/downscale, appops, `pm uninstall --user 0`, `wm size`).
> `Restore` is how you go back.

---

## Honest measurement

- **Battery temperature** (`dumpsys battery`) — accurate
- **Thermal throttling state** (`dumpsys thermalservice`) — accurate
- **FPS + janky-frame %** (`dumpsys gfxinfo`) — **best effort**

Android has no public "current FPS" API for games, so the FPS number is estimated from the frame
timings Android records for the game process. Temperature and thermal state are the reliable signals,
and they are what actually decide your **sustained** FPS.

**Best before/after test:** play a match → `Measure` → optimize → restart game → play a match → `Measure`.

---

## In-game settings that matter more than any optimizer

| Setting | Value |
|---|---|
| Graphics quality | **Smooth** |
| Frame rate | **High** (or the highest your phone supports) |
| Auto-adjust graphics | **OFF** |
| Shadows / Anti-aliasing | **OFF** |
| High-quality audio | **OFF** (less CPU, clearer footsteps) |
| Display | Phone settings → **High/120 Hz** + app-specific refresh rate for Free Fire |

And the biggest factor of all: **heat**. Don't play while charging, take the case off, keep 15–20%
battery free.

> Free Fire's official cap is 60 FPS (Normal 30 / Medium 45 / High 60). 90 FPS is being unlocked by
> Garena per phone model. Root "FPS unlocker" mods are a **ban risk** — this tool does not ship any.

---

## CLI reference

```powershell
.\FFMobileOptimizer.ps1                      # interactive menu
.\FFMobileOptimizer.ps1 -Mode Doctor         # environment check
.\FFMobileOptimizer.ps1 -Mode Scan
.\FFMobileOptimizer.ps1 -Mode Measure
.\FFMobileOptimizer.ps1 -Mode Optimize -Profile Safe
.\FFMobileOptimizer.ps1 -Mode Optimize -Profile Full -DryRun     # show the plan, change nothing
.\FFMobileOptimizer.ps1 -Mode Optimize -Profile Full -Force
.\FFMobileOptimizer.ps1 -Mode Optimize -Profile Full -Angle      # + experimental ANGLE renderer
.\FFMobileOptimizer.ps1 -Mode Optimize -Profile Custom -Tweaks "GameMode,Downscale" -Downscale 0.6
.\FFMobileOptimizer.ps1 -Mode Optimize -Wireless                 # asks for IP:port (wireless debugging)
.\FFMobileOptimizer.ps1 -Mode Restore
.\FFMobileOptimizer.ps1 -Mode Restore -BackupFile "C:\path\pending-XXX.json"
.\FFMobileOptimizer.ps1 -Mode PhoneGuide                         # commands for LADB / Shizuku users
```

| Parameter | Meaning |
|---|---|
| `-Mode` | `Menu` · `Scan` · `Optimize` · `Measure` · `Restore` · `PhoneGuide` · `Report` · `Doctor` |
| `-Profile` | `Safe` · `Full` · `Custom` |
| `-Tweaks` | ids for `Custom`: `GameMode, Downscale, Animations, Compile, WifiScan, KillApps, TouchResp, BgRestrict, FixedPerf, Angle, RemoveBloat, GlobalRes` |
| `-Downscale` | `1.0` = off · `0.75` = default · `0.5` = max FPS gain (slightly blurrier) |
| `-Angle` | 🧪 experimental — enable ANGLE for the game package |
| `-Serial` / `-Wireless` / `-AdbPath` | pick device · Wi-Fi ADB · use a specific adb binary |
| `-DryRun` / `-Force` / `-Simulate` | preview · skip confirmation · fake device for demos |

---

## No PC? Use the phone only

See **[docs/PHONE-ONLY-GUIDE.md](docs/PHONE-ONLY-GUIDE.md)** — the same commands, ready to paste into
**LADB** (or Shizuku + a terminal), including the undo block. The tool itself can also print them:
`-Mode PhoneGuide`.

---

## Testing

The whole tool is testable **without a phone** — `tests/fake-adb/` is a small Python shim that
emulates a Redmi Note 12 Pro on Android 13.

```bash
bash tests/run-tests.sh
```

```
==============================================================
  RESULT: 44 passed, 0 failed
==============================================================
```

It covers: script parsing, device detection, the scan/measure output, all three profiles, the
`-Angle` opt-in, dry-run safety, **one-restore-undoes-everything round-trip verified byte-for-byte
against a pristine device**, reversible bloat removal, custom downscale factors, the phone-only
guide, and error handling. Runs on Linux/macOS/CI (needs `pwsh` + `python3`).

---

## Limitations — read this

- 🆕 **Not tested on a real phone yet.** The logic is covered by the emulated-device suite, but vendor
  ROMs differ. If something fails on your device, please open an issue with the output text.
- 🧩 Some OEMs (older Huawei/Xiaomi builds) block Android's `cmd game` API. The rest of the tweaks
  still work; the tool reports per-tweak warnings.
- 🔒 No root features by design (governors, core pinning, kernel thermal). Those need root — and the
  "FPS unlocker" scene around them carries a ban risk.
- 📉 The gain is bounded by physics: weaker SoCs stay weaker. This tool removes *obstacles*, it does
  not add power.

### On ban risk — an honest note

This tool never interacts with the game: no injection, no memory access, no file modification, no
altered APK. It uses documented Android APIs (`cmd game`, `device_config`, `settings`, `appops`) —
the same mechanisms Android's own Game Dashboard and OEM game boosters use.

That said, **nobody can give a 100% guarantee**. Garena's rules are intentionally broad ("unauthorized
tools that interact with the game client"), anti-cheat systems are private, and bans can come from
false positives. If your account holds skins/rank you could not rebuild, weigh that before running
anything — including this. See [Garena's own ban policy](https://support-freefireind.garena.com/ind/articles/ind_account_ban).

---

## Repository layout

```
src/        FFMobileOptimizer.ps1 · FF Mobile Optimizer.bat
docs/       PHONE-ONLY-GUIDE.md · README.si.md (Sinhala)
examples/   real scan / optimize output + a sample HTML report
tests/      run-tests.sh · fake-adb/ (emulated device for CI)
```

## Contributing

Tweaks, bug reports and vendor compatibility notes are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).
Please don't open PRs that add cheats, root tricks, or unverifiable "performance boosters".

## License

[MIT](LICENSE) — do what you want, no warranty. Free Fire is a trademark of Garena; this project is
unofficial and not affiliated with or endorsed by Garena.
