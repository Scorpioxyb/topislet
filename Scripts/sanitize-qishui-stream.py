#!/usr/bin/env python3
"""Turn a raw Qishui stream capture into a committable replay fixture.

Input is the JSON-lines file written by `capture-qishui-stream.py` (it holds
real titles, artists and artwork and must stay in LocalData/). Output is a
fixture for `Tests/Fixtures/streams/`:

- titles become "Title N", numbered by first appearance;
- each artist, album, duration and artwork is attributed to the title it
  appears with most often, so a mixed transition packet (new title, old
  artist) keeps its mixed shape: "Title 2" with "Artist 1";
- artwork bytes become base64 of "artwork-N"; content item ids become
  "item-N"; PIDs become 1001, 1002, ...;
- the source `timestamp` becomes `timestampLatency`, seconds between the
  source event and its arrival, so replay keeps the timeline relationship;
- times are relative to the first kept envelope; unknown payload keys are
  dropped rather than risk carrying personal data.

The header's `tracks` table lists every synthetic track, which the replay
test uses to reject any published mix of two tracks.
"""

from __future__ import annotations

import argparse
import base64
import collections
import datetime as dt
import json
import pathlib
import sys

NUMERIC_KEYS = {"duration", "elapsedTime", "elapsedTimeNow", "playbackRate", "playing"}
PASSTHROUGH_KEYS = {"bundleIdentifier", "artworkMimeType"}


def parse_timestamp(text: str) -> float | None:
    try:
        return dt.datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def artwork_payload(tag: str) -> str:
    return base64.b64encode(tag.encode()).decode()


class Numbering:
    def __init__(self, prefix: str, start: int = 1):
        self.prefix, self.next, self.map = prefix, start, {}

    def __call__(self, value):
        if value not in self.map:
            self.map[value] = f"{self.prefix}{self.next}" if self.prefix else self.next
            self.next += 1
        return self.map[value]


def sanitize(records: list[dict], name: str, description: str) -> list[dict]:
    payloads = [r["envelope"].get("payload", {}) for r in records
                if r.get("envelope", {}).get("type") == "data"]

    title_number = Numbering("")
    for payload in payloads:
        if isinstance(payload.get("title"), str) and payload["title"].strip():
            title_number(payload["title"])

    # Attribute each other field to the title it co-occurs with most often.
    co = {key: collections.defaultdict(collections.Counter)
          for key in ("artist", "album", "duration", "artworkData")}
    for payload in payloads:
        title = payload.get("title")
        if title not in title_number.map:
            continue
        for key in co:
            if key in payload and payload[key] not in (None, ""):
                co[key][payload[key]][title_number.map[title]] += 1

    def owner(key, value):
        counts = co[key].get(value)
        return counts.most_common(1)[0][0] if counts else None

    extra = Numbering("", start=len(title_number.map) + 1)
    item_number = Numbering("item-")
    pid_number = Numbering("", start=1001)

    def synthetic(key, value):
        number = owner(key, value) or extra((key, value))
        if key == "artist":
            return f"Artist {number}"
        if key == "album":
            return f"Album {number}"
        if key == "artworkData":
            return artwork_payload(f"artwork-{number}")
        return value

    tracks: dict[int, dict] = {n: {"title": f"Title {n}"} for n in title_number.map.values()}
    for key, field in (("artist", "artist"), ("album", "album"),
                       ("duration", "duration"), ("artworkData", "artwork")):
        for value, counts in co[key].items():
            n = counts.most_common(1)[0][0]
            if field == "duration":
                tracks[n][field] = value
            elif field == "artwork":
                tracks[n][field] = f"artwork-{n}"
            else:
                tracks[n][field] = synthetic(key, value)

    out: list[dict] = [{
        "fixture": name,
        "description": description,
        "running_pids": [],
        "tracks": [tracks[n] for n in sorted(tracks)],
    }]
    start = None
    pids = []
    for record in records:
        envelope = record.get("envelope", {})
        if envelope.get("type") != "data":
            continue
        payload = envelope.get("payload", {})
        start = record["t"] if start is None else start
        clean = {}
        for key, value in payload.items():
            if key == "title":
                clean[key] = f"Title {title_number(value)}" if isinstance(value, str) and value.strip() else value
            elif key in ("artist", "album", "artworkData"):
                clean[key] = synthetic(key, value) if value not in (None, "") else value
            elif key == "contentItemIdentifier":
                clean[key] = item_number(value)
            elif key == "processIdentifier":
                clean[key] = pid_number(value)
                if clean[key] not in pids:
                    pids.append(clean[key])
            elif key == "timestamp":
                source = parse_timestamp(value) if isinstance(value, str) else None
                if source is not None and "wall" in record:
                    clean["timestampLatency"] = round(record["wall"] - source, 3)
            elif key in NUMERIC_KEYS or key in PASSTHROUGH_KEYS:
                clean[key] = value
        out.append({
            "t": round(record["t"] - start, 4),
            "envelope": {"type": "data", "diff": bool(envelope.get("diff", False)), "payload": clean},
        })
    out[0]["running_pids"] = pids
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("raw", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--name", required=True)
    parser.add_argument("--description", required=True)
    parser.add_argument("--start", type=float, default=0, help="first capture second to keep")
    parser.add_argument("--end", type=float, default=float("inf"), help="last capture second to keep")
    args = parser.parse_args()

    records = [json.loads(line) for line in args.raw.read_text(encoding="utf-8").splitlines() if line.strip()]
    records = [r for r in records if args.start <= r["t"] <= args.end]
    if not records:
        sys.exit("no envelopes in the selected range")
    fixture = sanitize(records, args.name, args.description)
    args.output.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in fixture), encoding="utf-8")
    print(f"{len(fixture) - 1} steps, {len(fixture[0]['tracks'])} tracks -> {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
