#!/usr/bin/env python3
"""
Fake `adb` for testing FF Mobile Optimizer without a real phone.

It emulates a Redmi Note 12 Pro on Android 13 (SDK 33) with Free Fire installed,
and it stores its state in a JSON file so get/set round-trips behave realistically
(required to test that Restore really puts the device back).

Env:
    FFMO_DEV_DIR     directory for state.json / game_running  (default /tmp/ffmodev)

Usage (as a drop-in adb):
    tests/fake-adb/adb shell "settings get global window_animation_scale"

To make the device look like a game is running:
    touch "$FFMO_DEV_DIR/game_running"

This file exists so that the whole test suite can run on Linux/macOS/CI
with no Android device attached. It is not used by the real tool.
"""
import json
import os
import sys
import time

STATE_DIR = os.environ.get("FFMO_DEV_DIR", "/tmp/ffmodev")
STATE = os.path.join(STATE_DIR, "state.json")
RUNNING = os.path.join(STATE_DIR, "game_running")

DEFAULT = {
    "props": {
        "ro.build.version.release": "13",
        "ro.build.version.sdk": "33",
        "ro.product.model": "Redmi Note 12 Pro",
        "ro.product.brand": "Redmi",
        "ro.soc.model": "MediaTek Helio G99",
        "ro.board.platform": "mt6789",
        "ro.hardware": "mt6789",
    },
    "global": {
        "window_animation_scale": "1.0",
        "transition_animation_scale": "1.0",
        "animator_duration_scale": "1.0",
        "wifi_scan_always_enabled": "1",
        "network_recommendations_enabled": "1",
        "fixed_performance_mode_enabled": "false",
    },
    "secure": {
        "long_press_timeout": "400",
        "multi_press_timeout": "300",
    },
    "system": {},
    "wm_size_override": None,
    "wm_density_override": None,
    "game_overlay": {},       # pkg -> "mode=2,downscaleFactor=0.75"
    "appops": {},             # pkg -> "RUN_IN_BACKGROUND: deny"
    "uninstalled": [],
    "compiled": {},
    "thermal_override": None,
    "base_temp": 36.4,
    "packages": [
        "com.dts.freefireth", "com.dts.freefiremax",
        "com.facebook.katana", "com.facebook.appmanager", "com.facebook.services",
        "com.netflix.mediaclient", "com.linkedin.android", "com.spotify.music",
        "com.whatsapp", "com.instagram.android", "com.google.android.youtube",
        "com.miui.weather2", "com.android.chrome",
    ],
    "third_party": [
        "com.dts.freefireth", "com.dts.freefiremax", "com.facebook.katana",
        "com.facebook.appmanager", "com.facebook.services", "com.netflix.mediaclient",
        "com.linkedin.android", "com.spotify.music", "com.whatsapp",
        "com.instagram.android", "com.google.android.youtube",
    ],
}


def load():
    os.makedirs(STATE_DIR, exist_ok=True)
    if os.path.exists(STATE):
        try:
            d = json.load(open(STATE))
            for k, v in DEFAULT.items():
                d.setdefault(k, v)
            return d
        except Exception:
            pass
    return json.loads(json.dumps(DEFAULT))


def save(s):
    os.makedirs(STATE_DIR, exist_ok=True)
    json.dump(s, open(STATE, "w"), indent=1)


def out(*lines):
    for l in lines:
        print(l)


def game_running():
    return os.path.exists(RUNNING)


def optimized(s):
    """(performance mode on?, downscale on?) for the default Free Fire package"""
    c = s["game_overlay"].get("com.dts.freefireth", "")
    return ("mode=2" in c), ("downscaleFactor" in c)


# ------------------------------------------------------------------ shell parts
def sh_settings(s, rest):
    if not rest:
        return ""
    act = rest[0]
    ns = rest[1] if len(rest) > 1 else "global"
    key = rest[2] if len(rest) > 2 else ""
    store = s["secure"] if ns == "secure" else s["global"]
    if act == "get":
        return store.get(key, "null")
    if act == "put":
        store[key] = rest[3]
        save(s)
        return ""
    if act == "delete":
        store.pop(key, None)
        save(s)
        return ""
    return ""


def sh_wm(s, rest):
    what = rest[0] if rest else ""
    if what == "size":
        if len(rest) > 1:
            s["wm_size_override"] = None if rest[1] == "reset" else rest[1]
            save(s)
            return ""
        lines = ["Physical size: 1080x2400"]
        if s.get("wm_size_override"):
            lines.append("Override size: " + s["wm_size_override"])
        return "\n".join(lines)
    if what == "density":
        if len(rest) > 1:
            s["wm_density_override"] = None if rest[1] == "reset" else rest[1]
            save(s)
            return ""
        lines = ["Physical density: 395"]
        if s.get("wm_density_override"):
            lines.append("Override density: " + s["wm_density_override"])
        return "\n".join(lines)
    return ""


def sh_game(s, rest):
    if len(rest) >= 3 and rest[0] == "mode":
        mode, pkg = rest[1], rest[2]
        parts = [p for p in s["game_overlay"].get(pkg, "").split(",")
                 if p and not p.startswith("mode=")]
        if mode != "default":
            num = {"battery": 0, "balanced": 1, "performance": 2}.get(mode, 1)
            parts.insert(0, "mode=%d" % num)
        if parts:
            s["game_overlay"][pkg] = ",".join(parts)
        else:
            s["game_overlay"].pop(pkg, None)
        save(s)
        return ""
    if len(rest) >= 3 and rest[0] == "downscale":
        factor, pkg = rest[1], rest[2]
        parts = [p for p in s["game_overlay"].get(pkg, "").split(",")
                 if p and not p.startswith("downscaleFactor=")]
        if factor != "disable":
            parts.append("downscaleFactor=%s" % factor)
        if parts:
            s["game_overlay"][pkg] = ",".join(parts)
        else:
            s["game_overlay"].pop(pkg, None)
        save(s)
        return ""
    return ""


def sh_appops(s, rest):
    if not rest:
        return ""
    act = rest[0]
    if act == "get" and len(rest) >= 3:
        pkg, op = rest[1], rest[2]
        cur = "default"
        for p in s["appops"].get(pkg, "").split(","):
            if p.startswith(op + ":"):
                cur = p.split(":", 1)[1].strip()
        return "%s: %s" % (op, cur)
    if act == "set" and len(rest) >= 4:
        pkg, op, mode = rest[1], rest[2], rest[3]
        parts = [p for p in s["appops"].get(pkg, "").split(",")
                 if p and not p.startswith(op + ":")]
        parts.append("%s: %s" % (op, mode))
        s["appops"][pkg] = ",".join(parts)
        save(s)
        return "" if pkg in s["packages"] else "Error: package %s not found" % pkg
    if act == "reset" and len(rest) >= 2:
        s["appops"].pop(rest[1], None)
        save(s)
        return ""
    return ""


def sh_pm(s, rest):
    if rest and rest[0] == "list":
        third = "-3" in rest
        src = s["third_party"] if third else s["packages"]
        pkgs = [p for p in src if p not in s["uninstalled"]]
        return "\n".join("package:" + p for p in pkgs)
    if rest and rest[0] == "uninstall":
        args = [x for x in rest[1:] if not x.startswith("--") and not x.isdigit()]
        if args and args[0] in s["packages"]:
            if args[0] not in s["uninstalled"]:
                s["uninstalled"].append(args[0])
                save(s)
            return "Success"
        return "Failure [not installed for 0]"
    return ""


def sh_cmd(s, rest):
    if not rest:
        return ""
    if rest[0] == "game":
        return sh_game(s, rest[1:])
    if rest[0] == "appops":
        return sh_appops(s, rest[1:])
    if rest[0] == "package":
        if len(rest) > 1 and rest[1] == "compile":
            pkg = rest[-1]
            s["compiled"][pkg] = "speed" if "speed" in " ".join(rest) else "speed-profile"
            save(s)
            return "Success"
        if len(rest) > 1 and rest[1] == "install-existing":
            pkg = rest[-1]
            if pkg in s["uninstalled"]:
                s["uninstalled"].remove(pkg)
                save(s)
                return "Package %s installed for user: 0" % pkg
            return "Package %s was not uninstalled for any user" % pkg
        return ""
    if rest[0] == "power":
        if len(rest) > 1 and rest[1] == "set-fixed-performance-mode-enabled":
            if len(rest) > 2:
                s["global"]["fixed_performance_mode_enabled"] = rest[2]
                save(s)
                return ""
            return s["global"].get("fixed_performance_mode_enabled", "false")
        return ""
    if rest[0] == "thermalservice":
        if len(rest) > 1 and rest[1] == "override-status":
            s["thermal_override"] = rest[2] if len(rest) > 2 else None
            save(s)
            return ""
        if len(rest) > 1 and rest[1] == "reset":
            s["thermal_override"] = None
            save(s)
            return ""
    return ""


def sh_dumpsys(s, rest):
    if not rest:
        return ""
    what = rest[0]
    if what == "battery":
        mode_on, downs = optimized(s)
        t = float(s["base_temp"])
        if mode_on and downs:
            t -= 1.6                    # less GPU work -> cooler
        if s["global"].get("fixed_performance_mode_enabled") == "true":
            t += 3.2                    # pinned clocks -> hotter
        if game_running():
            t += 0.4
        out("Current Battery Service state:", "  AC powered: false", "  USB powered: true",
            "  temperature: %d" % int(round(t * 10)), "  level: 74")
        return None
    if what == "thermalservice":
        mode_on, downs = optimized(s)
        st = 0
        if s.get("thermal_override") == "0":
            st = 0
        elif s["global"].get("fixed_performance_mode_enabled") == "true":
            st = 2
        elif not mode_on and game_running():
            st = 1                      # throttling when unoptimized + gaming
        out("IsStatusOverride: " + ("true" if s.get("thermal_override") is not None else "false"))
        out("Thermal Status: %d" % st)
        return None
    if what == "display":
        out('Display Devices: size=2',
            '  DisplayDeviceInfo{"Built-in Screen": uniqueId="local:0"',
            "    refreshRate=120.000004 fps",
            '    supportedModes=[{"mode":{"resolution":"1080x2400"},"fps":120.0},',
            '                    {"mode":{"resolution":"1080x2400"},"fps":60.0}]')
        return None
    if what == "gfxinfo":
        pkg = rest[1] if len(rest) > 1 else ""
        if not game_running():
            out("** Graphics info for pid 0 [%s] **" % pkg)
            out("No process found for " + pkg)
            return None
        mode_on, downs = optimized(s)
        if mode_on and downs:
            interval, jank = 13.9, "3.8"      # ~72 fps
        elif mode_on:
            interval, jank = 16.6, "9.4"      # ~60 fps
        else:
            interval, jank = 22.7, "21.6"     # ~44 fps, stuttery
        total = 3600
        out("** Graphics info for pid 8123 [%s] **" % pkg, "",
            "Total frames rendered: %d" % total,
            "Janky frames: %d (%s%%)" % (int(total * float(jank) / 100), jank), "",
            "---PROFILEDATA---",
            "Flags,IntendedVsync,Vsync,OldestInputEvent,NewestInputEvent,HandleInputStart,"
            "AnimationStart,PerformTraversalsStart,DrawStart,SyncQueued,SyncStart,"
            "IssueDrawCommandsStart,SwapBuffers,FrameCompleted,DequeueBufferDuration,"
            "QueueBufferDuration,GpuCompleted,SwapBuffersCompleted")
        now = int(time.time() * 1e9)
        step = int(interval * 1e6)
        for i in range(60):
            ts = now - (60 - i) * step
            out("0,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,0,0,%d,%d" % (
                ts, ts + 1000, ts, ts + 500, ts, ts, ts, ts + 2000, ts + 2500,
                ts + 3000, ts + 4000, ts + 6000, ts + 7000, ts + 6800, ts + 6900))
        out("---PROFILEDATA---")
        return None
    if what == "activity":
        out("ACTIVITY MANAGER ACTIVITIES (dumpsys activity activities)")
        if game_running():
            out("  * Task{1234 #4321 type=standard A=10321:com.dts.freefireth}",
                "    mResumedActivity: ActivityRecord{abc u0 com.dts.freefireth/.MainActivity t4321}")
        else:
            out("  mResumedActivity: ActivityRecord{def u0 com.miui.home/.launcher t1}")
        return None
    if what == "deviceidle":
        out("systemui,com.whatsapp")
        return None
    if what == "package":
        pkg = rest[1] if len(rest) > 1 else ""
        v = {"com.dts.freefireth": "1.106.1", "com.dts.freefiremax": "2.106.1"}.get(pkg, "1.0.0")
        out("Packages:", "  Package [%s]:" % pkg, "    versionName=%s" % v)
        return None
    return "(dumpsys %s)" % what


def run_shell(cmd, s):
    r = cmd.strip().split()
    if not r:
        return ""
    h = r[0]
    if h == "getprop":
        return s["props"].get(r[1] if len(r) > 1 else "", "")
    if h == "settings":
        return sh_settings(s, r[1:])
    if h == "wm":
        return sh_wm(s, r[1:])
    if h == "device_config":
        # device_config get game_overlay <pkg>
        if len(r) >= 4 and r[1] == "get":
            return s["game_overlay"].get(r[3]) or "null"
        return "null"
    if h == "cmd":
        return sh_cmd(s, r[1:])
    if h == "pm":
        return sh_pm(s, r[1:])
    if h == "am":
        return ""
    if h == "dumpsys":
        return sh_dumpsys(s, r[1:])
    if h == "cat" and len(r) > 1 and "meminfo" in r[1]:
        mode_on, downs = optimized(s)
        avail = (2.4 if (mode_on or downs) else 1.5) * 1024 * 1024
        return ("MemTotal:       %d kB\nMemFree:         420000 kB\n"
                "MemAvailable:   %d kB\n" % (8 * 1024 * 1024, int(avail)))
    return ""


def main(argv):
    s = load()
    a = argv[1:]
    while a and a[0] in ("-s", "-d", "-e"):
        a = a[2:] if a[0] == "-s" else a[1:]
    if not a:
        out("Android Debug Bridge version 1.0.41")
        return 0
    c = a[0]
    if c == "version":
        out("Android Debug Bridge version 1.0.41", "Version 35.0.2-12345678")
        return 0
    if c == "devices":
        out("List of devices attached",
            "FAKE1234567890\tdevice\tproduct:rubyx device:rubyx "
            "model:Redmi_Note_12_Pro transport_id:1", "")
        return 0
    if c == "connect":
        out("connected to " + (a[1] if len(a) > 1 else "phone"))
        return 0
    if c == "shell":
        res = run_shell(" ".join(a[1:]), s)
        if res:
            out(res)
        return 0
    if c == "get-state":
        out("device")
        return 0
    if c == "wait-for-device":
        return 0
    out("adb: unknown command %s" % c)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
