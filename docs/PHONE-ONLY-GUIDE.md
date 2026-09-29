# Free Fire — Phone එකෙන් විතරක් Optimize කරන Guide (PC එකක් නැතුව)

> මේක **Android 12 හෝ අලුත්** phone එකකට. Root **ඕන නෑ**.
> PC tool එකේ run වෙන එකම commands ටික මෙතන ඔයාම copy-paste කරනවා විතරයි.

---

## 📱 1. මුලින්ම මොනවද ඕන

| දේ | විස්තරය |
|---|---|
| **LADB** app එකක් | "LADB — Local ADB Shell" (Play Store). Phone එකේම ADB shell එකක් run කරනවා |
| **හෝ** Shizuku + Terminal | Shizuku app + Termux වගේ terminal එකක් |
| Developer options | Settings → About phone → **Build number** එකට **7 වතාවක්** tap කරන්න |

**LADB setup:**
1. Settings → System → Developer options → **Wireless debugging** = ON
2. **Wireless debugging** එකට ගිහින් **Pair device with pairing code** → කේතයයි IP එකයි බලාගන්න
3. LADB app එක open කරලා ඒ IP එකයි pairing code එකයි දාන්න
4. දැන් ඔයාට `adb shell` එකක් තියෙනවා — පහල commands copy කරන්න

> ⚠️ Phone එක reboot කළොත් wireless debugging එක ආයෙත් on කරන්න වෙනවා.

---

## 🔍 2. මුලින්ම දැන් තත්ත්වය බලන්න (මොනවත් වෙනස් වෙන්නේ නෑ)

```
pkg=com.dts.freefireth

wm size ; wm density
settings get global window_animation_scale
device_config get game_overlay $pkg
dumpsys battery | grep temperature
dumpsys thermalservice | grep "Thermal Status"
```

**මතක තියාගන්න:** පළවෙනි පේළියේ එන resolution එකයි density එකයි (උදා: `1080x2400`, `395`) — පස්සේ ඕන වෙයි.

> `com.dts.freefireth` = **Free Fire**, `com.dts.freefiremax` = **Free Fire MAX**.
> ඔයා MAX ගහනවා නම් උඩ `pkg=com.dts.freefiremax` කරන්න.

---

## 🚀 3. Optimize කරන්න (copy-paste)

### Block A — Game එකට performance mode + resolution downscale

```
cmd game mode performance $pkg
cmd game downscale 0.75 $pkg
```

- `mode performance` — Android එකේ GameManager එකෙන් game එකට CPU/GPU priority වැඩි කරනවා
- `downscale 0.75` — game එක **0.75x** (= 75%) pixels වලින් render කරනවා. **ඔයාගේ phone UI එකට බලපෑමක් නෑ**, game එකට විතරයි
- තව smooth ඕන නම් `0.6` හෝ `0.5` try කරන්න (0.5 = pixels භාගයක්, ලොකුම FPS gain, ටිකක් blur වෙයි)

### Block B — Animations off + background Wi-Fi scanning off

```
settings put global window_animation_scale 0
settings put global transition_animation_scale 0
settings put global animator_duration_scale 0
settings put global wifi_scan_always_enabled 0
settings put global network_recommendations_enabled 0
```

### Block B2 — Touch response එක ඉක්මන් කරන්න (safe)

```
settings put secure long_press_timeout 250
settings put secure multi_press_timeout 250
```

### Block B3 — 🌟 Game එකට focus: freeze වෙන එක නවත්තන්න + full speed

```
dumpsys deviceidle whitelist +$pkg
am set-standby-bucket $pkg 10
settings put global low_power 0
```

> මේ 3 නිසා match එකක් අතරේ ඔයා වෙන app එකකට ගියත් Free Fire එක **kill වෙන්නේ නෑ**, background restrictions **අයින් වෙනවා**, සහ battery saver එකේ CPU cap එක **අයින් වෙනවා**. ආපහු හරවන commands පහළ Undo section එකේ තියෙනවා.
>
> ⚠️ `low_power 0` කියන්නේ battery saver එක **off** කරනවා කියන එකයි — saver on නම් විතරයි වෙනසක් වෙන්නේ.

### Block C — Game එක AOT compile කරන්න (loading/stutter අඩු)

```
cmd package compile -m speed -f $pkg
```

> මේකට තත්පර 30-60ක් ගත වෙන්න පුළුවන්. Game එක install/update කරාට පස්සේ ආයෙත් run කරන්න.

### Block D — නිකන් memory කන apps නවත්තන්න

```
am force-stop com.facebook.katana
am force-stop com.netflix.mediaclient
am force-stop com.linkedin.android
am force-stop com.spotify.music
am force-stop com.instagram.android
```

> ඔයා භාවිතා කරන app එකක් තියෙනවා නම් ඒ පේළිය මකන්න. WhatsApp වගේ දේවල් force-stop කරන්න එපා — messages delay වෙනවා.

### Block D2 — 🧪 (Experiment) ANGLE driver එකෙන් game එක render කරවන්න

```
settings put global angle_gl_driver_selection_pkgs $pkg
settings put global angle_gl_driver_selection_values angle
```

> මේකෙන් Free Fire එක **ANGLE** (OpenGL ES → Vulkan translation layer) එකෙන් render වෙනවා. Google එකේම documented ක්රමයක්.
> ⚠️ **Device එක අනුව FPS වැඩි වෙන්නත් අඩු වෙන්නත් පුළුවන්.** දාන්න කලින් `dumpsys gfxinfo` එකෙන් jank % එකක් ගන්න, දාලා reboot කරලා ආයෙත් ගන්න — compare කරන්න. නරක නම් Block D3 එකෙන් අයින් කරන්න.
> 💡 ඒ වගේම `debug.hwui.renderer` (Skia GL) නම් **දාන්න එපා** — ඒක Android UI එකට විතරයි, **game එකට බලපෑමක් නෑ**.

### Block D2b — (Optional) Refresh-rate lock (සමහර phones ignore කරනවා)

```
settings put system min_refresh_rate 120.0
settings put system peak_refresh_rate 120.0
```

> Display එක 120Hz පෙන්නනවා නම් විතරයි මේකෙන් වැඩක් තියෙන්නේ. Samsung වගේ සමහර phones මේක ignore කරනවා — ඒක normal. අයින් කරන්න `settings delete system min_refresh_rate` + `settings delete system peak_refresh_rate`.

### Block D3 — ANGLE අයින් කරන්න

```
settings delete global angle_gl_driver_selection_pkgs
settings delete global angle_gl_driver_selection_values
```

### Block E — (Optional) තව FPS ඕන නම් විතරයි

```
cmd power set-fixed-performance-mode-enabled true
```

> ⚠️ මේකෙන් CPU/GPU clocks උපරිමයේ pin වෙනවා → **phone එක ගොඩක් රත් වෙනවා, battery ඉක්මනට බහිනවා**.
> Thermal throttling නිසා **දිගු කාලීනව FPS අඩු වෙන්නත් පුළුවන්**. Case එක ගලවලා, charge නොකර ගහන්න.

---

## ↩️ 4. ආපහු හරවන්න (Undo) — මේක අනිවාර්යයෙන් කරන්න දැනගෙන ඉන්න

```
cmd game mode default $pkg
cmd game downscale disable $pkg
settings put global window_animation_scale 1
settings put global transition_animation_scale 1
settings put global animator_duration_scale 1
settings put global wifi_scan_always_enabled 1
settings put global network_recommendations_enabled 1
cmd package compile -m speed-profile -f $pkg
cmd power set-fixed-performance-mode-enabled false
settings put secure long_press_timeout 400
settings put secure multi_press_timeout 300
dumpsys deviceidle whitelist -$pkg
am reset-standby-bucket $pkg
settings delete global low_power
settings delete system min_refresh_rate
settings delete system peak_refresh_rate
settings delete global angle_gl_driver_selection_pkgs
settings delete global angle_gl_driver_selection_values
```

Screen size/density එක මොනව හරි එකකින් වෙනස් කරලා තියෙනවා නම් (Block A එකේ downscale නෙවෙයි — ඒක game එකට විතරයි):

```
wm size reset
wm density reset
```

පස්සේ **phone එක reboot** කරන්න — settings ඔක්කොම ආයෙත් හරියට read වෙනවා.

---

## ✅ 5. Verify කරන්න (වෙනස ඇත්තටම තියෙනවද?)

```
device_config get game_overlay $pkg
dumpsys battery | grep temperature
dumpsys thermalservice | grep "Thermal Status"
dumpsys gfxinfo $pkg | grep -E "Total frames|Janky"
```

**හොඳම test එක:**
1. Optimize කරන්න **කලින්** match එකක් ගහන්න → 10 විනාඩියක් ගියාට පස්සේ FPS බහිනවද බලන්න
2. Optimize කරලා, **game එක restart** කරන්න
3. ආයෙත් match එකක් ගහන්න → temperature එකයි smoothness එකයි compare කරන්න

> `dumpsys gfxinfo` එකේ "Janky frames %" අඩු වුණා නම් ඔයා හරි පාරේ. FPS number එක phone එකේ game engine එක අනුව වෙනස් වෙන්න පුළුවන්.

---

## 🧊 6. Heat = ලොකුම සතුරා (මේක අමතක කරන්න එපා)

Phone එකේ FPS එකට ලොකුම බලපෑම **thermal throttling** එකයි — 10-15 විනාඩියක් ගියාට පස්සේ phone එක රත් වුණාම FPS 60→40 බහිනවා. මේවා නොකරන්න:

- ❌ Charge කරන අතරේ ගහන්න එපා (battery + CPU දෙකම රත් වෙනවා)
- ✅ Case එක ගලවන්න
- ✅ 15-20% battery ඉතුරු කරගන්න
- ✅ Fan එකක් / AC තියෙන තැනක ගහන්න
- ✅ Screen brightness 70-80% ට වඩා අඩුවෙන් තියන්න (තමයි දවාලට බෑ නම්)

---

## ⚙️ 7. Game ඇතුළේ settings (මේක නැතුව අනිත් ඒවා අඩක් wasted)

| Setting | අගය |
|---|---|
| Graphics quality | **Smooth** |
| Frame rate | **High** (හෝ ඔයාගේ phone එකට උපරිම) |
| Auto-adjust graphics | **OFF** |
| Shadows / Anti-aliasing | **OFF** |
| High-quality audio | **OFF** (footsteps වඩා හොඳට ඇහෙනවා) |
| Background music | **OFF** |
| Refresh rate | Phone settings → Display → **High/120Hz**, "App-specific refresh rate" එකෙන් Free Fire ට high rate දෙන්න |

---

## ❓ 8. Free Fire එකේ FPS limit එක ගැන ඇත්ත

- Free Fire එකේ official cap එක **60 FPS** (Normal 30 / Medium 45 / High 60)
- **90 FPS** එක Garena විසින් **phone model එකට අනුව** එකින් එක unlock කරමින් තියෙන්නේ (Realme/Oppo/iQOO වගේ සමහර models වලට දැනටමත්)
- ඔයාගේ phone එකට 90fps option එක පේනවා නම් → use කරන්න
- නැත්නම් **"FPS unlocker" app/mod** දාන්න එපා — ඒවා root ඕන, ඒවායින් **ban වෙන්නත් පුළුවන්**
- RAM booster/cleaner apps වලින් **ඇත්තටම FPS වැඩි වෙන්නේ නෑ** — සමහරවිට අඩු වෙනවා (apps ආයෙත් load වෙන නිසා)

---

## ⚠️ 9. නොකළ යුතු දේවල්

- ❌ Hack/mod/aimbot/FPS unlocker — **ban risk**, හා සදාකාලික ban
- ❌ System apps disable කරන්න එපා (`pm disable-user system.xxx`) — phone එක brick වෙන්න පුළුවන්
- ❌ `wm size` එක අඩු කරලා ඉතුරු නොකරන්න — fingerprint sensor එක වැඩ නොකරන්නත් පුළුවන් (PIN/password use කරන්න)
- ❌ Service/thermal daemon kill කරන්න එපා

---

## 🧭 10. ඉක්මන් reference (Block A-D එකට උඩින්)

```
# ---- OPTIMIZE ----
pkg=com.dts.freefireth
cmd game mode performance $pkg
cmd game downscale 0.75 $pkg
settings put global window_animation_scale 0
settings put global transition_animation_scale 0
settings put global animator_duration_scale 0
settings put global wifi_scan_always_enabled 0
settings put global network_recommendations_enabled 0
settings put secure long_press_timeout 250
settings put secure multi_press_timeout 250
cmd package compile -m speed -f $pkg
dumpsys deviceidle whitelist +$pkg
am set-standby-bucket $pkg 10
settings put global low_power 0

# ---- UNDO ----
cmd game mode default $pkg
cmd game downscale disable $pkg
settings put global window_animation_scale 1
settings put global transition_animation_scale 1
settings put global animator_duration_scale 1
settings put global wifi_scan_always_enabled 1
settings put global network_recommendations_enabled 1
settings put secure long_press_timeout 400
settings put secure multi_press_timeout 300
cmd package compile -m speed-profile -f $pkg
dumpsys deviceidle whitelist -$pkg
am reset-standby-bucket $pkg
settings delete global low_power
```

---

*මේ එකම commands ටික** PC tool එකෙන් automatic run කරන්නත් පුළුවන් (USB/WiFi ADB එකෙන්) — එතකොට backup + undo automatic, සහ temperature/FPS measure කරලා report එකක් හම්බෙනවා.*
