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

TIMEOUT = {"race": 900, "escape": 600, "vehicles": 600, "match": 1800, "sounds": 600, "probe": 300}

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

FN = {"race": "runRace", "escape": "runEscape", "vehicles": "runRace", "match": "runMatch", "sounds": "runSounds", "probe": "probeApi"}


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
        if c.get("abilities"):
            out += check_abilities(sc, events)
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
    src = (LUAU.replace("__TOKEN__", token).replace("__OPTS__", json.dumps(opts)).replace("__FN__", FN[sc["kind"]])
           .replace("__SAMPLES__", "true" if args.samples else "false").replace("__CHUNK__", str(CHUNK)))
    work = tempfile.mkdtemp(prefix="studio-sim-")
    script = os.path.join(work, sc["name"] + ".luau")
    with open(script, "w") as f:
        f.write(src)
    t0 = time.time()
    print("▶ %s (%s) ..." % (sc["name"], sc["kind"]), flush=True)
    timeout = args.timeout or TIMEOUT[sc["kind"]]
    try:
        proc = subprocess.run([STUDIO, "-task", "RunScript", "-localPlaceFile", place, "-runScriptFile", script,
                               "-quitAfterExecution"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                              timeout=timeout)
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
        d = driving_summary((report.get("telemetry") or {}).get("events") or [])
        if d:
            summary += "\n" + d
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
