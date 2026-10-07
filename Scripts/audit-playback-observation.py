#!/usr/bin/env python3
"""Read-only joint audit; no process control and no media text in output."""
import argparse
import csv
import datetime
import json
from pathlib import Path


def audit(prefix, source_pid, parent_pid):
    def path(suffix):
        return Path(str(prefix) + suffix)

    def optional_json(suffix):
        p = path(suffix)
        return json.loads(p.read_text()) if p.exists() else None

    resource = optional_json('-long-run.json')
    child = optional_json('-child-observation.json')
    source = optional_json('-source-samples-summary.json')
    stream = optional_json('-source-playback-summary.json')
    if resource is None:
        raise ValueError('Resource summary is missing')
    with path('-long-run.csv').open() as f:
        rows = list(csv.DictReader(f))
    samples = [json.loads(line) for line in path('-source-samples.jsonl').read_text().splitlines()]
    if not rows or not samples:
        raise ValueError('Resource or source samples are empty')
    def timestamp(value):
        return datetime.datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()
    start = max(timestamp(rows[0]['timestamp']), samples[0]['unixTime'])
    end = min(timestamp(rows[-1]['timestamp']), samples[-1]['unixTime'])
    common = [sample for sample in samples if start <= sample['unixTime'] <= end]
    invalid = [dict(index=index, observedSeconds=sample['observedSeconds'])
               for index, sample in enumerate(samples)
               if start <= sample['unixTime'] <= end
               and (sample.get('verifiedQishuiSource') != 'true'
                    or sample.get('isPlaying') != 'true'
                    or sample.get('sourceProcessIdentifier') != str(source_pid))]
    terminal = bool(resource.get('completedAt')) and child is not None and source is not None and stream is not None
    issues = []
    if not terminal:
        issues.append('All four terminal reports are required; an empty interim violations list is not success.')
    if resource.get('pid') != parent_pid or (child and child.get('parentPID') != parent_pid):
        issues.append('Resource/child parent PID mismatch.')
    if not resource.get('processAlive'):
        issues.append('Resource target is not alive in its latest report.')
    issues.extend(resource.get('violations', []))
    if terminal and (not resource.get('completed') or resource['observedDurationSeconds'] < 7200):
        issues.append('Resource observation did not complete the original two-hour duration.')
    if terminal:
        for name, report in [('child', child), ('source', source), ('stream', stream)]:
            if report.get('durationSeconds', 0) < 7200:
                issues.append(name + ' observation did not complete two hours.')
        if source.get('sampleCount') != len(samples):
            issues.append('Terminal source count does not match its sample file.')
        if resource.get('sampleCount') != len(rows):
            issues.append('Terminal resource count does not match its sample file.')
        if stream.get('eventCount', 0) < 1:
            issues.append('Terminal event report has no events.')
        # Recheck the stated gates without selecting a new baseline. Preserve
        # the monitor's original violation list as independent evidence.
        for field, threshold in [('finalRSSGrowthPercent', 15),
                                 ('finalPhysicalFootprintGrowthPercent', 15)]:
            value = resource.get(field)
            if value is None or value > threshold:
                issues.append(field + ' is missing or exceeds the original 15% gate.')
        for field, threshold in [('maximumSustainedCPUAbove5Seconds', 30),
                                 ('maximumSustainedThreadGrowthSeconds', 60),
                                 ('maximumSustainedChildGrowthSeconds', 30)]:
            value = resource.get(field)
            if value is None or value >= threshold:
                issues.append(field + ' is missing or reaches its original time gate.')
        if resource.get('maximumWindowCount') != 1 or resource.get('finalWindowCount') != 1:
            issues.append('Original single-window/final-visible-window gate is not satisfied.')
    overlap = max(0, end - start)
    if overlap < 7200:
        issues.append('Resource/source common interval is shorter than two hours.')
    if invalid:
        issues.append('Some common-interval samples cannot verify source and playing state.')
    if source and source.get('unverifiedOrNotPlayingSamples', 0):
        issues.append('Terminal source report retains unverified/not-playing samples.')
    if source and source.get('lockedUnknownOrIdentityMismatchSamples', 0):
        issues.append('Source observation retains locked, unknown-session or changed-process samples.')
    if stream and (stream.get('exitCode') != 0 or stream.get('unverifiedOrNotPlayingEvents', 0)):
        issues.append('Terminal event observer failed or retained unverified/not-playing events.')
    if child and not child.get('parentAliveAtEnd'):
        issues.append('Fine child observer did not end with the parent alive.')
    # Even clean sampled reports cannot certify playback between samples or
    # an unlocked screen. Keep the full acceptance conclusion separate.
    return dict(
        allFourReportsTerminal=terminal,
        resourceReportedCompleted=resource.get('completed'),
        resourceDurationSeconds=resource['observedDurationSeconds'],
        commonIntervalSeconds=round(overlap, 6),
        sourceStartLagSeconds=round(samples[0]['unixTime'] - timestamp(rows[0]['timestamp']), 6),
        commonSourceSampleCount=len(common),
        maximumCommonSampleGapSeconds=max((b['unixTime'] - a['unixTime']
                                           for a, b in zip(common, common[1:])), default=None),
        unverifiedCommonSamples=invalid,
        resourceFootprintGrowthPercent=resource.get('finalPhysicalFootprintGrowthPercent'),
        originalResourceViolations=resource.get('violations', []),
        issues=issues,
        sampledEvidenceGatesSatisfied=terminal and not issues,
        continuousPlaybackAcceptanceProven=False,
        limitations=[
            'Reports alone do not establish process-handle liveness; poll original handles separately.',
            'Source samples do not prove continuous playing or unlocked interaction between samples.',
            'Event source time is not a receipt wall timestamp and cannot prove exact event overlap.',
            'Fine child evidence cannot replace the original coarse resource gates.',
            'Independent probes add observation load; original baselines and thresholds are preserved.'
        ])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('prefix', type=Path)
    parser.add_argument('--source-pid', required=True, type=int)
    parser.add_argument('--parent-pid', required=True, type=int)
    args = parser.parse_args()
    if args.source_pid <= 0 or args.parent_pid <= 0:
        parser.error('PIDs must be positive')
    try:
        result = audit(args.prefix, args.source_pid, args.parent_pid)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(2, 'Audit indeterminate: ' + type(error).__name__ + '\n')
    print(json.dumps(result, indent=2, ensure_ascii=False))
