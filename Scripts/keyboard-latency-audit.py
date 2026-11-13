#!/usr/bin/env python3
"""Layered latency audit for physical media keys, read-only.

Reads the unified log (it never sends a key, a MediaRemote command or an AX
action) and pairs each physical media-key press with what followed:

  key    rcd "Request: Command = <...>"  (the HID media-key daemon; its first
         log line is the earliest timestamp available without Input Monitoring)
  route  mediaremoted "Request: sendRemoteControlCommand<id> for <bundle>"
  source mediaremoted NowPlaying change for that bundle (playback state for
         play/pause, now-playing item for next/previous)
  island first TopIslet ui_published that reflects the change

Only Qishui (com.soda.music) presses get source/island columns; presses routed
to other players are counted so a mis-routed key is visible. Output holds no
track, artist or lyric content: TopIslet logs carry only hashes, and this
script prints event timings alone.

  Scripts/keyboard-latency-audit.py --last 3d
  Scripts/keyboard-latency-audit.py --file saved-log.txt
"""
import argparse
import datetime
import re
import statistics
import subprocess
import sys

QISHUI = "com.soda.music"
WINDOW = 3.0  # seconds after the key to look for a source / island reaction
PREDICATE = ('process == "rcd" OR (process == "mediaremoted" AND subsystem == '
             '"com.apple.amp.mediaremote" AND (category == "rr" OR category == '
             '"NowPlaying")) OR subsystem == "io.github.scorpioxyb.topislet"')

LINE = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}) \S+\s+(\S+?)\[")
KEY = re.compile(r"Request: Command = <(\w+)>.*commandID = <([0-9A-F-]+)>")
ROUTE = re.compile(r"Request: sendRemoteControlCommand<([0-9A-F-]+)> for .*?(com\.[\w.]+) \(")
STATE = re.compile(r"PlaybackState changed from (\w+) to (\w+) for .*?(com\.[\w.]+) \(")
ITEM = re.compile(r"setting nowPlayingItem from .*?(com\.[\w.]+) \(|"
                  r"Set: .*?(com\.[\w.]+) \(.*setting nowPlayingItem from ")
UI = re.compile(r"event=ui_published .*playback=(\w+) source=qishui track=(\w+)")
TRACK_CHANGE = {"NextTrack", "PreviousTrack"}
TOGGLE = {"TogglePlayPause", "Play", "Pause"}


def parse_time(text):
    return datetime.datetime.strptime(text, "%Y-%m-%d %H:%M:%S.%f")


def events(lines):
    """Yield (time, process, message) for timestamped lines only."""
    for line in lines:
        match = LINE.match(line)
        if match:
            yield parse_time(match.group(1)), match.group(2), line


def audit(lines):
    rows, keys, routes = [], {}, {}
    stream = list(events(lines))
    for index, (when, process, line) in enumerate(stream):
        if process == "rcd" and (m := KEY.search(line)):
            keys.setdefault(m.group(2), (when, m.group(1), index))
        elif process == "mediaremoted" and (m := ROUTE.search(line)):
            routes.setdefault(m.group(1), (when, m.group(2), index))

    for command_id, (key_time, command, key_index) in sorted(keys.items(), key=lambda kv: kv[1][0]):
        row = {"time": key_time, "command": command, "target": None,
               "route_ms": None, "source_ms": None, "island_ms": None, "island_state": None}
        rows.append(row)
        if command_id not in routes:
            continue
        route_time, target, route_index = routes[command_id]
        row["target"] = target
        row["route_ms"] = ms(key_time, route_time)
        if target != QISHUI:
            continue
        last_track = previous_island_track(stream, key_index)
        source_time = None
        for when, process, line in stream[route_index:]:
            if when - key_time > datetime.timedelta(seconds=WINDOW):
                break
            if process == "mediaremoted" and source_time is None and QISHUI in line:
                if command in TOGGLE and STATE.search(line):
                    source_time = when
                elif command in TRACK_CHANGE and ITEM.search(line):
                    source_time = when
                if source_time:
                    row["source_ms"] = ms(key_time, source_time)
            if process == "MacBookIsland" and (m := UI.search(line)):
                changed = (m.group(2) != last_track) if command in TRACK_CHANGE else True
                if changed and (source_time is not None or command in TRACK_CHANGE):
                    row["island_ms"] = ms(key_time, when)
                    row["island_state"] = m.group(1)
                    break
    return rows


def previous_island_track(stream, before):
    for _, process, line in reversed(stream[:before]):
        if process == "MacBookIsland" and (m := UI.search(line)):
            return m.group(2)
    return None


def ms(start, end):
    return round((end - start).total_seconds() * 1000)


def summary(values):
    values = [v for v in values if v is not None]
    if not values:
        return "n=0"
    return f"n={len(values)} median={statistics.median(values):.0f}ms max={max(values)}ms"


def report(rows):
    out = ["| 时间 | 命令 | 目标 | 路由 ms | 汽水 ms | 顶屿 ms | 顶屿状态 |",
           "| --- | --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        cells = [r["time"].strftime("%m-%d %H:%M:%S.%f")[:-3], r["command"], r["target"] or "未路由",
                 r["route_ms"], r["source_ms"], r["island_ms"], r["island_state"]]
        out.append("| " + " | ".join("—" if c is None else str(c) for c in cells) + " |")
    qishui = [r for r in rows if r["target"] == QISHUI]
    island_after_source = [r["island_ms"] - r["source_ms"] for r in qishui
                           if r["island_ms"] is not None and r["source_ms"] is not None]
    out += ["",
            f"按键 {len(rows)} 次，路由到汽水 {len(qishui)} 次，其他播放器 "
            f"{sum(1 for r in rows if r['target'] and r['target'] != QISHUI)} 次，未见路由 "
            f"{sum(1 for r in rows if not r['target'])} 次。",
            f"- 按键→路由：{summary(r['route_ms'] for r in qishui)}",
            f"- 按键→汽水状态：{summary(r['source_ms'] for r in qishui)}",
            f"- 按键→顶屿发布：{summary(r['island_ms'] for r in qishui)}",
            f"- 汽水状态→顶屿发布：{summary(island_after_source)}",
            f"- 汽水已变化但 {WINDOW:.0f} 秒内顶屿无发布："
            f"{sum(1 for r in qishui if r['source_ms'] is not None and r['island_ms'] is None)} 次"]
    return "\n".join(out)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--last", default="1d", help="log show --last value (default 1d)")
    source.add_argument("--file", help="read a saved `log show --style compact` dump instead")
    args = parser.parse_args(argv)
    if args.file:
        with open(args.file, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    else:
        lines = subprocess.run(["/usr/bin/log", "show", "--last", args.last, "--style", "compact",
                                "--predicate", PREDICATE],
                               capture_output=True, text=True, check=True).stdout.splitlines()
    print(report(audit(lines)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
