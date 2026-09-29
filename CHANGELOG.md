# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-09-29

### Added
- **Game-focus tweaks** — the phone now keeps the game alive and unrestricted while you play:
  - **Battery-optimization exemption** (`dumpsys deviceidle whitelist +pkg`) — Android no longer
    freezes the game in the background. Restored with `-pkg`.
  - **ACTIVE standby bucket** (`am set-standby-bucket pkg 10`) — no background restrictions.
    Restore puts the exact previous bucket back (`am reset-standby-bucket` when unknown).
  - **Battery saver off while gaming** (`low_power 0`) — only changes anything if battery saver
    was on; the previous value is restored afterwards.
  All three sit in the **Full** profile (Safe is unchanged).
- **Refresh-rate lock** (opt-in, Custom only): `min_refresh_rate` / `peak_refresh_rate` set to the
  display's peak (read from `dumpsys display`). Honest note in the plan step: **some phones ignore
  it** (device-dependent). Fully restored/deleted by `Restore`.
- New `SystemSetting` change kind in the backup format, plus `Set-TrackedSystem` tracking helper.
- Phone-only guide blocks for the three game-focus commands and the refresh-rate lock (with undo).

### Changed
- Score denominator: **12 core tweaks** (was 8) — the four new tweaks are counted.
- Regression suite grew from 44 to **58 checks**, including a byte-for-byte restore check that now
  covers the new tweak kinds, and a new T13 group for the refresh-rate lock.

### Not added (deliberately)
- **Thermal override** (`cmd thermalservice override-status 0`) — no monitoring, so it stays out.
- **Boost & Launch** menu — out of scope for this release.

## [1.1.0] - 2026-09-29

### Added
- **Touch response latency** tweak (`long_press_timeout`, `multi_press_timeout` → 250 ms), part of
  the *Safe* profile.
- **ANGLE renderer** (experimental, opt-in via `-Angle`): routes the game package through Google's
  ANGLE GLES→Vulkan driver (`angle_gl_driver_selection_pkgs` / `_values`). Appends to any existing
  ANGLE list instead of overwriting it, warns during the plan step, and is fully restored by
  `Restore`.
- `-Tweaks` parameter so `Custom` profiles can be driven from the command line, plus a printed list
  of valid tweak ids when a selection is empty.
- Phone-only guide blocks for the touch tweak and the ANGLE driver (including undo).
- Full regression suite with an **emulated Android device** (`tests/fake-adb`), runnable on
  Linux/macOS/CI without a phone — 44 checks.

### Changed
- Score now counts 8 core tweaks (was 6) — safer/moderate tweaks, advanced ones stay informational.
- `pending-<serial>.json` accumulates every change since the last restore, so a single `Restore`
  also undoes earlier runs; the log is cleared when the device is fully reverted.

### Fixed
- PowerShell 5.1 compatibility: no inline `if` expressions in parameter position.
- `devices` parsing now accepts trailing `adb devices` transport columns (real adb output).
- `cmd power set-fixed-performance-mode-enabled` without a readback is reported as
  *unverifiable* instead of being shown as disabled.
- Restore reports newly created values as `removed` and deletes them (was: tried to write them).

### Documented
- Reboot behaviour table: which settings survive a restart and which do not.
- Explicitly *not* implemented, with reasons: `debug.hwui.renderer` (Android UI only, not games)
  and fake touch-sampling props (hardware feature).
- Known limitations and an honest statement about ban risk.

## [1.0.0] - 2026-09-28

### Added
- Initial release: `Scan`, `Safe`/`Full`/`Custom` profiles, `Measure`, `Restore`, `Report`,
  `PhoneGuide`, `Doctor`.
- Tweaks: per-game performance mode, game resolution downscale, animation scales, AOT compile,
  background Wi-Fi scanning, background app stopping, bloat app restriction, fixed performance mode,
  bloat removal, screen resolution override.
- Backup + restore model: every change stored with its previous value, `pending-<serial>.json` undo
  log, HTML report per run.
- Interactive menu launcher (`FF Mobile Optimizer.bat`) and phone-only guide for LADB/Shizuku users.
