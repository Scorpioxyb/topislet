#!/usr/bin/env python3
"""Record the raw Qishui MediaRemote stream with receive timestamps.

Read-only: runs the same `stream-client` command the app runs, sends no
control, never launches or restarts Qishui. The raw capture contains real
titles, artists and artwork, so it must stay in LocalData/ and is turned into
a committable fixture only by `sanitize-qishui-stream.py`.

Usage:
  python3 Scripts/capture-qishui-stream.py --duration 300 \
      --output LocalData/qa/<date>-stream-capture/raw.jsonl
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import select
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADAPTER_CANDIDATES = [
    pathlib.Path("/Applications/顶屿.app/Contents/Resources/MediaRemoteAdapter"),
    ROOT / "Vendor/MediaRemoteAdapter",
]


def adapter_root() -> pathlib.Path:
    for root in ADAPTER_CANDIDATES:
        if (root / "mediaremote-adapter.pl").exists() and (root / "MediaRemoteAdapter.framework").exists():
            return root
    sys.exit("MediaRemote adapter not found")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--duration", type=float, default=300, help="seconds to record")
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()

    root = adapter_root()
    command = [
        "/usr/bin/perl",
        str(root / "mediaremote-adapter.pl"),
        str(root / "MediaRemoteAdapter.framework"),
        "stream-client",
        "com.soda.music",
        "--debounce=40",
        "--no-diff",
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    count = 0
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0) as process, \
            args.output.open("w", encoding="utf-8") as out:
        assert process.stdout is not None
        buffer = b""
        try:
            while (remaining := args.duration - (time.monotonic() - started)) > 0:
                # A paused player sends nothing; never block past the duration.
                ready, _, _ = select.select([process.stdout], [], [], min(remaining, 1.0))
                if not ready:
                    continue
                chunk = os.read(process.stdout.fileno(), 1 << 20)
                if not chunk:
                    break
                received = time.monotonic() - started
                wall = time.time()
                buffer += chunk
                *lines, buffer = buffer.split(b"\n")
                for line in lines:
                    try:
                        envelope = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    record = {"t": round(received, 4), "wall": round(wall, 4), "envelope": envelope}
                    out.write(json.dumps(record, ensure_ascii=False) + "\n")
                    count += 1
                out.flush()
        finally:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
    print(f"recorded {count} envelopes in {time.monotonic() - started:.1f}s -> {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
