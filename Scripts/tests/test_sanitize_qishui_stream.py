import base64
import importlib.util
import json
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'sanitize-qishui-stream.py'
spec = importlib.util.spec_from_file_location('sanitize_stream', path)
sanitize_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sanitize_module)

REAL_A = {'title': '真实歌名甲', 'artist': '真实歌手甲', 'album': '真实专辑甲',
          'duration': 201.5, 'artworkData': base64.b64encode(b'\x89PNG-real-a').decode()}
REAL_B = {'title': '真实歌名乙', 'artist': '真实歌手乙', 'album': '真实专辑乙',
          'duration': 188.25, 'artworkData': base64.b64encode(b'\x89PNG-real-b').decode()}


def record(t, payload, wall=None):
    base = {'bundleIdentifier': 'com.soda.music', 'processIdentifier': 4321,
            'playing': 1, 'playbackRate': 1, 'elapsedTime': 3.0,
            'timestamp': '2026-11-14T05:00:00Z', 'artworkMimeType': 'image/jpeg',
            'contentItemIdentifier': 'B2F1C0DE-REAL-UUID'}
    base.update(payload)
    return {'t': t, 'wall': wall if wall is not None else 1794632400.25 + t,
            'envelope': {'type': 'data', 'diff': False, 'payload': base}}


class SanitizeQishuiStreamTests(unittest.TestCase):
    def setUp(self):
        mixed = dict(REAL_A, title=REAL_B['title'], contentItemIdentifier='NEW-UUID')
        del mixed['artworkData']
        self.records = [
            record(10.0, REAL_A),
            record(10.5, REAL_A),
            record(11.0, mixed),
            record(11.6, dict(REAL_B, contentItemIdentifier='NEW-UUID')),
            record(12.6, dict(REAL_B, contentItemIdentifier='NEW-UUID')),
            {'t': 13.0, 'envelope': {'type': 'error', 'payload': {'title': REAL_A['title']}}},
        ]
        self.fixture = sanitize_module.sanitize(self.records, 'sample', 'two tracks')

    def test_no_real_value_survives(self):
        text = json.dumps(self.fixture, ensure_ascii=False)
        for real in (REAL_A, REAL_B):
            for key in ('title', 'artist', 'album', 'artworkData'):
                self.assertNotIn(real[key], text)
        for leaked in ('B2F1C0DE-REAL-UUID', 'NEW-UUID', '4321', '2026-11-14T05'):
            self.assertNotIn(leaked, text)

    def test_mixed_packet_keeps_its_mixed_shape(self):
        mixed = self.fixture[3]['envelope']['payload']
        self.assertEqual(mixed['title'], 'Title 2')
        self.assertEqual(mixed['artist'], 'Artist 1')
        self.assertEqual(mixed['album'], 'Album 1')
        self.assertEqual(mixed['duration'], 201.5)
        self.assertNotIn('artworkData', mixed)
        complete = self.fixture[4]['envelope']['payload']
        self.assertEqual((complete['title'], complete['artist'], complete['album']),
                         ('Title 2', 'Artist 2', 'Album 2'))
        self.assertEqual(base64.b64decode(complete['artworkData']), b'artwork-2')

    def test_header_lists_tracks_and_pids(self):
        header = self.fixture[0]
        self.assertEqual(header['running_pids'], [1001])
        self.assertEqual(header['tracks'], [
            {'title': 'Title 1', 'artist': 'Artist 1', 'album': 'Album 1',
             'duration': 201.5, 'artwork': 'artwork-1'},
            {'title': 'Title 2', 'artist': 'Artist 2', 'album': 'Album 2',
             'duration': 188.25, 'artwork': 'artwork-2'},
        ])

    def test_times_are_relative_and_non_data_lines_dropped(self):
        steps = self.fixture[1:]
        self.assertEqual([s['t'] for s in steps], [0.0, 0.5, 1.0, 1.6, 2.6])
        self.assertEqual(steps[0]['envelope']['payload']['contentItemIdentifier'], 'item-1')
        self.assertEqual(steps[2]['envelope']['payload']['contentItemIdentifier'], 'item-2')

    def test_timestamp_becomes_arrival_latency(self):
        payload = self.fixture[1]['envelope']['payload']
        self.assertNotIn('timestamp', payload)
        self.assertAlmostEqual(payload['timestampLatency'], 10.25, places=3)

    def test_unknown_keys_are_dropped(self):
        records = [record(0, dict(REAL_A, radioStationName='私人电台'))]
        payload = sanitize_module.sanitize(records, 'x', 'y')[1]['envelope']['payload']
        self.assertNotIn('radioStationName', payload)


if __name__ == '__main__':
    unittest.main()
