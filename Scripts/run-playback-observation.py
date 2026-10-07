#!/usr/bin/env python3
"""Launch bounded, read-only joint observers. Never launch or control the product/source."""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
import math
import os
import re
import signal
import selectors
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = Path('/Applications/顶屿.app/Contents/MacOS/MacBookIsland')
ALLOWED = {'mediaRemoteAvailable', 'verifiedQishuiSource', 'isPlaying',
           'elapsedTime', 'duration', 'sourceProcessIdentifier'}


def fields(text):
    # Never persist media text, artwork URLs, account/configuration or diagnostics.
    result = {}
    for line in text.splitlines():
        key, separator, value = line.partition('=')
        if not separator or key not in ALLOWED:
            continue
        if key in {'mediaRemoteAvailable', 'verifiedQishuiSource', 'isPlaying'}:
            if value in {'true', 'false'}:
                result[key] = value
        elif key == 'sourceProcessIdentifier':
            if value.isascii() and value.isdigit() and len(value) <= 10 and 0 < int(value) <= 2**31 - 1:
                result[key] = str(int(value))
        else:
            try:
                number = float(value)
                if math.isfinite(number) and number >= 0:
                    result[key] = str(number)
            except ValueError:
                pass
    return result


def verified(record, source_pid):
    return (record.get('verifiedQishuiSource') == 'true'
            and record.get('isPlaying') == 'true'
            and record.get('sourceProcessIdentifier') == str(source_pid))


def source_preflight(source_pid):
    result = subprocess.run([str(APP), '--adapter-status'], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=8)
    record = fields(result.stdout)
    record['exitCode'] = result.returncode
    if result.returncode != 0 or not verified(record, source_pid):
        raise ValueError('trusted target source is not playing; observers not started')
    return record


def write_new(path, value):
    with path.open('x') as handle:
        json.dump(value, handle, indent=2)
        handle.write('\n')


def prepare():
    sources = ['monitor-long-run.swift', 'observe-process-children.swift',
               'playback-observation-session.swift']
    digest = hashlib.sha256(b''.join((ROOT / 'Scripts' / s).read_bytes()
                                    for s in sources)).hexdigest()[:16]
    directory = ROOT / '.build/qa/observer-tools' / digest
    directory.mkdir(parents=True, exist_ok=True)
    binaries = []
    for source in sources:
        output = directory / Path(source).stem
        if not output.exists():
            subprocess.run(['swiftc', str(ROOT / 'Scripts' / source), '-o', str(output)],
                           check=True, stdout=subprocess.DEVNULL)
        binaries.append(output)
    return binaries


def session_state(binary):
    return json.loads(subprocess.check_output([str(binary)], text=True, timeout=8))


def process_identity(state, key, pid):
    matches = [row for row in state.get(key, []) if row.get('pid') == pid]
    return matches[0] if len(matches) == 1 else None


def unlocked(state):
    return (state.get('sessionKnown') is True and state.get('locked') is False
            and state.get('frontIsLoginWindow') is False)


def sample_source(prefix, source_pid, parent_pid, duration, session_binary, identities):
    start = time.monotonic()
    count = invalid = bad_session = 0
    previous = None
    max_gap = 0.0
    with Path(str(prefix) + '-source-samples.jsonl').open('x') as handle:
        while True:
            tick = time.monotonic()
            record = {'unixTime': time.time(), 'observedSeconds': tick - start}
            if previous is not None:
                max_gap = max(max_gap, tick - previous)
            previous = tick
            try:
                state = session_state(session_binary)
                record['sessionUnlocked'] = unlocked(state)
                record['processIdentitiesMatch'] = (
                    process_identity(state, 'islandProcesses', parent_pid) == identities[0]
                    and process_identity(state, 'sourceProcesses', source_pid) == identities[1])
                result = subprocess.run([str(APP), '--adapter-status'], text=True,
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=8)
                record.update(fields(result.stdout))
                record['exitCode'] = result.returncode
                # The status read may block: also record receipt time, not just invocation time.
                record['receivedUnixTime'] = time.time()
            except (subprocess.TimeoutExpired, subprocess.CalledProcessError, ValueError):
                record['probeFailed'] = True
            count += 1
            invalid += not verified(record, source_pid)
            bad_session += not (record.get('sessionUnlocked') is True
                                and record.get('processIdentitiesMatch') is True)
            handle.write(json.dumps(record, separators=(',', ':')) + '\n')
            handle.flush()
            if tick - start >= duration:
                break
            time.sleep(max(0, min(5 - (time.monotonic() - tick), duration - (time.monotonic() - start))))
    summary = {'durationSeconds': time.monotonic() - start, 'sampleCount': count,
               'unverifiedOrNotPlayingSamples': invalid, 'lockedUnknownOrIdentityMismatchSamples': bad_session,
               'maximumSampleGapSeconds': max_gap,
               'limitation': 'Sampled state only; no proof between samples. Probe loads are external to target.'}
    write_new(Path(str(prefix) + '-source-samples-summary.json'), summary)
    return summary


def event_source(prefix, source_pid, duration):
    start = time.monotonic()
    # Binary CLI owns its two read-only adapter children; watchdog only controls this observer.
    process = subprocess.Popen([str(APP), '--adapter-watch', str(math.ceil(duration))],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               start_new_session=True)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    buffer = b''
    current = None
    count = invalid = 0
    last = None
    max_gap = 0.0
    timed_out = False
    line_limit_exceeded = False
    with Path(str(prefix) + '-source-playback.jsonl').open('x') as handle:
        def save():
            nonlocal count, invalid, last, max_gap
            if current is None:
                return
            if last is not None:
                max_gap = max(max_gap, current['observedSeconds'] - last)
            last = current['observedSeconds']
            count += 1
            invalid += not verified(current, source_pid) or current.get('eventTime') is None
            handle.write(json.dumps(current, separators=(',', ':')) + '\n')
            handle.flush()

        while True:
            if time.monotonic() - start > duration + 15:
                timed_out = True
                os.killpg(process.pid, signal.SIGTERM)
                break
            ready = selector.select(timeout=1)
            if not ready:
                if process.poll() is not None:
                    break
                continue
            chunk = process.stdout.read1(65536)
            if not chunk:
                break
            buffer += chunk
            if len(buffer) > 1024 * 1024:
                os.killpg(process.pid, signal.SIGTERM)
                line_limit_exceeded = True
                break
            while b'\n' in buffer:
                line, buffer = buffer.split(b'\n', 1)
                text = line.decode('utf-8', errors='replace')
                if text.startswith('EVENT '):
                    save()
                    try:
                        timestamp = datetime.datetime.fromisoformat(text[6:].replace('Z', '+00:00'))
                        event_time = timestamp.isoformat() if timestamp.tzinfo is not None else None
                    except ValueError:
                        event_time = None
                    current = {'eventTime': event_time, 'unixTime': time.time(),
                               'observedSeconds': time.monotonic() - start}
                elif current is not None:
                    current.update(fields(text))
        save()
    selector.close()
    process.stdout.close()
    try:
        code = process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        # Only the observer we spawned; never the product/source process.
        os.killpg(process.pid, signal.SIGKILL)
        code = process.wait()
    summary = {'durationSeconds': time.monotonic() - start, 'exitCode': code,
               'eventCount': count, 'unverifiedOrNotPlayingEvents': invalid,
               'maximumEventGapSeconds': max_gap, 'watchdogTimedOut': timed_out,
               'lineLimitExceeded': line_limit_exceeded,
               'limitation': 'Receipt wall time recorded; events do not prove playback between events.'}
    write_new(Path(str(prefix) + '-source-playback-summary.json'), summary)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--prefix', type=Path)
    parser.add_argument('--parent-pid', type=int)
    parser.add_argument('--source-pid', type=int)
    parser.add_argument('--expected-build', type=int)
    parser.add_argument('--duration', type=float, default=7215)
    args = parser.parse_args()
    binaries = prepare()
    if args.prepare_only:
        print(json.dumps({'preparedOnly': True, 'observersStarted': False,
                          'tools': [str(p.relative_to(ROOT)) for p in binaries]}))
        return
    if not args.prefix or not args.parent_pid or not args.source_pid or not args.expected_build:
        parser.error('prefix, expected build and both PIDs are required')
    if min(args.parent_pid, args.source_pid) <= 0 or not math.isfinite(args.duration) or args.duration < 7200:
        parser.error('positive PIDs and a finite duration >=7200 seconds required')
    prefix = args.prefix.resolve()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]*', prefix.name):
        parser.error('prefix basename must contain only letters, numbers, underscores and hyphens')
    prefix.parent.mkdir(parents=True, exist_ok=True)
    if list(prefix.parent.glob(prefix.name + '-*')):
        parser.error('existing observation prefix; inspect original process/handle, do not restart it')
    state = session_state(binaries[2])
    identities = [process_identity(state, 'islandProcesses', args.parent_pid),
                  process_identity(state, 'sourceProcesses', args.source_pid)]
    if (not unlocked(state) or any(identity is None or not isinstance(identity.get('launchUnixTime'), (int, float))
                                  for identity in identities)
            or len(state.get('islandProcesses', [])) != 1 or len(state.get('sourceProcesses', [])) != 1):
        parser.error('session locked/unknown or target identity unavailable; observers not started')
    installed_build = int(subprocess.check_output(
        ['/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleVersion',
         str(APP.parent.parent / 'Info.plist')], text=True, timeout=5).strip())
    if installed_build != args.expected_build:
        parser.error('installed build mismatch; observers not started')
    try:
        playback = source_preflight(args.source_pid)
    except (ValueError, subprocess.TimeoutExpired, OSError):
        parser.error('trusted target source is not playing or probe failed; observers not started')
    # Status can take time. Recheck the session/instance before writing a receipt
    # or creating observers, rather than trusting the earlier session snapshot.
    final_state = session_state(binaries[2])
    if (not unlocked(final_state)
            or process_identity(final_state, 'islandProcesses', args.parent_pid) != identities[0]
            or process_identity(final_state, 'sourceProcesses', args.source_pid) != identities[1]):
        parser.error('session or process identity changed during preflight; observers not started')
    receipt = {'startedUnixTime': time.time(), 'durationSeconds': args.duration,
               'sourcePreflight': playback,
               'installedBuild': installed_build, 'binarySHA256': hashlib.sha256(APP.read_bytes()).hexdigest(),
               'processIdentities': identities, 'allObserversTerminal': False,
               'finalAccepted': False, 'limitation': '15-second padding is not a pass; audit measured overlap.'}
    write_new(Path(str(prefix) + '-launch-receipt.json'), receipt)
    commands = [
        [str(binaries[0]), '--pid', str(args.parent_pid), '--duration', str(args.duration),
         '--interval', '5', '--output', str(prefix) + '-long-run.json'],
        [str(binaries[1]), str(args.parent_pid), str(args.duration), '0.1', str(prefix) + '-child-observation.json']]
    processes = []
    handles = []
    try:
        for index, command in enumerate(commands):
            handle = Path(str(prefix) + f'-observer{index}.log').open('x')
            handles.append(handle)
            processes.append(subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT))
        print(json.dumps({'observationPIDs': [p.pid for p in processes],
                          'parentPID': args.parent_pid, 'sourcePID': args.source_pid}), flush=True)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            source = pool.submit(sample_source, prefix, args.source_pid, args.parent_pid,
                                 args.duration, binaries[2], identities)
            stream = pool.submit(event_source, prefix, args.source_pid, args.duration)
            codes = [p.wait(timeout=args.duration + 30) for p in processes]
            reports = [source.result(), stream.result()]
        receipt.update(allObserversTerminal=True, observerExitCodes=codes,
                       completedUnixTime=time.time(),
                       sourceSessionIssues=reports[0]['lockedUnknownOrIdentityMismatchSamples'])
        write_new(Path(str(prefix) + '-terminal-receipt.json'), receipt)
        audit = subprocess.run([sys.executable, str(ROOT / 'Scripts/audit-playback-observation.py'),
                                str(prefix), '--source-pid', str(args.source_pid),
                                '--parent-pid', str(args.parent_pid)],
                               text=True, capture_output=True, timeout=30)
        if audit.returncode == 0:
            write_new(Path(str(prefix) + '-joint-audit.json'), json.loads(audit.stdout))
        else:
            write_new(Path(str(prefix) + '-joint-audit-error.json'), {'exitCode': audit.returncode,
                                                                    'acceptanceIndeterminate': True})
        print(json.dumps({'allObserversTerminal': True, 'observerExitCodes': codes,
                          'sourceSessionIssues': receipt['sourceSessionIssues'], 'finalAccepted': False}), flush=True)
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
        for handle in handles:
            handle.close()


if __name__ == '__main__':
    main()
