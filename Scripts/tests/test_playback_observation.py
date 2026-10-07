import importlib.util
import datetime
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import subprocess

path = Path(__file__).resolve().parents[1] / 'run-playback-observation.py'
spec = importlib.util.spec_from_file_location('observation', path)
observation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(observation)
audit_spec = importlib.util.spec_from_file_location('joint_audit', path.parent / 'audit-playback-observation.py')
joint_audit = importlib.util.module_from_spec(audit_spec)
audit_spec.loader.exec_module(joint_audit)


class ObservationPrivacyAndEvidenceTests(unittest.TestCase):
    def test_paused_or_failed_preflight_cannot_start_observation(self):
        paused = subprocess.CompletedProcess([], 0, stdout='verifiedQishuiSource=true\nisPlaying=false\nsourceProcessIdentifier=42\n')
        failed = subprocess.CompletedProcess([], 1, stdout='verifiedQishuiSource=true\nisPlaying=true\nsourceProcessIdentifier=42\n')
        for result in [paused, failed]:
            with patch.object(observation.subprocess, 'run', return_value=result):
                with self.assertRaises(ValueError):
                    observation.source_preflight(42)

    def test_trusted_playing_preflight_retains_only_validated_fields(self):
        result = subprocess.CompletedProcess([], 0, stdout='verifiedQishuiSource=true\nisPlaying=true\nsourceProcessIdentifier=42\ncurrentTrack=PRIVATE\n')
        with patch.object(observation.subprocess, 'run', return_value=result):
            record = observation.source_preflight(42)
        self.assertTrue(observation.verified(record, 42))
        self.assertNotIn('PRIVATE', str(record))

    def test_status_output_cannot_persist_media_or_account_content(self):
        raw = ('currentTrack=PRIVATE_TITLE\nartworkURL=https://private.example/token\n'
               'diagnostic=PRIVATE_ACCOUNT\nverifiedQishuiSource=true\n'
               'isPlaying=true\nsourceProcessIdentifier=42\n')
        parsed = observation.fields(raw)
        self.assertTrue(observation.verified(parsed, 42))
        self.assertNotIn('PRIVATE', str(parsed))
        self.assertNotIn('https://', str(parsed))

    def test_wrong_source_and_sparse_status_cannot_pass(self):
        playing = {'verifiedQishuiSource': 'true', 'isPlaying': 'true', 'sourceProcessIdentifier': '43'}
        self.assertFalse(observation.verified(playing, 42))
        self.assertFalse(observation.verified({'sourceProcessIdentifier': '42'}, 42))

    def test_malformed_values_under_whitelisted_keys_are_not_saved(self):
        parsed = observation.fields('isPlaying=PRIVATE_VALUE\nelapsedTime=PRIVATE_CONTENT\n'
                                    'duration=nan\nsourceProcessIdentifier=ACCOUNT_ID\n')
        self.assertEqual(parsed, {})

    def test_unknown_session_and_login_window_are_ineligible(self):
        self.assertFalse(observation.unlocked({}))
        self.assertFalse(observation.unlocked({'sessionKnown': True, 'locked': False,
                                              'frontIsLoginWindow': True}))
        self.assertFalse(observation.unlocked({'sessionKnown': True, 'locked': True,
                                              'frontIsLoginWindow': False}))

    def test_duplicate_pid_identity_is_not_accepted(self):
        state = {'sourceProcesses': [{'pid': 42, 'launchUnixTime': 1},
                                     {'pid': 42, 'launchUnixTime': 2}]}
        self.assertIsNone(observation.process_identity(state, 'sourceProcesses', 42))

    def test_saved_observation_cannot_be_overwritten(self):
        # Retain the tiny fixture; ordinary cleanup uses Trash, never an
        # automatic irreversible TemporaryDirectory cleanup.
        target = Path(tempfile.mkdtemp(prefix='topislet-observation-test-')) / 'receipt.json'
        observation.write_new(target, {'original': True})
        with self.assertRaises(FileExistsError):
            observation.write_new(target, {'original': False})
        self.assertIn('true', target.read_text())

    def test_event_boundaries_flush_last_record_without_media_content(self):
        directory = Path(tempfile.mkdtemp(prefix='topislet-event-fixture-'))
        executable = directory / 'synthetic-observer'
        executable.write_text('#!/usr/bin/env python3\n'
                              'print("EVENT 2026-10-01T00:00:00Z")\n'
                              'print("verifiedQishuiSource=true")\n'
                              'print("isPlaying=true")\n'
                              'print("sourceProcessIdentifier=42")\n'
                              'print("currentTrack=PRIVATE_TITLE")\n'
                              'print("EVENT 2026-10-01T00:00:01Z")\n'
                              'print("verifiedQishuiSource=true")\n'
                              'print("isPlaying=false")\n'
                              'print("sourceProcessIdentifier=42")\n')
        executable.chmod(0o700)
        original = observation.APP
        observation.APP = executable
        try:
            result = observation.event_source(directory / 'probe', 42, 0.1)
        finally:
            observation.APP = original
        self.assertEqual(result['exitCode'], 0)
        self.assertEqual(result['eventCount'], 2)
        self.assertEqual(result['unverifiedOrNotPlayingEvents'], 1)
        text = (directory / 'probe-source-playback.jsonl').read_text()
        rows = [json.loads(line) for line in text.splitlines()]
        self.assertEqual(len(rows), 2)
        self.assertTrue(all(row['unixTime'] > 0 for row in rows))
        self.assertNotIn('PRIVATE_TITLE', text)

    def test_joint_audit_rejects_locked_sample_and_preserves_memory_failure(self):
        directory = Path(tempfile.mkdtemp(prefix='topislet-joint-audit-fixture-'))
        prefix = directory / 'probe'
        resource = {'pid': 41, 'completedAt': '2026-10-01T02:00:00Z', 'completed': True,
                    'observedDurationSeconds': 7200, 'processAlive': True, 'sampleCount': 1441,
                    'violations': ['original memory failure'], 'finalRSSGrowthPercent': 0,
                    'finalPhysicalFootprintGrowthPercent': 45,
                    'maximumSustainedCPUAbove5Seconds': 0, 'maximumSustainedThreadGrowthSeconds': 0,
                    'maximumSustainedChildGrowthSeconds': 0, 'maximumWindowCount': 1, 'finalWindowCount': 1}
        fixtures = {'-long-run.json': resource,
                    '-child-observation.json': {'parentPID': 41, 'durationSeconds': 7200,
                                                'parentAliveAtEnd': True},
                    '-source-samples-summary.json': {'durationSeconds': 7200, 'sampleCount': 1441,
                                                     'unverifiedOrNotPlayingSamples': 0,
                                                     'lockedUnknownOrIdentityMismatchSamples': 1},
                    '-source-playback-summary.json': {'durationSeconds': 7200, 'exitCode': 0,
                                                      'eventCount': 1, 'unverifiedOrNotPlayingEvents': 0}}
        for suffix, value in fixtures.items():
            observation.write_new(Path(str(prefix) + suffix), value)
        epoch = datetime.datetime(2026, 10, 1, tzinfo=datetime.timezone.utc).timestamp()
        with Path(str(prefix) + '-long-run.csv').open('x') as resource_file, \
                Path(str(prefix) + '-source-samples.jsonl').open('x') as source_file:
            resource_file.write('timestamp\n')
            for index in range(1441):
                timestamp = epoch + index * 5
                resource_file.write(datetime.datetime.fromtimestamp(timestamp, datetime.timezone.utc).isoformat() + '\n')
                source_file.write(json.dumps({'unixTime': timestamp, 'observedSeconds': index * 5,
                                              'verifiedQishuiSource': 'true', 'isPlaying': 'true',
                                              'sourceProcessIdentifier': '42'}) + '\n')
        result = joint_audit.audit(prefix, 42, 41)
        self.assertTrue(result['allFourReportsTerminal'])
        self.assertFalse(result['sampledEvidenceGatesSatisfied'])
        self.assertFalse(result['continuousPlaybackAcceptanceProven'])
        self.assertEqual(result['originalResourceViolations'], ['original memory failure'])
        self.assertTrue(any('locked' in issue for issue in result['issues']))
        self.assertTrue(any('15%' in issue for issue in result['issues']))


if __name__ == '__main__':
    unittest.main()
