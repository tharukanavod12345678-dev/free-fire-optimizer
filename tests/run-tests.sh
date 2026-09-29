#!/usr/bin/env bash
# =============================================================================
#  FF Mobile Optimizer - regression test suite
# -----------------------------------------------------------------------------
#  Runs the whole tool against tests/fake-adb (an emulated Android phone),
#  so no real device is needed. Works on Linux, macOS and CI.
#
#  Requirements:  pwsh (PowerShell 7+)  and  python3
#
#  Usage:         bash tests/run-tests.sh
# =============================================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/src/FFMobileOptimizer.ps1"
FAKE_ADB="$ROOT/tests/fake-adb/adb"

DEV="/tmp/ffmo-test-device"
APP="/tmp/ffmo-test-app"
export FFMO_DEV_DIR="$DEV"
export FFMO_HOME="$APP"
export FFMO_SILENT=1

# ---------------------------------------------------------------- requirements
if ! command -v pwsh >/dev/null 2>&1; then
    echo "ERROR: pwsh (PowerShell 7+) is required but was not found in PATH."
    echo "       Windows : winget install Microsoft.PowerShell"
    echo "       macOS   : brew install --cask powershell"
    echo "       Linux   : https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux"
    exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required (used by tests/fake-adb)."
    exit 2
fi

pass=0
fail=0

chk() {  # chk <name> <expected substring> <output file>
    sed "s/\x1b\[[0-9;]*m//g" "$3" > "$3.clean" 2>/dev/null
    if grep -qF -- "$2" "$3.clean"; then
        printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass + 1))
    else
        printf '  \033[31mFAIL\033[0m  %s   (wanted: %s)\n' "$1" "$2"; fail=$((fail + 1))
    fi
}
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail + 1)); }

reset_device() {
    rm -rf "$DEV"; mkdir -p "$DEV"
    touch "$DEV/game_running"                 # pretend Free Fire is running
    "$PS" -NoProfile -File "$SRC" -Mode Scan -AdbPath "$FAKE_ADB" >/dev/null 2>&1
    cp "$DEV/state.json" /tmp/ffmo-pristine.json
}
reset_app() { rm -rf "$APP"; mkdir -p "$APP"; }
PS="$(command -v pwsh)"

echo "=============================================================="
echo " FF Mobile Optimizer - test suite"
echo " script : $SRC"
echo " device : emulated Redmi Note 12 Pro / Android 13 (tests/fake-adb)"
echo "=============================================================="

echo
echo "== T1: script sanity =="
"$PS" -NoProfile -Command '
  $e = $null; $t = $null
  [System.Management.Automation.Language.Parser]::ParseFile("'"$SRC"'", [ref]$t, [ref]$e) | Out-Null
  if ($e.Count -eq 0) { "clean" } else { $e[0].Message }
' > /tmp/t1.txt 2>&1
chk "parses without syntax errors" "clean" /tmp/t1.txt

echo
echo "== T2: scan (read-only) =="
reset_device; reset_app
"$PS" -NoProfile -File "$SRC" -Mode Scan -AdbPath "$FAKE_ADB" > /tmp/t2.txt 2>&1
chk "device detected"        "Redmi Note 12 Pro"                /tmp/t2.txt
chk "android version read"   "Android 13 (SDK 33)"              /tmp/t2.txt
chk "refresh rate read"      "120 Hz"                           /tmp/t2.txt
chk "free fire detected"     "com.dts.freefireth"               /tmp/t2.txt
chk "starts at 0% score"     "(0/12 core tweaks optimal)"       /tmp/t2.txt
chk "focus tweak rows shown" "Battery-optimization exemption"   /tmp/t2.txt
chk "standby bucket read"    "bucket WORKING_SET"               /tmp/t2.txt
chk "battery saver read"     "battery saver is ON"              /tmp/t2.txt
chk "refresh lock read"      "not locked (device peak 120 Hz)"  /tmp/t2.txt
chk "temperature read"       "Temperature : 36."                /tmp/t2.txt
chk "touch latency read"     "long_press=400 multi_press=300"   /tmp/t2.txt
chk "angle state read"       "native GLES driver"               /tmp/t2.txt

echo
echo "== T3: measure =="
"$PS" -NoProfile -File "$SRC" -Mode Measure -AdbPath "$FAKE_ADB" > /tmp/t3.txt 2>&1
chk "fps is estimated"       "fps (estimated"                   /tmp/t3.txt
chk "jank percentage"        "janky frames"                     /tmp/t3.txt
chk "thermal state"          "Thermal"                          /tmp/t3.txt

echo
echo "== T4: safe profile =="
reset_device; reset_app
"$PS" -NoProfile -File "$SRC" -Mode Optimize -Profile Safe -AdbPath "$FAKE_ADB" -Force > /tmp/t4.txt 2>&1
chk "7 tweaks applied"       "[7/7]"                            /tmp/t4.txt
chk "game mode applied"      "performance mode"                 /tmp/t4.txt
chk "downscale applied"      "75% of pixels"                    /tmp/t4.txt
chk "touch response applied" "long press + multi tap tuned"     /tmp/t4.txt
chk "backup written"         "Backup saved"                     /tmp/t4.txt
chk "report written"         "report-"                           /tmp/t4.txt
grep -q "ANGLE enabled" /tmp/t4.txt.clean && bad "ANGLE must not run in Safe profile" || ok "ANGLE stays off in Safe profile"
python3 -c "
import json, sys
d = json.load(open('$DEV/state.json'))
ok = (d['game_overlay'].get('com.dts.freefireth') == 'mode=2,downscaleFactor=0.75'
      and d['global']['window_animation_scale'] == '0'
      and d['secure']['long_press_timeout'] == '250'
      and 'angle_gl_driver_selection_pkgs' not in d['global'])
sys.exit(0 if ok else 1)" && ok "device state really changed" || bad "device state not changed"
python3 -c "
import json, sys
d = json.load(open('$DEV/state.json'))
ok = ('com.dts.freefireth' not in d['doze_whitelist']
      and d['standby'].get('com.dts.freefireth') == 20
      and d['global'].get('low_power') == '1')
sys.exit(0 if ok else 1)" && ok "Safe profile leaves the focus tweaks alone" || bad "Safe touched focus tweaks"

echo
echo "== T5: full profile (ANGLE still off by default) =="
reset_device; reset_app
"$PS" -NoProfile -File "$SRC" -Mode Optimize -Profile Full -AdbPath "$FAKE_ADB" -Force > /tmp/t5.txt 2>&1
chk "12 tweaks applied"      "[12/12]"                          /tmp/t5.txt
chk "doze exemption applied" "battery-optimization exempt"      /tmp/t5.txt
chk "active bucket applied"  "bucket = ACTIVE"                  /tmp/t5.txt
chk "battery saver applied"  "battery saver turned off"         /tmp/t5.txt
chk "fixed perf applied"     "clocks pinned"                    /tmp/t5.txt
chk "bloat restricted"       "apps restricted"                  /tmp/t5.txt
python3 -c "
import json, sys
d = json.load(open('$DEV/state.json'))
ok = ('com.dts.freefireth' in d['doze_whitelist']
      and d['standby'].get('com.dts.freefireth') == 10
      and d['global'].get('low_power') == '0')
sys.exit(0 if ok else 1)" && ok "focus tweaks really applied" || bad "focus tweaks not applied"
grep -q "ANGLE enabled" /tmp/t5.txt.clean && bad "ANGLE must need -Angle flag" || ok "ANGLE still off by default"

echo
echo "== T6: -Angle flag (experimental opt-in) =="
reset_device; reset_app
"$PS" -NoProfile -File "$SRC" -Mode Optimize -Profile Full -Angle -AdbPath "$FAKE_ADB" -Force > /tmp/t6.txt 2>&1
chk "13 tweaks applied"      "[13/13]"                          /tmp/t6.txt
chk "experimental warning"   "EXPERIMENTAL: measure before/after" /tmp/t6.txt
chk "angle enabled message"  "ANGLE enabled"                    /tmp/t6.txt
python3 -c "
import json, sys
d = json.load(open('$DEV/state.json'))
ok = (d['global'].get('angle_gl_driver_selection_pkgs') == 'com.dts.freefireth'
      and d['global'].get('angle_gl_driver_selection_values') == 'angle')
sys.exit(0 if ok else 1)" && ok "ANGLE settings written" || bad "ANGLE settings missing"

echo
echo "== T7: dry run changes nothing =="
reset_device; reset_app
"$PS" -NoProfile -File "$SRC" -Mode Optimize -Profile Full -Angle -AdbPath "$FAKE_ADB" -DryRun -Force > /tmp/t7.txt 2>&1
chk "dry run banner"         "DRY RUN - nothing was changed"    /tmp/t7.txt
diff -q /tmp/ffmo-pristine.json "$DEV/state.json" >/dev/null && ok "device untouched" || bad "device was modified"
[ -f "$APP/pending-FAKE1234567890.json" ] && bad "dry run wrote a change log" || ok "no change log written"

echo
echo "== T8: one Restore undoes everything (safe + full + angle) =="
reset_device; reset_app
"$PS" -NoProfile -File "$SRC" -Mode Optimize -Profile Safe -AdbPath "$FAKE_ADB" -Force >/dev/null 2>&1
"$PS" -NoProfile -File "$SRC" -Mode Optimize -Profile Full -Angle -AdbPath "$FAKE_ADB" -Force >/dev/null 2>&1
python3 -c "
import json
d = json.load(open('$APP/pending-FAKE1234567890.json'))
print(len(d['Changes']))" > /tmp/t8n.txt
chk "23 changes accumulated" "23"                               /tmp/t8n.txt
"$PS" -NoProfile -File "$SRC" -Mode Restore -AdbPath "$FAKE_ADB" -Force > /tmp/t8.txt 2>&1
chk "23 items reverted"      "23 item(s) reverted"              /tmp/t8.txt
chk "change log cleared"     "Change log cleared"               /tmp/t8.txt
python3 - <<EOF > /tmp/t8rt.txt
import json
a = json.load(open('/tmp/ffmo-pristine.json'))
b = json.load(open('$DEV/state.json'))
a.pop('thermal_override', None); b.pop('thermal_override', None)
d = [k for k in set(a) | set(b) if a.get(k) != b.get(k)]
if not d:
    print("IDENTICAL")
else:
    print("DIFFS:")
    for k in d:
        print("  ", k, "|", a.get(k), "->", b.get(k))
EOF
chk "device identical to pristine" "IDENTICAL"                  /tmp/t8rt.txt

echo
echo "== T9: bloat removal is reversible =="
reset_device; reset_app
"$PS" -NoProfile -File "$SRC" -Mode Optimize -Profile Custom -Tweaks "GameMode,RemoveBloat" \
      -RemovePackages "com.facebook.katana,com.linkedin.android" -AdbPath "$FAKE_ADB" -Force > /tmp/t9.txt 2>&1
chk "custom profile runs" "OPTIMIZE - profile: Custom"           /tmp/t9.txt
python3 -c "
import json, sys
d = json.load(open('$DEV/state.json'))
sys.exit(0 if {'com.facebook.katana','com.linkedin.android'} <= set(d['uninstalled']) else 1)" \
    && ok "apps removed" || bad "apps not removed"
"$PS" -NoProfile -File "$SRC" -Mode Restore -AdbPath "$FAKE_ADB" -Force > /tmp/t9b.txt 2>&1
python3 -c "
import json, sys
d = json.load(open('$DEV/state.json'))
sys.exit(0 if not d['uninstalled'] else 1)" && ok "apps reinstalled by restore" || bad "apps not restored"

echo
echo "== T10: custom downscale factor =="
reset_device; reset_app
"$PS" -NoProfile -File "$SRC" -Mode Optimize -Profile Custom -Tweaks "GameMode,Downscale" \
      -Downscale 0.6 -AdbPath "$FAKE_ADB" -Force > /tmp/t10.txt 2>&1
chk "60% factor honoured" "60% of pixels"                        /tmp/t10.txt

echo
echo "== T11: phone-only guide =="
"$PS" -NoProfile -File "$SRC" -Mode PhoneGuide > /tmp/t11.txt 2>&1
chk "optimize commands"      "cmd game mode performance"         /tmp/t11.txt
chk "angle section"          "angle_gl_driver_selection_pkgs"    /tmp/t11.txt
chk "undo section"           "undo everything"                   /tmp/t11.txt
chk "focus commands in guide" "dumpsys deviceidle whitelist +"  /tmp/t11.txt
chk "bucket command in guide" "am set-standby-bucket"           /tmp/t11.txt

echo
echo "== T13: refresh-rate lock (opt-in, Custom only) =="
reset_device; reset_app
"$PS" -NoProfile -File "$SRC" -Mode Optimize -Profile Custom -Tweaks "RefreshLock" -AdbPath "$FAKE_ADB" -Force > /tmp/t13.txt 2>&1
chk "refresh lock applied"   "refresh lock set to 120 Hz"       /tmp/t13.txt
python3 -c "
import json, sys
d = json.load(open('$DEV/state.json'))
ok = (d['system'].get('min_refresh_rate') == '120.0' and d['system'].get('peak_refresh_rate') == '120.0')
sys.exit(0 if ok else 1)" && ok "system settings written" || bad "system settings missing"
"$PS" -NoProfile -File "$SRC" -Mode Restore -AdbPath "$FAKE_ADB" -Force > /tmp/t13b.txt 2>&1
python3 -c "
import json, sys
d = json.load(open('$DEV/state.json'))
sys.exit(0 if not d['system'] else 1)" && ok "refresh lock removed by restore" || bad "refresh lock left behind"

echo
echo "== T12: restore with no backup =="
reset_app
"$PS" -NoProfile -File "$SRC" -Mode Restore -AdbPath "$FAKE_ADB" -Force > /tmp/t12.txt 2>&1
rc=$?
chk "clear error message"    "No backup file found"              /tmp/t12.txt
[ "$rc" -ne 0 ] && ok "non-zero exit code ($rc)" || bad "expected non-zero exit code"

echo
echo "=============================================================="
if [ "$fail" -eq 0 ]; then
    printf '  \033[32mRESULT: %d passed, 0 failed\033[0m\n' "$pass"
else
    printf '  \033[31mRESULT: %d passed, %d failed\033[0m\n' "$pass" "$fail"
fi
echo "=============================================================="
[ "$fail" -eq 0 ] || exit 1
