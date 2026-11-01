#!/usr/bin/env python3
"""Is the live game up to date? Compares the published place's last update
(Roblox's public games API) with the last merge on origin/main, and checks
the server size against Constants.MAX_PLAYERS.

    python3 tools/live_check.py

"updated" moves on every publish (and on some settings saves), so a live
game older than the last merge certainly lacks it; a newer one most likely
has it (sync with Rojo before publishing: docs/launch.md).
"""
import datetime
import json
import re
import subprocess
import sys
import urllib.request

UNIVERSE = 9983801557
PLACE = 74883519312765


def get(url):
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.load(r)


def when(s):
    return datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))


def main():
    g = get("https://games.roblox.com/v1/games?universeIds=%d" % UNIVERSE)["data"][0]
    subprocess.run(["git", "fetch", "-q", "origin", "main"], check=False)
    line = subprocess.run(["git", "log", "-1", "--format=%cI|%h %s", "origin/main"],
                          capture_output=True, text=True).stdout.strip()
    merged_at, last = line.split("|", 1)
    live, merged = when(g["updated"]), when(merged_at)
    consts = open("roblox/ReplicatedStorage/Shared/Constants.lua").read()
    m = re.search(r"Constants\.MAX_PLAYERS\s*=\s*(\d+)", consts)
    max_players = int(m.group(1)) if m else 10
    local = lambda t: t.astimezone().strftime("%Y-%m-%d %H:%M")
    print("game:        %s  https://www.roblox.com/games/%d" % (g["name"], PLACE))
    print("live update: %s" % local(live))
    print("last merge:  %s  %s" % (local(merged), last))
    ok = True
    if live < merged:
        print("NOT LIVE: the last merge came after the last publish (sync with Rojo, then File > Publish)")
        ok = False
    else:
        print("published after the last merge")
    if g.get("maxPlayers") != max_players:
        print("SERVER SIZE: %s on the dashboard, the game is made for %d (Studio: File > Game Settings > Places > the place > Max Players)"
              % (g.get("maxPlayers"), max_players))
        ok = False
    print("playing now: %s, visits: %s" % (g.get("playing"), g.get("visits")))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
