# FF Mobile Optimizer — සිංහල Guide

> **PC එකකින් USB/WiFi ADB හරහා ඔයාගේ Android phone එකේ Free Fire performance එක වැඩි කරන tool එකක්.**
> Root **ඕන නෑ** · Game එකට කිසිම විදිහකින් touch කරන්නේ නෑ · **100% reversible** (menu `6` එකෙන් ආපහු)

🗂️ Repo එකේ ගොනු:

| ගොනුව | මොකක්ද |
|---|---|
| **`src/FF Mobile Optimizer.bat`** | **මේක double-click කරන්න** |
| `src/FFMobileOptimizer.ps1` | Tool එකේ code එක |
| `docs/PHONE-ONLY-GUIDE.md` | PC එකක් නැතුව phone එකෙන්ම කරන විදිහ (LADB) |
| `examples/` | Scan + optimize output එකේ ඇත්ත samples, HTML report එකක් |
| `tests/` | Emulated phone එකක් එක්ක automatic test suite එක |

---

## ⚡ 1. ඉක්මනින් පටන් ගන්න (විනාඩි 3ක්)

**Phone එකේ:**
1. Settings → About phone → **Build number** එකට **7 වතාවක්** tap
2. Settings → System → **Developer options** → **USB debugging** = **ON**
3. USB cable එකෙන් PC එකට connect කරන්න → phone එකේ **File transfer / MTP** තෝරන්න
4. Phone එකේ එන **"Allow USB debugging?"** → **Allow** (+ "Always allow" ✓)

**PC එකේ:**
5. `src/` folder එකේ ගොනු **දෙකම** එකම folder එකකට copy කරගන්න → **`FF Mobile Optimizer.bat`** එකට double-click
6. Menu එකෙන් **`1`** (connect) → **`2`** (scan) → **`3`** (Safe optimize) → `y`

> PC එකේ `adb` නැත්නම්, tool එක **Google එකේම official platform-tools** auto download කරගන්නවා (~9MB).

**ඊට පස්සේ:** game එක **restart** කරන්න → **cable එක ගලවන්න** → නිදහසේ ගහන්න 🎮

> ⚠️ Game එක ගහන අතරේ cable එක දාගෙන ඉන්න එපා — **charge වෙනවා → රත් වෙනවා → FPS බහිනවා**.

---

## 🖥️ 2. Menu එකේ විස්තරය

```
   1) Connect / reconnect phone
   2) Scan        - මොනවත් වෙනස් නොකර බලන්න
   3) Optimize    - Safe profile (recommended)
   4) Optimize    - Full profile (තව FPS, phone රත් වෙනවා)
   5) Optimize    - Custom (ඔයාම තෝරන්න)
   6) Restore     - ඔක්කොම ආපහු හරවන්න
   7) Measure     - temperature / thermal / frame stats
   8) Remove bloat apps (reversible, opt-in)
   9) Reset screen size/density to native
  10) Phone-only commands (LADB / Shizuku)
  11) Open backup + report folder
   0) Exit
```

Boost කරන්න කලින් tool එක **plan එක පෙන්නලා අවසරය අහනවා** — `y` නැත්නම් කිසිම දෙයක් වෙන්නේ නෑ.

---

## 🔧 3. මොනවද වෙනස් වෙන්නේ?

### 🟢 Safe profile

| Tweak | බලපෑම | කරන දේ |
|---|---|---|
| **Per-game performance mode** | FPS | `cmd game mode performance` — Android GameManager එකෙන් game එකට priority |
| **Game resolution downscale** | FPS | `cmd game downscale 0.75` — **game එකට විතරක්** 75% pixels |
| **Animation scales off** | Latency | Menus snappier |
| **AOT compile game** | Stutter | `cmd package compile -m speed` — loading/stutter අඩු |
| **Background Wi-Fi scanning off** | Ping | Jitter අඩු |
| **Stop background apps** | RAM/FPS | 3rd-party apps force-stop |
| **Touch response latency** | Aim | `long_press_timeout` + `multi_press_timeout` → 250ms |

### 🟡 Full profile (අමතරව)

| Tweak | අවවාදය |
|---|---|
| **Restrict heavy bloat apps** | Facebook/Netflix වගේ apps වල background activity block (`appops`) |
| **Fixed performance mode** | Clocks pin කරනවා → **phone එක රත් වෙනවා**. ඒක *consistency* එකක්, max speed එකක් නෙවෙයි |

### 🔵 Custom එකේ විතරක් (අවදානම වැඩි)

| Tweak | අවවාදය |
|---|---|
| **Remove bloat apps** | `pm uninstall --user 0` — **සම්පූර්ණයෙන් reversible** |
| **Lower screen resolution** | `wm size`/`wm density` 75% — මුළු phone එකටම බලපානවා. Fingerprint sensor එක වැඩ නොකරන්නත් පුළුවන් |
| **ANGLE GLES driver** 🧪 | Game එක ANGLE (GLES→Vulkan) driver එකෙන් render කරනවා. **Device එක අනුව FPS වැඩි වෙන්නත් අඩු වෙන්නත් පුළුවන්** — ඒ නිසා `-Angle` flag එකෙන් විතරයි enable වෙන්නේ, measure කරලා බලන්න ඕන |

> ❌ **අපි හිතාමතාම නොදාපු දේවල්:** `debug.hwui.renderer` (Skia GL — ඒක **Android UI එකට විතරයි**, game එකට නෙවෙයි) සහ fake touch-sampling props (**sampling rate = hardware**, ADB එකෙන් බෑ). ඒවා placebo, ඒ නිසා දාන්නේ නෑ.

---

## 📊 4. Score + Measure ගැන ඇත්ත

- **Score** = core tweaks 8කින් කීයක් optimal ද (0-100%)
- **Temperature** (`dumpsys battery`) සහ **thermal state** (`dumpsys thermalservice`) — **නිවැරදි**
- **FPS + jank %** (`dumpsys gfxinfo`) — **estimate එකක්**. Android එකේ "දැන් FPS කීයද" කියන public API එකක් නෑ

**හොඳම before/after test:** match එකක් ගහන්න → `7) Measure` → optimize → game restart → ආයෙත් match → `7) Measure`.

---

## ↩️ 5. Undo — හැම වෙලාවෙම තියෙනවා

```
%LOCALAPPDATA%\FFMobileOptimizer\pending-<serial>.json
```

- **Menu `6) Restore`** — Safe + Full + Custom ඔක්කොම එකට undo කරනවා
- නැත්නම්: `.\FFMobileOptimizer.ps1 -Mode Restore`
- Restore එකට පස්සේ **phone එක reboot** කරන්න

> **Reboot එකෙන් undo වෙන්නේ නෑ!** Android settings database එකක තියෙන නිසා reboot එකෙන් රැකෙනවා (animations, game mode/downscale, appops, `pm uninstall --user 0`, `wm size` ඔක්කොම). ආපහු හරවන්න **Restore** එක තමයි තියෙන්නේ. ඒ `pending-*.json` file එක **මකන්න එපා** — ඒකයි ඔයාගේ undo එක.

---

## 🎮 6. Game ඇතුළේ settings (මේක නැතුව අනිත් ඒවා අඩක් wasted)

| Setting | අගය |
|---|---|
| Graphics quality | **Smooth** |
| Frame rate | **High** |
| Auto-adjust graphics | **OFF** |
| Shadows / Anti-aliasing | **OFF** |
| High-quality audio | **OFF** |
| Display | Phone settings → **High/120Hz** + app-specific refresh rate |

**හැමෝටම වඩා වැදගත්:** 🔥 **Heat control** — charge නොකර ගහන්න, case එක ගලවන්න, battery 15-20% ඉතුරු කරන්න.

---

## 🧊 7. Ban risk ගැන අවංකව

මේ tool එක game එකට **කිසිම විදිහකින්** touch කරන්නේ නෑ — injection නෑ, memory access නෑ, file modify නෑ, modified APK නෑ. Android එකේ **documented APIs** විතරයි (`cmd game`, `device_config`, `settings`, `appops`) — OEM Game Boosters භාවිතා කරන ඒවාම.

ඒත් **කවුරුත් 100% guarantee එකක් දෙන්න බෑ** — Garena එකේ rules හිතාමතාම පුළුල්, anti-cheat internal, false positives තියෙනවා. Account එකේ වටිනා දේවල් තියෙනවා නම් ඒක හිතලා තීරණය කරන්න.

---

## ⌨️ 8. Command line

```powershell
.\FFMobileOptimizer.ps1 -Mode Scan
.\FFMobileOptimizer.ps1 -Mode Optimize -Profile Safe
.\FFMobileOptimizer.ps1 -Mode Optimize -Profile Full -DryRun      # මොනවද වෙන්නේ කියලා විතරයි
.\FFMobileOptimizer.ps1 -Mode Optimize -Profile Full -Angle       # + ANGLE (experimental)
.\FFMobileOptimizer.ps1 -Mode Optimize -Profile Custom -Tweaks "GameMode,Downscale" -Downscale 0.6
.\FFMobileOptimizer.ps1 -Mode Measure
.\FFMobileOptimizer.ps1 -Mode Restore
.\FFMobileOptimizer.ps1 -Mode PhoneGuide
```

---

## 🧰 9. Troubleshooting

| ප්‍රශ්නය | විසඳුම |
|---|---|
| "No phone detected" | USB debugging ON ද, cable එක **data cable** එකක් ද, popup එකට Allow කළා ද බලන්න |
| "unauthorized" | Phone screen unlock කරලා popup එක accept කරන්න |
| `adb` නැහැ | Tool එකම download කරන්න අහනවා → `y` |
| WiFi එකෙන් ඕන | Wireless debugging ON → `-Wireless` flag එකෙන් run කරලා IP:port දෙන්න |
| වෙනසක් නෑ | (1) game එක **restart** කරන්න (2) OEM Game Mode එකෙනුත් Free Fire එකට performance දෙන්න (3) phone reboot |
| සමහර phones වල `cmd game` වැඩ නෑ | සමහර OEM (පරණ Huawei/Xiaomi) Android GameManager block කරලා. අනිත් tweaks වැඩ කරනවා |
| Screen zoom වුණා | Menu `9` එකෙන් reset කරන්න |

---

## 🧪 10. Test කරන්න (PC එකේ, phone එකක් නැතුව)

```bash
bash tests/run-tests.sh
```

Emulated Redmi Note 12 Pro එකක් එක්ක checks **44ක්** run වෙනවා — profiles ඔක්කොම, `-Angle` opt-in, dry-run safety, **Restore round-trip** (device එක byte-level පරණ තත්ත්වයට එනවද කියලා), bloat reversibility, error handling. CI එකේත් run වෙනවා.

---

*MIT License · Garena එකට සම්බන්ධ නෑ · GLHF! 🎮*
