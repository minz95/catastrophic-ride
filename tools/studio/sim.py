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

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCENARIOS = os.path.join(ROOT, "tools", "studio", "scenarios.json")
OUT_DIR = os.path.join(ROOT, "reports", "studio")
STUDIO = os.environ.get("ROBLOX_STUDIO", "/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio")
LOG_DIR = os.path.expanduser("~/Library/Logs/Roblox")
CHUNK = 800

TIMEOUT = {"race": 900, "escape": 600, "match": 1800}

LUAU = r"""
local HttpService = game:GetService("HttpService")
local Runner = require(game.ServerScriptService.TestHarness.Runner)
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

FN = {"race": "runRace", "escape": "runEscape", "match": "runMatch"}


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


def newest_log():
    logs = glob.glob(os.path.join(LOG_DIR, "*Studio*_last.log"))
    return max(logs, key=os.path.getmtime) if logs else None


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
    if sc["kind"] in ("race", "escape"):
        res = [r for r in report.get("results", []) if isinstance(r, dict)]
        if not res:
            return [("fail", "no cars in report")]
        if sc["kind"] == "escape":
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
                out.append(("fail", "round %s: %d of %d players joined" % (r.get("round"), len(players), want)))
            if players and done / len(players) < c.get("finishRate", 0):
                out.append(("fail", "round %s: %d of %d finished" % (r.get("round"), done, len(players))))
        if not report.get("rounds"):
            out.append(("fail", "no round completed"))
    return out


def run_one(sc, place, args):
    opts = dict(sc.get("opts", {}))
    for kv in args.set or []:
        k, v = kv.split("=", 1)
        opts[k] = parse_value(v)
    if sc["kind"] in ("race", "escape"):
        opts["mode"] = "run"
    src = (LUAU.replace("__OPTS__", json.dumps(opts)).replace("__FN__", FN[sc["kind"]])
           .replace("__SAMPLES__", "true" if args.samples else "false").replace("__CHUNK__", str(CHUNK)))
    work = tempfile.mkdtemp(prefix="studio-sim-")
    script = os.path.join(work, sc["name"] + ".luau")
    with open(script, "w") as f:
        f.write(src)
    before = newest_log()
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
    log = newest_log()
    if log == before and (log is None or os.path.getmtime(log) < t0):
        log = None
    ok, summary, report, errors = read_log(log) if log else (None, "", None, ["no Studio log written"])
    checks = check(sc, report)
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
