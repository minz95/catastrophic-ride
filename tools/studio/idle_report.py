#!/usr/bin/env python3
"""Idle time per phase from the Studio match reports (reports/studio/*.json).

    python3 tools/studio/idle_report.py [reports/studio/match-forest.json ...]

For every match run it prints, per phase:
  FARMING   when each player's inventory filled up and how long the phase
            went on after their last pickup / steal / contest
  CRAFTING  how long players who had submitted waited for the race
  RACING    how long finished players waited for the results

Writes reports/studio/idle.md. Bots are faster than people at crafting, so
treat CRAFTING waits as a lower bound.
"""
import glob
import json
import sys


def events_of(path):
    d = json.load(open(path))
    if d.get("kind") != "match":
        return None, None
    return d, d["report"]["telemetry"]["events"]


def phases(ev):
    return [(e["t"], e["phase"]) for e in ev if e["kind"] == "phase"]


def first(ph, name, after=-1):
    for t, p in ph:
        if p == name and t > after:
            return t
    return None


def report(path):
    d, ev = events_of(path)
    if d is None or not ev:
        return None
    ph = phases(ev)
    out = [f"## {path.split('/')[-1]}  (players {d['opts'].get('players')}, durations {d['opts'].get('durations') or 'live'})"]
    fs = first(ph, "FARMING")
    cs = first(ph, "CRAFTING", fs or -1)
    rs = first(ph, "RACING", cs or -1)
    res = first(ph, "RESULTS", rs or -1)
    if fs and cs:
        last, full = {}, {}
        for e in ev:
            if fs <= e["t"] <= cs:
                if e["kind"] == "item_pickup":
                    last[e["userId"]] = e["t"]
                    if e.get("inventory", 0) >= 8 and e["userId"] not in full:
                        full[e["userId"]] = e["t"] - fs
                for k in ("thief", "winner"):
                    if e["kind"] in ("steal", "contest_result") and k in e:
                        last[e[k]] = e["t"]
        idle = {u: round(cs - t, 1) for u, t in last.items()}
        waves = [e for e in ev if e["kind"] == "item_wave" and fs <= e["t"] <= cs]
        out.append(f"- FARMING {cs - fs:.0f} s: inventory full at {dict((u, round(t, 1)) for u, t in full.items())}; "
                   f"idle after last pickup/steal {idle}; item waves {[w.get('count') for w in waves]}")
    if cs and rs:
        sub = {e["userId"]: round(rs - e["t"], 1) for e in ev if e["kind"] == "craft" and cs <= e["t"] <= rs + 0.5 and not e.get("auto")}
        short = [e for e in ev if e["kind"] == "phase_shortened" and cs <= e["t"] <= rs]
        out.append(f"- CRAFTING {rs - cs:.0f} s: wait after submitting {sub}{' (shortened)' if short else ''}")
    if rs and res:
        fin = {e["userId"]: e["t"] for e in ev if e["kind"] == "finish" and rs <= e["t"] <= res}
        waits = {u: round(res - t, 1) for u, t in fin.items()}
        out.append(f"- RACING {res - rs:.0f} s: finished {len(fin)}; wait after own finish {waits}")
    return "\n".join(out)


def main():
    paths = sys.argv[1:] or sorted(glob.glob("reports/studio/*.json"))
    parts = [r for r in (report(p) for p in paths) if r]
    text = "# Idle time per phase (Studio match runs)\n\n" + "\n\n".join(parts) + "\n"
    open("reports/studio/idle.md", "w").write(text)
    print(text)


if __name__ == "__main__":
    main()
