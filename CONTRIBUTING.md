# Contributing

Thanks for wanting to improve this project. A few ground rules keep it trustworthy.

## What is welcome

- 🐛 **Bug reports** with the exact output text (and your Android version + phone model)
- 📱 **Vendor compatibility notes** — which OEMs block `cmd game`, `cmd package compile`, `appops`, etc.
- 🔧 **New tweaks** that are:
  1. based on a **documented Android/ADB API** (link the docs or AOSP source in the PR),
  2. **reversible** — they must record the previous value through the existing change-tracking helpers,
  3. **testable** in `tests/fake-adb` (add the shim support + a check in `tests/run-tests.sh`).
- 🌍 **Translations** of `docs/README.si.md` / `docs/PHONE-ONLY-GUIDE.md` into other languages
- 📝 **Documentation fixes** — especially if you found a claim that turned out to be wrong

## What will be rejected

- ❌ Anything that touches the game client: memory editing, injection, hooks, patched APKs,
  modified game assets, "FPS unlockers" — these carry a ban risk for users
- ❌ Root-only tricks presented as non-root ones
- ❌ Tweaks with no verifiable mechanism ("+300% FPS", "AI boost", unverifiable prop writes)
- ❌ Anything that removes the undo path

When in doubt, open an issue first and we can talk about the mechanism before you write code.

## Development

```bash
# requirements: pwsh (PowerShell 7+) and python3
git clone https://github.com/tharukanavod12345678-dev/free-fire-optimizer.git
cd ff-mobile-optimizer

# run the whole suite against the emulated Android device
bash tests/run-tests.sh

# lint (same rules as CI)
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path src/FFMobileOptimizer.ps1 -Severity Error"
```

The suite must be green before a PR is merged. If you add a tweak, extend both
`tests/fake-adb/adb.py` (so the emulated device can store it) and `tests/run-tests.sh`
(so the round-trip Restore is verified).

## Code style

- PowerShell 5.1 compatible (no `??`, no ternary, no inline `if` in parameter position)
- Every new tweak has: a table entry, a `Test-Tweak` case, an `Invoke-Tweak` case,
  a `Restore` case, and an entry in the phone-only guide
- Keep the honest tone: if a tweak helps only some devices, say so in the docs

## Commit messages

Short imperative subject, then *why* in the body if it isn't obvious. Examples:

```
Add ANGLE renderer tweak (experimental, opt-in)

Routed through Google's documented angle_gl_driver_selection_* settings.
Appends to existing lists instead of overwriting, and Restore deletes the
keys when they were not set before.
```
