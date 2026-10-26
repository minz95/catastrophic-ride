#!/usr/bin/env python3
"""Run Studio real-physics experiments from the command line (macOS).

No MCP and no open Studio window needed: every scenario builds the place with
Rojo, starts `RobloxStudio -task RunScript`, calls TestHarness.Runner inside it
and reads the result back from the Studio log.

  python3 tools/studio/sim.py list
  python3 tools/studio/sim.py run smoke              # a tag (smoke | core | full)
  python3 tools/studio/sim.py run race-forest escape-sky
  python3 tools/studio/sim.py run race-ocean --set seconds=240 --samples
  python3 tools/studio/sim.py summary                # rebuild reports/studio/summary.md

Results: reports/studio/<scenario>.json (report + checks) and summary.md.
Exit code 1 when a check fails. Scenarios live in tools/studio/scenarios.json.

Notes (Studio 0.743, macOS):
- `-outputFile` writes nothing; output is read from the [FLog::CreatorOutput]
  lines of ~/Library/Logs/Roblox/*_Studio_*_last.log, which are cut at ~1000
  characters, so the JSON is printed in 800-character chunks.
- workspace:StepPhysics crashes Studio under -task RunScript, so races run in
  real time (Runner.runRace{ mode = "run" }).
"""

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCENARIOS = os.path.join(ROOT, "tools", "studio", "scenarios.json")
OUT_DIR = os.path.join(ROOT, "reports", "studio")
STUDIO = os.environ.get("ROBLOX_STUDIO", "/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio")
LOG_DIR = os.path.expanduser("~/Library/Logs/Roblox")
CHUNK = 800

TIMEOUT = {"race": 900, "escape": 600, "vehicles": 600, "match": 1800, "sounds": 600, "probe": 300, "gallery": 600,
           "promo": 600}
STORE_DIR = os.path.join(ROOT, "assets", "store")
GALLERY_DIR = os.path.join(ROOT, "reports", "vehicles", "studio")
# Cropped to the Studio view (no desktop, no screen-share banner): safe to commit.
SHEET_DIR = os.path.join(ROOT, "reports", "vehicles", "gallery")
# Screen recordings of a bot client's window (scenario "record"): cropped to
# the Studio view, git-ignored (large). tools/video/cut.py edits them.
VIDEO_DIR = os.path.join(ROOT, "reports", "video", "raw")


def _is_client_frame(px):
    """A play client's outline: bright blue, or dark blue (25, 47, 127)
    while Studio's window is not focused."""
    r, g, b = px[:3]
    return (b > 230 and r < 90 and 80 < g < 140) or (110 < b < 145 and r < 40 and 35 < g < 60)


def _is_frame(px):
    """The coloured outline Studio draws round a running view: green (run
    mode, the server) or blue (a play client)."""
    r, g, b = px[:3]
    return (g > 150 and r < 80 and 80 < b < 140) or (b > 230 and r < 90 and 80 < g < 140)


def _stay_awake(proc):
    """Screenshots of a sleeping display are black: keep it awake while
    Studio runs (a locked screen still cannot be captured)."""
    try:
        subprocess.Popen(["caffeinate", "-d", "-w", str(proc.pid)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def view_box(im, client=False):
    """(left, top, right, bottom) of the 3D view inside Studio's coloured
    outline in a whole-screen PIL image, or None. client: only a play
    client's (blue) outline."""
    w, h = im.size
    is_frame = _is_client_frame if client else _is_frame
    px = im.load()
    rows = [y for y in range(0, h, 1) if sum(1 for x in range(0, w, 4) if is_frame(px[x, y])) > w / 4 * 0.3]
    cols = [x for x in range(0, w, 1) if sum(1 for y in range(0, h, 4) if is_frame(px[x, y])) > h / 4 * 0.3]
    if len(rows) < 2 or len(cols) < 2:
        return None
    top, bottom, left, right = min(rows), max(rows), min(cols), max(cols)
    if bottom - top < 100 or right - left < 100:
        return None
    return (left + 4, top + 4, right - 3, bottom - 3)


def crop_view(path):
    """The 3D view inside Studio's coloured outline, as a PIL image (None
    without PIL or when no outline is found). The whole-screen shot keeps the
    desktop and the screen-share banner (an e-mail address); this does not."""
    try:
        from PIL import Image
    except ImportError:
        return None
    im = Image.open(path).convert("RGB")
    box = view_box(im)
    return im.crop(box) if box else None


def contact_sheets(paths, name, per_row=2, per_sheet=6, width=560):
    """Cropped shots tiled into JPG sheets in SHEET_DIR (name_1.jpg, ...)."""
    tiles = [t for t in (crop_view(p) for p in paths) if t is not None]
    if not tiles:
        print("  (no sheets: PIL missing, or no Studio view in the shots: was the screen asleep or locked?)")
        return []
    from PIL import Image
    os.makedirs(SHEET_DIR, exist_ok=True)
    for old in glob.glob(os.path.join(SHEET_DIR, name + "_*.jpg")):
        os.remove(old)
    out = []
    for k in range(0, len(tiles), per_sheet):
        group = tiles[k:k + per_sheet]
        th = max(int(t.size[1] * width / t.size[0]) for t in group)
        rows = (len(group) + per_row - 1) // per_row
        sheet = Image.new("RGB", (width * per_row, th * rows), (20, 20, 28))
        for i, t in enumerate(group):
            t = t.resize((width, int(t.size[1] * width / t.size[0])))
            sheet.paste(t, ((i % per_row) * width, (i // per_row) * th))
        path = os.path.join(SHEET_DIR, "%s_%d.jpg" % (name, k // per_sheet + 1))
        sheet.save(path, quality=80)
        out.append(path)
    print("  sheets → %s" % ", ".join(os.path.relpath(p, ROOT) for p in out))
    return out

LUAU = r"""
local HttpService = game:GetService("HttpService")
local Runner = require(game.ServerScriptService.TestHarness.Runner)
print("SIM_RUN __TOKEN__")
task.wait(8) -- let the freshly opened place settle (sessions started at once end empty)
local opts = HttpService:JSONDecode([==[__OPTS__]==])
local keepSamples = __SAMPLES__
local t0 = os.clock()
local ok, summary, json = pcall(function() return Runner.__FN__(opts) end)
print("SIM_OK", ok, string.format("%.1f", os.clock() - t0))
print("SIM_SUMMARY_BEGIN") print(ok and summary or ("ERROR " .. tostring(summary))) print("SIM_SUMMARY_END")
if ok and json then
	local okd, rep = pcall(HttpService.JSONDecode, HttpService, json)
	if okd and type(rep) == "table" and rep.results and not keepSamples then
		for _, r in ipairs(rep.results) do r.samples = nil end
	end
	local s = okd and HttpService:JSONEncode(rep) or json
	for i = 1, #s, __CHUNK__ do print("SIM_JSON " .. s:sub(i, i + __CHUNK__ - 1)) end
end
print("SIM_DONE")
"""

FN = {"race": "runRace", "escape": "runEscape", "vehicles": "runRace", "match": "runMatch", "sounds": "runSounds", "probe": "probeApi",
      "gallery": "runGallery", "promo": "runPromo"}


def run_gallery_studio(cmd, token, t0, timeout, sheet="gallery"):
    """Runs Studio and takes a screenshot (screencapture, the whole screen,
    scaled to 1600 px) at every GALLERY_SHOT line the gallery prints.
    Needs screen-recording permission for the terminal."""
    os.makedirs(GALLERY_DIR, exist_ok=True)
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    _stay_awake(proc)
    taken = set()
    for old in glob.glob(os.path.join(GALLERY_DIR, "[0-9][0-9]_*.png")):
        os.remove(old)
    while proc.poll() is None and time.time() - t0 < timeout:
        time.sleep(0.5)
        log = find_log(token, t0)
        if not log:
            continue
        with open(log, errors="replace") as f:
            for name in re.findall(r"GALLERY_SHOT " + token + r" \d+ (\w+)", f.read()):
                if name in taken:
                    continue
                taken.add(name)
                out = os.path.join(GALLERY_DIR, name + ".png")
                subprocess.run(["screencapture", "-x", out])
                subprocess.run(["sips", "-Z", "1600", out], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                print("  shot %s → %s" % (name, os.path.relpath(out, ROOT)), flush=True)
    if proc.poll() is None:
        proc.terminate()
        return "timeout"
    shots = [os.path.join(GALLERY_DIR, n + ".png") for n in sorted(taken)]
    contact_sheets(shots, sheet, per_row=2, per_sheet=6)   # 3 items a sheet: side | rear
    return proc.returncode


def store_image(path, name, icon=False):
    """A store picture from a full-resolution screenshot: the Studio view,
    cropped to 16:9 (or a centred square for the icon) and resized to
    1920 x 1080 (512 x 512). Returns the written path or None."""
    view = crop_view(path)
    if view is None:
        return None
    from PIL import Image
    w, h = view.size
    if icon:
        side = min(w, h)
        box = ((w - side) // 2, (h - side) // 2, (w - side) // 2 + side, (h - side) // 2 + side)
        size, out = (512, 512), os.path.join(STORE_DIR, "icon.png")
    else:
        if w / h > 16 / 9:
            cw, ch = int(h * 16 / 9), h
        else:
            cw, ch = w, int(w * 9 / 16)
        box = ((w - cw) // 2, (h - ch) // 2, (w - cw) // 2 + cw, (h - ch) // 2 + ch)
        size, out = (1920, 1080), os.path.join(STORE_DIR, name + ".png")
    os.makedirs(STORE_DIR, exist_ok=True)
    view.crop(box).resize(size, Image.LANCZOS).save(out)
    return out


def run_promo_studio(cmd, token, t0, timeout):
    """Like run_gallery_studio, but the screenshots stay full resolution and
    each becomes a store picture in assets/store/ (store_image)."""
    os.makedirs(GALLERY_DIR, exist_ok=True)
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    _stay_awake(proc)
    taken = set()
    while proc.poll() is None and time.time() - t0 < timeout:
        time.sleep(0.5)
        log = find_log(token, t0)
        if not log:
            continue
        with open(log, errors="replace") as f:
            for name in re.findall(r"GALLERY_SHOT " + token + r" \d+ (\w+)", f.read()):
                if name in taken:
                    continue
                taken.add(name)
                raw = os.path.join(GALLERY_DIR, "promo_" + name + ".png")
                subprocess.run(["screencapture", "-x", raw])
                out = store_image(raw, name, icon=(name == "icon"))
                print("  shot %s → %s" % (name, os.path.relpath(out, ROOT) if out else "(no Studio view found: screen asleep or locked?)"), flush=True)
    if proc.poll() is None:
        proc.terminate()
        return "timeout"
    return proc.returncode


def run_with_shots(cmd, token, t0, timeout, name, shots):
    """Runs Studio and takes screenshots (whole screen, scaled to 1600 px)
    once the server log shows `shots["after"]` (e.g. "phase=CRAFTING"):
    `count` shots `gap` s apart after `delay` s, into GALLERY_DIR (git-ignored:
    the whole screen is in them). For looking at client UI in a match."""
    os.makedirs(GALLERY_DIR, exist_ok=True)
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    _stay_awake(proc)
    seen_at, taken, paths = None, 0, []
    while proc.poll() is None and time.time() - t0 < timeout:
        time.sleep(0.5)
        if seen_at is None:
            # the test server writes its own log (not the one with the token)
            for path in glob.glob(os.path.join(LOG_DIR, "*Studio*.log")):
                if os.path.getmtime(path) < t0:
                    continue
                with open(path, errors="replace") as f:
                    if shots.get("after", "") in f.read():
                        seen_at = time.time()
                        break
            continue
        due = seen_at + shots.get("delay", 3) + taken * shots.get("gap", 4)
        if taken < shots.get("count", 3) and time.time() >= due:
            taken += 1
            out = os.path.join(GALLERY_DIR, "%s_%d.png" % (name, taken))
            paths.append(out)
            subprocess.run(["screencapture", "-x", out])
            subprocess.run(["sips", "-Z", "1600", out], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            print("  shot %s → %s" % (name, os.path.relpath(out, ROOT)), flush=True)
    if proc.poll() is None:
        proc.terminate()
        return "timeout"
    contact_sheets(paths, name, per_row=2, per_sheet=4)
    return proc.returncode


def _screen_scale():
    """Pixels per point of the main display (2 on Retina): screencapture -R
    takes points, screenshots are in pixels."""
    tmp = os.path.join(tempfile.mkdtemp(prefix="scale-"), "s.png")
    subprocess.run(["screencapture", "-x", "-R0,0,100,100", tmp])
    try:
        from PIL import Image
        return Image.open(tmp).size[0] / 100.0
    except Exception:
        return 2.0


def run_with_record(cmd, token, t0, timeout, name, rec):
    """Runs Studio and records a play client's view (blue outline: the bot
    client's window in a match) as video. Studio writes its log only at the
    end of a match, so nothing waits on phases: from the moment the client
    view is on screen, `screencapture -v -R` records only that rectangle (no
    desktop, no e-mail banner) in rec["chunk"]-second pieces, back to back,
    until Studio closes. Pieces: a running recording cannot be stopped
    cleanly (any signal loses the file); the piece running when Studio
    closes would film what lies under it, so it is deleted. Studio is
    brought to the front once at launch (open -a). Writes
    VIDEO_DIR/<name>/NNN.mov and take.json (each piece's start in seconds),
    which tools/video/cut.py edits; `cut.py sheets` shows what is where."""
    import shutil
    folder = os.path.join(VIDEO_DIR, name)
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(folder)
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    _stay_awake(proc)
    from PIL import Image
    chunk = rec.get("chunk", 10)
    rect, pieces, current, rec_t0, raised, k = None, [], None, None, 0, _screen_scale()
    while proc.poll() is None and time.time() - t0 < timeout:
        time.sleep(0.25)
        if rect is None:
            if not raised and time.time() - t0 >= 4:
                # Studio to the front once, before the client window opens:
                # a new window of the active app opens on top. Raising it
                # later puts Studio's edit window over the client.
                subprocess.run(["open", "-a", os.path.dirname(os.path.dirname(os.path.dirname(STUDIO)))])
                raised = time.time()
            if time.time() - t0 < rec.get("delay", 20):
                continue   # Studio opening, the place building
            shot = os.path.join(tempfile.mkdtemp(prefix="rec-"), "s.png")
            subprocess.run(["screencapture", "-x", shot])
            box = view_box(Image.open(shot).convert("RGB"), client=True)
            if os.environ.get("SIM_DEBUG"):
                print("  look at %.0f s: %s (%s)" % (time.time() - t0, box, shot), flush=True)
            if not box:
                continue
            x, y = int(box[0] / k) + 1, int(box[1] / k) + 1
            w, h = int((box[2] - box[0]) / k) - 2, int((box[3] - box[1]) / k) - 2
            w, h = w - w % 2, h - h % 2
            rect = "-R%d,%d,%d,%d" % (x, y, w, h)
            print("  recording %dx%d pt → %s/" % (w, h, os.path.relpath(folder, ROOT)), flush=True)
        if current is None or current.poll() is not None:
            out = os.path.join(folder, "%03d.mov" % len(pieces))
            current = subprocess.Popen(["screencapture", "-x", "-v", "-V", str(chunk), rect, out],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            now = time.time()
            rec_t0 = rec_t0 or now
            pieces.append({"file": os.path.basename(out), "start": round(now - rec_t0, 2)})
    if current is not None and current.poll() is None:
        # it outlives Studio: drop it (it would film the desktop)
        current.wait(timeout=chunk + 10)
        os.remove(os.path.join(folder, pieces[-1]["file"]))
        pieces.pop()
    if rec_t0:
        with open(os.path.join(folder, "take.json"), "w") as f:
            json.dump({"pieces": pieces, "chunk": chunk}, f, indent=1)
        print("  %d pieces, %.0f s" % (len(pieces), (pieces[-1]["start"] + chunk) if pieces else 0), flush=True)
    if proc.poll() is None:
        proc.terminate()
        return "timeout"
    return proc.returncode


def load_scenarios():
    with open(SCENARIOS) as f:
        return json.load(f)["scenarios"]


def select(scenarios, names):
    out = []
    for n in names:
        hit = [s for s in scenarios if s["name"] == n or n in s.get("tags", [])]
        if not hit:
            sys.exit("unknown scenario or tag: " + n)
        out += [s for s in hit if s not in out]
    return out


def build_place(path):
    rojo = shutil.which("rojo") or os.path.expanduser("~/bin/rojo")
    subprocess.run([rojo, "build", os.path.join(ROOT, "roblox"), "-o", path], check=True,
                   stdout=subprocess.DEVNULL)


def parse_value(v):
    try:
        return json.loads(v)
    except ValueError:
        return v


def find_log(token, since):
    """The Studio log of this run: written after `since` and containing the
    run's token. Other Studio windows (an open editor) write logs too, so
    "the newest log" is not enough."""
    logs = [p for p in glob.glob(os.path.join(LOG_DIR, "*Studio*.log")) if os.path.getmtime(p) >= since - 1]
    for p in sorted(logs, key=os.path.getmtime, reverse=True):
        with open(p, errors="replace") as f:
            if ("SIM_RUN " + token) in f.read():
                return p
    return None


def read_log(path):
    summary, chunks, errors, ok = [], [], [], None
    inside = False
    with open(path, errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            m = re.search(r"\[FLog::(?:CreatorOutput|Output)\] (.*)$", line)
            body = m.group(1) if m else (line if inside else None)
            if re.search(r",Error \[|\[Runner\]|\[HarnessEntry\]", line):
                errors.append(line[-300:])
            if body is None:
                continue
            if body.startswith("SIM_JSON "):
                chunks.append(body[9:])
            elif body == "SIM_SUMMARY_BEGIN":
                inside = True
            elif body == "SIM_SUMMARY_END":
                inside = False
            elif inside:
                summary.append(body)
            elif body.startswith("SIM_OK"):
                ok = body
    report = None
    if chunks:
        try:
            report = json.loads("".join(chunks))
        except ValueError as e:
            errors.append("JSON decode failed: %s" % e)
    return ok, "\n".join(summary), report, errors


def check(sc, report):
    """Returns a list of (level, message); level is 'fail' or 'warn'."""
    c = sc.get("checks", {})
    out = []
    if not isinstance(report, dict) or not report:
        return [("fail", "no report (session returned nothing)")]
    if sc["kind"] == "probe":
        bad = sorted(k for k, v in (report.get("members") or {}).items() if v is not True)
        if bad:
            out.append(("fail", "missing engine members: " + ", ".join(bad)))
        return out
    if sc["kind"] == "sounds":
        conf = report.get("configured") or {}
        if not conf:
            return [("fail", "no sounds checked")]
        bad = sorted(k for k, v in conf.items() if not v.get("ok"))
        if bad and c.get("allLoad", True):
            out.append(("fail", "%d sounds do not load: %s" % (len(bad), ", ".join(bad[:12]))))
        return out
    if sc["kind"] == "promo":
        if report.get("errors"):
            out.append(("fail", "scenes failed: " + "; ".join(report["errors"])))
        return out
    if sc["kind"] == "gallery":
        loose = report.get("loose") or []
        if "loose" in c and len(loose) > c["loose"]:
            out.append(("fail", "%d loose wheels / paddles / propellers: %s" % (len(loose), "; ".join(loose[:8]))))
        return out
    if sc["kind"] in ("race", "escape", "vehicles"):
        res = [r for r in report.get("results", []) if isinstance(r, dict)]
        if "maxTilt" in c:
            tilted = [r for r in res if (r.get("maxTilt") or 0) > c["maxTilt"]]
            if tilted:
                out.append(("fail", "tilted over %d°: %s" % (c["maxTilt"], ", ".join(
                    "%s %.0f°" % (r.get("label") or r.get("profile"), r["maxTilt"]) for r in tilted[:8]))))
        if "minTopSpeedRatio" in c:
            slow = [r for r in res if r.get("maxSpeed") and (r.get("topSpeed") or 0) < c["minTopSpeedRatio"] * r["maxSpeed"]]
            if slow:
                out.append(("fail", "never reached %d%% of MaxSpeed: %s" % (c["minTopSpeedRatio"] * 100, ", ".join(
                    "%s %.0f/%.0f" % (r.get("label"), r.get("topSpeed") or 0, r["maxSpeed"]) for r in slow[:8]))))
        if "minHoldGain" in c:
            weak = [r for r in res if r.get("holdGain") is not None and r["holdGain"] < c["minHoldGain"]]
            if weak:
                out.append(("fail", "throttle alone moved under %d studs: %s" % (c["minHoldGain"], ", ".join(
                    "%s %d" % (r.get("label"), r["holdGain"]) for r in weak[:8]))))
        if "maxNoseOff" in c:
            skew = [r for r in res if (r.get("maxNoseOff") or 0) > c["maxNoseOff"]]
            if skew:
                out.append(("fail", "nose off the travel direction over %d°: %s" % (c["maxNoseOff"], ", ".join(
                    "%s %.0f°" % (r.get("label"), r["maxNoseOff"]) for r in skew[:8]))))
        if not res:
            return [("fail", "no cars in report")]
        if sc["kind"] in ("escape", "vehicles"):
            stuck = [r for r in res if not r.get("reached")]
            respawned = [r for r in res if r.get("reached") and r.get("respawns")]
            if len(stuck) > c.get("stuck", 0):
                out.append(("fail", "%d stuck: %s" % (len(stuck), ", ".join(
                    "%s (blocked by %s)" % (r.get("label"), (r.get("blocked") or [{}])[0].get("part", "?"))
                    for r in stuck[:8]))))
            if respawned:
                out.append(("warn", "%d escaped only by respawning: %s" % (
                    len(respawned), ", ".join(r.get("label", "?") for r in respawned[:8]))))
            return out
        if c.get("finishAll"):
            dnf = [r for r in res if not r.get("finished")]
            if dnf:
                out.append(("fail", "did not finish: " + ", ".join(
                    "%s at %s/%s" % (r.get("label") or r.get("profile"), r.get("maxProgress"), r.get("trackLength"))
                    for r in dnf)))
        if "maxRespawns" in c:
            many = [r for r in res if len(r.get("respawns", [])) > c["maxRespawns"]]
            if many:
                out.append(("fail", "too many respawns: " + ", ".join(
                    "%s %d" % (r.get("label") or r.get("profile"), len(r["respawns"])) for r in many)))
        if "winnerTime" in c:
            times = [r["time"] for r in res if r.get("finished")]
            lo, hi = c["winnerTime"]
            if times and not (lo <= min(times) <= hi):
                out.append(("warn", "winner time %.1fs outside the %d-%d s target" % (min(times), lo, hi)))
    elif sc["kind"] == "match":
        if report.get("errors"):
            out.append(("fail", "%d server script errors" % len(report["errors"])))
        if report.get("timedOut"):
            out.append(("fail", "match timed out"))
        want = sc["opts"].get("players", 4)
        for r in report.get("rounds", []):
            players = r.get("players", [])
            done = len(r.get("finishOrder", []))
            if c.get("allJoined") and len(players) < want:
                # Studio sometimes starts fewer client windows than asked
                # (no bot_joined event at all for the missing player).
                out.append(("warn", "round %s: %d of %d players joined (Studio did not start every client)" % (
                    r.get("round"), len(players), want)))
            if players and done / len(players) < c.get("finishRate", 0):
                out.append(("fail", "round %s: %d of %d finished" % (r.get("round"), done, len(players))))
        if not report.get("rounds"):
            out.append(("fail", "no round completed"))
        for r in report.get("rounds", []):
            out += check_farm(c, r, report)
        events = (report.get("telemetry") or {}).get("events") or []
        if c.get("fairStart"):
            out += check_fair_start(c, events)
        if c.get("hudTimer"):
            out += check_hud_timer(c, events)
        if c.get("shopUi"):
            out += check_shop_ui(c["shopUi"], events)
        if c.get("abilities"):
            out += check_abilities(sc, events)
        perf = [e for e in events if e.get("kind") == "server_perf"]
        if c.get("perf"):
            pc = c["perf"]
            if not perf:
                out.append(("fail", "no server_perf samples"))
            for key, floor in (("heartbeatHz", pc.get("minHeartbeatHz")), ("physicsFps", pc.get("minPhysicsFps"))):
                vals = sorted(e[key] for e in perf if e.get(key) is not None and e.get("phase") in ("FARMING", "RACING"))
                if floor and vals:
                    p5 = vals[max(0, int(len(vals) * 0.05) - 1)]
                    if p5 < floor:
                        out.append(("fail", "server %s p5 %.1f under %d (min %.1f)" % (key, p5, floor, vals[0])))
        if c.get("showroomSpin"):
            sr = [e for e in events if e.get("kind") == "bot_showroom_spin"
                  and ((e.get("data") or {}).get("groups") or 0) > 0 and ((e.get("data") or {}).get("turned") or 0) > 0]
            if len(sr) < c["showroomSpin"]:
                out.append(("fail", "nothing turned in the crafting showroom"))
        if c.get("eject"):
            ej = [e.get("data") or {} for e in events if e.get("kind") == "bot_eject"]
            for stage in ("jump", "respawn"):
                got = [d for d in ej if d.get("stage") == stage]
                if not got:
                    out.append(("fail", "eject test: no %s report" % stage))
                elif not all(d.get("seated") for d in got):
                    out.append(("fail", "eject test: out of the car after the %s (%d of %d)" %
                                (stage, sum(1 for d in got if not d.get("seated")), len(got))))
        if c.get("spin"):
            turned = {e.get("userId") for e in events if e.get("kind") == "bot_spin_fx"
                       and ((e.get("data") or {}).get("turns") or 0) >= 3}
            if len(turned) < c["spin"]:
                out.append(("fail", "wheels or propellers spun on %d cars, want %d" % (len(turned), c["spin"])))
        if c.get("shop"):
            sc_ = c["shop"]
            bought = [e for e in events if e.get("kind") == "bot_shop" and (e.get("data") or {}).get("result") == "ok"]
            notok = [e for e in events if e.get("kind") == "bot_shop" and (e.get("data") or {}).get("result") != "ok"]
            if len(bought) < sc_.get("bought", 0):
                out.append(("fail", "bought %d of %d shop items (%s)" % (len(bought), sc_["bought"], ", ".join(
                    "%s: %s" % ((e.get("data") or {}).get("id"), (e.get("data") or {}).get("result")) for e in notok[:6]))))
            fx = {e.get("userId") for e in events if e.get("kind") == "bot_ride_fx"
                  and ((e.get("data") or {}).get("rate") or 0) > 0 and ((e.get("data") or {}).get("forward") or 0) > 10}
            if len(fx) < sc_.get("rideFx", 0):
                out.append(("fail", "special-ride particles seen while driving on %d cars, want %d" % (len(fx), sc_["rideFx"])))
            kicks = [e for e in events if e.get("kind") == "bot_farmfx" and (e.get("data") or {}).get("what") == "kick"
                     and (e.get("data") or {}).get("drawn")]
            if len(kicks) < sc_.get("kicks", 0):
                out.append(("fail", "no Flying Kick was drawn"))
            gadgets = [e for e in events if e.get("kind") == "gadget"]
            escaped = [e for e in events if e.get("kind") == "steal_attempt" and e.get("result") == "escaped"]
            if not gadgets:
                out.append(("warn", "no Smoke Bomb was thrown (no bot with one was grabbed)"))
            elif not escaped:
                out.append(("warn", "%d Smoke Bombs, no grab escaped" % len(gadgets)))
        if c.get("bots"):
            bc = c["bots"]
            spawned = [e for e in events if e.get("kind") == "race_bot"]
            fin = [e for e in events if e.get("kind") == "finish" and e.get("bot")]
            resp = [e for e in events if e.get("kind") == "respawn" and e.get("reason") == "bot"]
            if len(spawned) < bc.get("spawned", 0):
                out.append(("fail", "%d race bots spawned, want %d" % (len(spawned), bc["spawned"])))
            if len(fin) < bc.get("finished", 0):
                out.append(("fail", "%d of %d bots finished (bot respawns: %d)" % (len(fin), len(spawned), len(resp))))
            if len(resp) > 3 * max(1, len(spawned)):
                out.append(("warn", "bots respawned %d times" % len(resp)))
        if c.get("rewards"):
            rewarded = {e.get("userId") for e in events if e.get("kind") == "reward"}
            for r in report.get("rounds", []):
                raced = {p.get("userId") for p in r.get("players", []) if p.get("speed")}
                missing = raced - rewarded
                if missing:
                    out.append(("fail", "round %s: %d racers got no reward at RESULTS" % (r.get("round"), len(missing))))
        out += check_driving(c, events)
        out += check_after_finish(c, events)
    return out


def check_after_finish(c, events):
    """Nobody falls or respawns after crossing the line (2026-10-22: the
    winner ran off the end of the road and fell again and again), the
    others get the finish grace, logs are seen and passed."""
    out = []
    fin = {}
    for e in events:
        if e.get("kind") == "finish":
            fin.setdefault(e.get("userId"), e.get("t"))
    late = [e for e in events if e.get("kind") == "respawn" and e.get("userId") in fin and e.get("t", 0) > fin[e.get("userId")]]
    if late:
        out.append(("fail", "%d respawns after a racer finished (%s)" % (
            len(late), ", ".join("%s %s" % (e.get("userId"), e.get("reason")) for e in late[:5]))))
    grace = [e for e in events if e.get("kind") == "phase_shortened" and e.get("phase") == "RACING"]
    logs = [e for e in events if e.get("kind") == "hazard" and e.get("type") == "fallingLog"]
    log_hits = [e for e in events if e.get("kind") == "hit" and e.get("by") == "FallingLog"]
    print("    after finish: %d finished, %d late respawns, grace %s; falling logs %d, hit %d times" % (
        len(fin), len(late), "yes" if grace else "no", len(logs), len(log_hits)))
    return out


def check_driving(c, events):
    """Car-to-car hits, drift turbos and track drops (2026-10-22).
    Drops must lie on the ground and show their item; hits must reach both
    drivers with a push. `c["hits"]` / `c["turbos"]`: minimum counts."""
    out = []
    impacts = [e for e in events if e.get("kind") == "impact"]
    if impacts:
        weak = [e for e in impacts if (e.get("dvA") or 0) + (e.get("dvB") or 0) <= 0]
        if weak:
            out.append(("fail", "%d of %d hits pushed nobody" % (len(weak), len(impacts))))
    if len(impacts) < c.get("hits", 0):
        out.append(("fail", "%d car-to-car hits (want at least %d)" % (len(impacts), c["hits"])))
    turbos = [e for e in events if e.get("kind") == "drift_turbo"]
    if len(turbos) < c.get("turbos", 0):
        out.append(("fail", "%d drift turbos (want at least %d)" % (len(turbos), c["turbos"])))
    fx = [e for e in events if e.get("kind") == "bot_farmfx"]
    broken = [e for e in fx if (e.get("data") or {}).get("error")]
    if broken:
        out.append(("fail", "%d fight animations errored on clients, first: %s" % (len(broken), (broken[0].get("data") or {}).get("error"))))
    if c.get("fightFx"):
        drawn = set((e.get("data") or {}).get("what") for e in fx if (e.get("data") or {}).get("drawn"))
        missing = [w for w in c["fightFx"] if w not in drawn]
        if missing:
            out.append(("fail", "fight animations never drawn on a client: " + ", ".join(missing)))
    for e in events:
        if e.get("kind") == "drop_placed":
            if not e.get("onGround"):
                out.append(("fail", "%s drop did not find the ground at (%s, %s)" % (e.get("item"), e.get("x"), e.get("z"))))
            if not e.get("modelParts"):
                out.append(("fail", "%s drop shows no item model" % e.get("item")))
    return out


def perf_summary(events):
    perf = [e for e in events if e.get("kind") == "server_perf"]
    if not perf:
        return ""
    parts = []
    for phase in ("FARMING", "CRAFTING", "RACING"):
        ph = [e for e in perf if e.get("phase") == phase]
        if not ph:
            continue
        hb = sorted(e.get("heartbeatHz") or 0 for e in ph)
        pf = sorted(e.get("physicsFps") or 0 for e in ph)
        snd = max(e.get("sendKbps") or 0 for e in ph)
        parts.append("%s heartbeat %.0f-%.0f Hz, physics %.0f-%.0f fps, send max %.0f kbps" % (
            phase, hb[0], hb[-1], pf[0], pf[-1], snd))
    mem = max(e.get("memMb") or 0 for e in perf)
    return "server: " + "; ".join(parts) + "; memory max %d MB" % mem


def driving_summary(events):
    impacts = [e for e in events if e.get("kind") == "impact"]
    turbos = [e for e in events if e.get("kind") == "drift_turbo"]
    drops = [e for e in events if e.get("kind") == "drop_placed"]
    if not (impacts or turbos or drops):
        return ""
    line = "driving: %d hits" % len(impacts)
    if impacts:
        line += " (closing speed max %.0f, push max %.0f studs/s)" % (
            max(e.get("strength") or 0 for e in impacts),
            max(max(e.get("dvA") or 0, e.get("dvB") or 0) for e in impacts))
    line += ", %d drift turbos" % len(turbos)
    if drops:
        line += ", drops: " + ", ".join(sorted(set("%s%s" % (e.get("item"), "" if e.get("onGround") else "(air!)") for e in drops)))
    return line


def check_fair_start(c, events):
    """Every car leaves the grid within `fairStart` seconds of the others,
    and only after GO (Modules/RaceStart)."""
    out = []
    gos = [e for e in events if e.get("kind") == "race_go"]
    if not gos:
        return [("fail", "no race_go event: the countdown never released the cars")]
    launches = [e for e in events if e.get("kind") == "race_launch"]
    if not launches:
        return [("fail", "no car left the grid")]
    after = [e.get("afterGo", 0) for e in launches]
    early = [e for e in launches if e.get("afterGo", 0) < -0.05]
    if early:
        out.append(("fail", "%d cars moved before GO" % len(early)))
    spread = max(after) - min(after)
    if spread > c["fairStart"]:
        out.append(("fail", "cars left the grid %.1f s apart (limit %.1f s): %s" % (
            spread, c["fairStart"], ", ".join("%.1f" % a for a in sorted(after)))))
    return out


# What each effect must do to the car it lands on (Modules/EffectFx probes:
# the car just before the effect and over the next 0.5-1.5 s).
LIFT_KEYS = {"rise", "hover", "emergencyFloat", "fullBuoyancy", "softLanding", "groundBounce",
             "lifeFloat", "kiteLift", "kiteGlide", "parachute"}
FASTER_KEYS = {"rocketBurst", "reverseBoost", "spinBurst", "overclock", "redline", "windRide",
               "umbrellaSail", "raftGlide", "skateSlide", "kiteGlide", "flagAura", "barrelRoll",
               "boost", "boostRocket", "leadFlag", "momentum"}
# (2026-10-22: Red Sofa and the SKY Umbrella no longer slow their own car)
SLOWER_KEYS = {"noodleSnare", "magnetPull", "slipped", "splashed", "cactusSting", "frozen",
               "slipstream", "stall"}
STEER_LOCK_KEYS = {"steerDisable", "redline"}
LIFT_MIN = 1.5   # studs


def ability_table(events):
    """Per item: ability request results; per effect key: probes and draws."""
    items, probes, drawn = {}, {}, {}
    for e in events:
        k = e.get("kind")
        if k == "ability":
            items.setdefault(e.get("item"), {}).setdefault(e.get("result"), 0)
            items[e.get("item")][e.get("result")] += 1
        elif k == "ability_probe":
            probes.setdefault(e.get("effect"), []).append(e)
        elif k == "bot_fx":
            d = e.get("data") or {}
            drawn.setdefault(d.get("key"), []).append(d)
    return items, probes, drawn


def check_abilities(sc, events):
    """Every loadout item fired; each landing did what it should; every
    effect sent was drawn by the clients."""
    out = []
    items, probes, drawn = ability_table(events)
    # Loadouts of the bots that joined (BotIndex = join order; Studio
    # sometimes starts fewer client windows than asked).
    joined = len({e.get("userId") for e in events if e.get("kind") == "bot_joined"})
    want = set()
    for rnd in sc["opts"].get("loadouts") or []:
        for slots in rnd[:joined]:
            want |= {slots.get(t) for t in ("SPECIAL", "ENGINE", "BODY") if slots.get(t)}
    never = sorted(i for i in want if not (items.get(i) or {}).get("ok"))
    if never:
        out.append(("fail", "%d items never fired: %s" % (len(never), ", ".join(
            "%s %s" % (i, items.get(i) or "no request") for i in never))))
    wrong = sum((r or {}).get("denied: not equipped", 0) for r in items.values())
    if wrong:
        out.append(("fail", "%d requests for items that are not on the car" % wrong))
    if not probes:
        return out + [("fail", "no ability_probe events (EffectFx never measured an effect)")]

    def bad(key, test):
        ps = probes.get(key) or []
        miss = [p for p in ps if not test(p)]
        return ps, miss

    for key in sorted(probes):
        ps = probes[key]
        problems = []
        if key in LIFT_KEYS:
            # lifts do not stack: a car already lifted (lift0) only rises the difference
            _, miss = bad(key, lambda p: (p.get("yMax") or 0) - (p.get("y0") or 0) + (p.get("lift0") or 0) >= LIFT_MIN)
            if len(miss) == len(ps):
                problems.append("never rose %.1f studs (rose %s)" % (LIFT_MIN, ", ".join(
                    "%.1f" % ((p.get("yMax") or 0) - (p.get("y0") or 0)) for p in ps[:5])))
        if key in FASTER_KEYS:
            _, miss = bad(key, lambda p: (p.get("maxSpeedMid") or 0) > (p.get("maxSpeed0") or 0) * 1.03)
            if len(miss) == len(ps):
                problems.append("MaxSpeed never went up (%s)" % ", ".join(
                    "%s→%s" % (p.get("maxSpeed0"), p.get("maxSpeedMid")) for p in ps[:5]))
        if key in SLOWER_KEYS:
            _, miss = bad(key, lambda p: (p.get("maxSpeedMid") or 0) < (p.get("maxSpeed0") or 0) * 0.97)
            if len(miss) == len(ps):
                problems.append("MaxSpeed never went down (%s)" % ", ".join(
                    "%s→%s" % (p.get("maxSpeed0"), p.get("maxSpeedMid")) for p in ps[:5]))
        if key in STEER_LOCK_KEYS:
            _, miss = bad(key, lambda p: (p.get("turnMid") or 0) <= 0.01)
            if len(miss) == len(ps):
                problems.append("steering never locked (TurnSpeed %s)" % ", ".join(str(p.get("turnMid")) for p in ps[:5]))
        if problems:
            # One landing can be masked by other effects changing at the same
            # moment (boost ending, another slow starting): a warning.
            out.append(("fail" if len(ps) >= 2 else "warn", "%s (%d landings): %s" % (key, len(ps), "; ".join(problems))))
    for key in sorted(probes):
        ds = drawn.get(key) or []
        if not ds:
            out.append(("fail", "%s: sent %d times, no client drew it" % (key, len(probes[key]))))
            continue
        errs = [d for d in ds if d.get("error") or d.get("missing")]
        if errs:
            out.append(("warn", "%s: %d of %d client draws failed (%s)" % (
                key, len(errs), len(ds), errs[0].get("error") or ("no " + str(errs[0].get("missing"))))))
    return out


def ability_summary(events):
    """Text table for the summary: per effect key, landings and what was measured."""
    items, probes, drawn = ability_table(events)
    lines = ["abilities: %d items fired ok, %d effect keys measured" % (
        sum(1 for r in items.values() if r.get("ok")), len(probes))]
    for key in sorted(probes):
        ps = probes[key]
        rise = max((p.get("yMax") or 0) - (p.get("y0") or 0) for p in ps)
        ms = ["%s→%s" % (p.get("maxSpeed0"), p.get("maxSpeedMid")) for p in ps[:2]]
        lines.append("  %-15s x%-3d rise %.1f  MaxSpeed %s  drawn %d" % (
            key, len(ps), rise, " ".join(ms), len(drawn.get(key) or [])))
    return "\n".join(lines)


def parse_clock(text):
    m = re.search(r"(\d+):(\d\d)", text or "")
    return int(m.group(1)) * 60 + int(m.group(2)) if m else None


def check_shop_ui(sc, events):
    """The shop screen (ShopUI) a bot opened with B: shows the phase clock,
    closes itself `closeAt` s before the car is built and when the round
    starts (Shared/ShopTiming)."""
    out = []
    s = [e.get("data") or {} for e in events if e.get("kind") == "bot_shop_ui"]
    if not s:
        return [("fail", "no shop screen samples (did the bot open it?)")]
    close_at = sc.get("closeAt", 12)
    craft = [x for x in s if x.get("phase") == "CRAFTING" and x.get("left") is not None]
    early = [x for x in craft if x["left"] > close_at + 1]
    late = [x for x in craft if x["left"] < close_at - 1]
    if not any(x.get("open") for x in early):
        out.append(("fail", "CRAFTING: the shop never opened before %d s left" % close_at))
    elif not any((x.get("clock") or "").startswith("Car is built in") for x in early if x.get("open")):
        out.append(("fail", "CRAFTING: no phase clock on the open shop: %r" % [x.get("clock") for x in early][:3]))
    if any(x.get("open") for x in late):
        out.append(("fail", "CRAFTING: the shop was still open with %.0f s left" % min(x["left"] for x in late if x.get("open"))))
    if not any((x.get("notice") or "").startswith("Finish your car") for x in craft):
        out.append(("fail", "CRAFTING: no 'Finish your car' notice when the shop closed"))
    lobby_open = any(x.get("open") for x in s if x.get("phase") == "LOBBY")
    farm = [x for x in s if x.get("phase") == "FARMING"]
    if lobby_open and farm and farm[0].get("open"):
        out.append(("fail", "FARMING: the shop opened in the lobby stayed open when the round started"))
    if any(x.get("open") for x in s if x.get("phase") == "RACING"):
        out.append(("fail", "RACING: the shop is open"))
    return out


def check_hud_timer(c, events):
    """The FARMING / CRAFTING timer on each bot's screen: one copy, counting
    down, within 2 s of the server's end time."""
    out = []
    by = {}
    for e in events:
        if e.get("kind") == "bot_hud":
            by.setdefault((e.get("userId"), (e.get("data") or {}).get("phase")), []).append(e)
    if not by:
        return [("fail", "no HUD samples from the bot clients")]
    for (uid, phase), samples in sorted(by.items(), key=lambda kv: str(kv[0])):
        d = [s.get("data") or {} for s in samples]
        dup = [x for x in d if len(x.get("guis") or []) != 1]
        if dup:
            out.append(("fail", "%s %s: %d timer screens at once" % (uid, phase, len(dup[0].get("guis") or []))))
        shown = [parse_clock(x["guis"][0].get("text")) for x in d if x.get("guis") and x["guis"][0].get("shown")]
        shown = [v for v in shown if v is not None]
        if len(shown) >= 3 and shown[-1] >= shown[0]:
            out.append(("fail", "%s %s: timer does not count down (%s)" % (uid, phase, shown[:6])))
        off = [abs(parse_clock(x["guis"][0].get("text")) - x["serverLeft"]) for x in d
               if x.get("guis") and x.get("serverLeft") is not None and parse_clock(x["guis"][0].get("text")) is not None]
        if off and max(off) > 2:
            out.append(("fail", "%s %s: timer is %.0f s off the server's" % (uid, phase, max(off))))
    return out


def check_farm(c, r, report):
    """FARMING / CRAFTING checks on one round (MatchHarness farm / craft stats)."""
    out = []
    farm, craft = r.get("farm") or {}, r.get("craft") or {}
    players = (farm.get("players") or {})
    profile = {str(p.get("userId")): p.get("farm") for p in r.get("players", [])}
    tag = "round %s: " % r.get("round")
    if c.get("ledger") and farm.get("ledgerMismatches"):
        out.append(("fail", tag + "inventory ledger off: " + "; ".join(farm["ledgerMismatches"])))
    for uid, p in players.items():
        if (p.get("inventory") or 0) > 8:
            out.append(("fail", tag + "%s holds %d items" % (uid, p["inventory"])))
    if c.get("everyonePicks"):
        lazy = [uid for uid, prof in profile.items() if prof != "afk" and players.get(uid, {}).get("pickups", 0) == 0]
        if lazy:
            out.append(("fail", tag + "picked up nothing: " + ", ".join(lazy)))
    if c.get("everyoneCrafted"):
        missing = [uid for uid in profile if uid not in craft]
        if missing:
            out.append(("fail", tag + "no craft for " + ", ".join(missing)))
    if c.get("noRejected"):
        bad = ["%s %s" % (uid, x.get("rejected")) for uid, x in craft.items() if x.get("rejected")]
        if bad:
            out.append(("fail", tag + "server rejected craft slots: " + "; ".join(bad)))
    for prof in c.get("autoFor", []):
        for uid, pr in profile.items():
            if pr == prof and not (craft.get(uid) or {}).get("auto"):
                out.append(("fail", tag + "%s (%s) did not get an auto craft" % (uid, prof)))
    for prof in c.get("draftKept", []):
        for uid, pr in profile.items():
            if pr != prof:
                continue
            x = craft.get(uid) or {}
            draft, slots = x.get("draft") or {}, x.get("slots") or {}
            lost = ["%s=%s→%s" % (k, v, slots.get(k)) for k, v in draft.items() if slots.get(k) != v]
            if not draft:
                out.append(("fail", tag + "%s (%s): no draft reached the auto craft" % (uid, prof)))
            elif lost:
                out.append(("fail", tag + "%s (%s): placed items lost at the timeout: %s" % (uid, prof, ", ".join(lost))))
    attempts = farm.get("attempts") or {}
    for res, n in (c.get("minAttempts") or {}).items():
        if attempts.get(res, 0) < n:
            out.append(("fail", tag + "steal attempts %s: %d (want at least %d; all: %s)" % (res, attempts.get(res, 0), n, attempts)))
    punches = farm.get("punches") or {}
    for res, n in (c.get("minPunches") or {}).items():
        if punches.get(res, 0) < n:
            out.append(("fail", tag + "punches %s: %d (want at least %d; all: %s)" % (res, punches.get(res, 0), n, punches)))
    for res, n in (c.get("maxAttempts") or {}).items():
        if attempts.get(res, 0) > n:
            out.append(("fail", tag + "steal attempts %s: %d (want at most %d)" % (res, attempts.get(res, 0), n)))
    errs = [e for e in report.get("clientErrors", []) if "ChatScript" not in json.dumps(e)]
    if errs:
        out.append(("warn", "%d bot client errors, first: %s" % (len(errs), json.dumps(errs[0])[:200])))
    return out


def run_one(sc, place, args):
    opts = dict(sc.get("opts", {}))
    for kv in args.set or []:
        k, v = kv.split("=", 1)
        opts[k] = parse_value(v)
    if sc["kind"] in ("race", "escape", "vehicles"):
        opts["mode"] = "run"
    if sc["kind"] == "vehicles":
        opts["cases"] = "vehicles"
    token = uuid.uuid4().hex
    if sc["kind"] in ("gallery", "promo"):
        opts["token"] = token
    src = (LUAU.replace("__TOKEN__", token).replace("__OPTS__", json.dumps(opts)).replace("__FN__", FN[sc["kind"]])
           .replace("__SAMPLES__", "true" if args.samples else "false").replace("__CHUNK__", str(CHUNK)))
    work = tempfile.mkdtemp(prefix="studio-sim-")
    script = os.path.join(work, sc["name"] + ".luau")
    with open(script, "w") as f:
        f.write(src)
    t0 = time.time()
    print("▶ %s (%s) ..." % (sc["name"], sc["kind"]), flush=True)
    timeout = args.timeout or TIMEOUT[sc["kind"]]
    cmd = [STUDIO, "-task", "RunScript", "-localPlaceFile", place, "-runScriptFile", script, "-quitAfterExecution"]
    if sc["kind"] == "gallery":
        code = run_gallery_studio(cmd, token, t0, timeout, sc["name"])
    elif sc["kind"] == "promo":
        code = run_promo_studio(cmd, token, t0, timeout)
    elif sc.get("record"):
        code = run_with_record(cmd, token, t0, timeout, sc["name"], sc["record"])
    elif sc.get("shots"):
        code = run_with_shots(cmd, token, t0, timeout, sc["name"], sc["shots"])
    else:
        try:
            proc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout)
            code = proc.returncode
        except subprocess.TimeoutExpired:
            code = "timeout"
    wall = time.time() - t0
    log = find_log(token, t0)
    ok, summary, report, errors = read_log(log) if log else (None, "", None, ["no Studio log written"])
    checks = check(sc, report)
    if sc.get("checks", {}).get("abilities") and isinstance(report, dict):
        summary += "\n" + ability_summary((report.get("telemetry") or {}).get("events") or [])
    if sc["kind"] == "match" and isinstance(report, dict):
        evs = (report.get("telemetry") or {}).get("events") or []
        d = driving_summary(evs)
        if d:
            summary += "\n" + d
        bots = [e for e in evs if e.get("kind") == "finish" and e.get("bot")]
        spawned = [e for e in evs if e.get("kind") == "race_bot"]
        farmBots = [e for e in evs if e.get("kind") == "farm_bot"]
        if farmBots:
            picks = [e for e in evs if e.get("kind") == "item_pickup" and (e.get("userId") or 0) <= -100000]
            acts = [e for e in evs if e.get("kind") == "bot_farm"]
            punches = [e for e in acts if e.get("act") == "punch"]
            onBots = [e for e in evs if e.get("kind") in ("punch", "steal_attempt") and
                      ((e.get("victim") or 0) <= -100000)]
            summary += "\nfarm bots: %d on the farm, %d pickups, %d punches thrown, %d punches/steals on bots" % (
                len(farmBots), len(picks), len(punches), len(onBots))
            botSteals = [e for e in evs if e.get("kind") == "steal_attempt" and (e.get("thief") or 0) <= -100000
                         and not str(e.get("result", "")).startswith("denied")]
            guards = [e for e in acts if e.get("act") == "guard"]
            summary += "\nfarm bots: %d steals tried (%d stolen), %d guards" % (
                len(botSteals), len([e for e in botSteals if e.get("result") == "stolen"]), len(guards))
        spins = {}
        for e in evs:
            if e.get("kind") == "bot_spin_fx":
                dd = e.get("data") or {}
                spins[e.get("userId")] = (max(spins.get(e.get("userId"), (0, ""))[0], dd.get("turns") or 0), dd.get("modes") or "")
        if spins:
            summary += "\nspinning wheels / paddles / propellers: %d cars (%s), most turns %d" % (
                len(spins), ", ".join(sorted(set(m for _, m in spins.values()))), max(t for t, _ in spins.values()))
        ups = [e for e in evs if e.get("kind") == "updraft"]
        if ups:
            summary += "\nupdrafts: %d lifts (%d bots), zones %s, lift %s studs" % (
                len(ups), len([e for e in ups if e.get("bot")]), ", ".join(sorted(set(str(e.get("zone")) for e in ups))),
                "/".join(sorted(set(str(e.get("lift")) for e in ups))))
        botAb = [e for e in evs if e.get("kind") == "bot_ability"]
        if botAb:
            summary += "\nbot abilities: %d fired (%s)" % (len(botAb), ", ".join(sorted(set(e.get("item", "?") for e in botAb))))
        targets = [e for e in evs if e.get("kind") == "ability_target"]
        if targets:
            summary += "\nability targets: %d, on bots %d" % (len(targets), len([e for e in targets if e.get("bot")]))
        if spawned:
            summary += "\nbots: %d raced (%s), %d farmed their car, %d finished: %s" % (len(spawned), ", ".join(e.get("profile", "?") for e in spawned),
                len([e for e in spawned if e.get("farmed")]), len(bots), ", ".join("%.1fs" % e.get("time", 0) for e in bots))
        pf = perf_summary(evs)
        if pf:
            summary += "\n" + pf
    if sc["kind"] == "race" and isinstance(report, dict):
        res = report.get("results") or report.get("cars") or []
        if isinstance(res, list) and any(isinstance(r, dict) and r.get("drifts") for r in res):
            summary += "\ndrifts: " + ", ".join("%s %d/%d" % (r.get("label") or r.get("profile"), r.get("drifts") or 0, r.get("turbos") or 0)
                                                for r in res if isinstance(r, dict))
    if code not in (0, "0"):
        checks.insert(0, ("fail" if report is None else "warn", "Studio exit code %s%s" % (
            code, " (139 = crash)" if code == 139 else "")))
    os.makedirs(OUT_DIR, exist_ok=True)
    rec = {
        "scenario": sc["name"], "kind": sc["kind"], "opts": opts, "ranAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "commit": subprocess.run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], capture_output=True,
                                 text=True).stdout.strip(),
        "dirty": bool(subprocess.run(["git", "-C", ROOT, "status", "--porcelain", "roblox"], capture_output=True,
                                     text=True).stdout.strip()),
        "wallSeconds": round(wall, 1), "studioExit": code, "summary": summary,
        "checks": [{"level": l, "message": m} for l, m in checks], "logErrors": errors[-10:], "report": report,
    }
    with open(os.path.join(OUT_DIR, sc["name"] + ".json"), "w") as f:
        json.dump(rec, f, indent=1, sort_keys=True)
    if args.keep_log and log:
        shutil.copy(log, os.path.join(OUT_DIR, sc["name"] + ".log"))
    shutil.rmtree(work, ignore_errors=True)
    status = "FAIL" if any(l == "fail" for l, _ in checks) else ("WARN" if checks else "PASS")
    print(summary)
    for l, m in checks:
        print("  %s %s" % (l.upper(), m))
    print("◀ %s %s in %.0fs\n" % (sc["name"], status, wall), flush=True)
    return status


def write_summary():
    rows = []
    for path in sorted(glob.glob(os.path.join(OUT_DIR, "*.json"))):
        with open(path) as f:
            rec = json.load(f)
        checks = rec.get("checks", [])
        status = "FAIL" if any(c["level"] == "fail" for c in checks) else ("WARN" if checks else "PASS")
        first = (rec.get("summary") or "").splitlines()
        rows.append((rec["scenario"], status, rec.get("commit", "?") + ("+" if rec.get("dirty") else ""),
                     rec.get("ranAt", "?")[:16], rec.get("summary") or "", checks))
    lines = ["# Studio experiments", "",
             "Real Roblox physics, run with `python3 tools/studio/sim.py run <scenario|tag>` "
             "(scenarios: `tools/studio/scenarios.json`). One file per scenario next to this one.", "",
             "| Scenario | Result | Commit | Ran |", "|---|---|---|---|"]
    for name, status, commit, ran, _, _ in rows:
        lines.append("| [%s](%s.json) | %s | %s | %s |" % (name, name, status, commit, ran))
    for name, status, commit, ran, summary, checks in rows:
        lines += ["", "## %s — %s" % (name, status), "", "```", summary.strip() or "(no summary)", "```"]
        for c in checks:
            lines.append("- **%s** %s" % (c["level"], c["message"]))
    with open(os.path.join(OUT_DIR, "summary.md"), "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    sub.add_parser("summary")
    r = sub.add_parser("run")
    r.add_argument("names", nargs="+", help="scenario names or tags")
    r.add_argument("--set", action="append", help="override an option, e.g. seconds=240 or profiles='[\"novice\"]'")
    r.add_argument("--samples", action="store_true", help="keep position samples in the report")
    r.add_argument("--keep-log", action="store_true", help="copy the Studio log next to the result")
    r.add_argument("--place", help="use this .rbxl instead of building one with Rojo")
    r.add_argument("--timeout", type=int, help="seconds before Studio is killed")
    args = ap.parse_args()

    scenarios = load_scenarios()
    if args.cmd == "list":
        for s in scenarios:
            print("%-24s %-7s %-16s %s" % (s["name"], s["kind"], ",".join(s.get("tags", [])), s.get("_why", "")))
        return
    if args.cmd == "summary":
        write_summary()
        return
    chosen = select(scenarios, args.names)
    place = args.place
    if not place:
        place = os.path.join(tempfile.mkdtemp(prefix="studio-place-"), "game.rbxl")
        build_place(place)
    statuses = {}
    for sc in chosen:
        statuses[sc["name"]] = run_one(sc, place, args)
    write_summary()
    print("Results: " + ", ".join("%s %s" % kv for kv in statuses.items()))
    print("Report:  " + os.path.relpath(os.path.join(OUT_DIR, "summary.md"), os.getcwd()))
    sys.exit(1 if "FAIL" in statuses.values() else 0)


if __name__ == "__main__":
    main()
