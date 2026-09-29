# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
