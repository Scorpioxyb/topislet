import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'keyboard-latency-audit.py'
spec = importlib.util.spec_from_file_location('keyboard_audit', path)
audit_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit_module)

ID = '284BC57E-83E7-4865-ABCA-3576CC0B1F6D'
OTHER = 'CC572F3F-4BC5-486A-8042-E87370F9F256'
QISHUI_PATH = '【 LOCL (Mac) ❯ com.soda.music (1112) 汽水音乐 ❯ default 】'


def line(time, process, message):
    return f'2026-11-13 {time} Df {process}[1:2] [sub:cat] {message}'


def key(time, command, command_id):
    return line(time, 'rcd', f'Request: Command = <{command}>, SenderDevice = <Mac>, '
                             f'commandID = <{command_id}>, options = <{{')


def route(time, command_id, bundle):
    return line(time, 'mediaremoted', f'Request: sendRemoteControlCommand<{command_id}> for '
                                      f'【 LOCL (Mac) ❯ {bundle} (1112) X ❯ default 】')


def island(time, playback, track):
    return line(time, 'MacBookIsland', f'topislet_usage v=1 event=ui_published has_artwork=1 '
                                       f'playback={playback} source=qishui track={track}')


class KeyboardLatencyAuditTests(unittest.TestCase):
    def test_toggle_is_split_into_route_source_and_island_layers(self):
        rows = audit_module.audit([
            island('01:16:00.000', 'paused', 'aaa'),
            key('01:16:10.000', 'TogglePlayPause', ID),
            '    "multi-line option dump without a timestamp"',
            route('01:16:10.002', ID, 'com.soda.music'),
            line('01:16:10.120', 'mediaremoted',
                 f'[MRDNowPlayingPlayerClient] PlaybackState changed from Paused to Playing for {QISHUI_PATH}'),
            island('01:16:10.175', 'playing', 'aaa'),
        ])
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual((row['route_ms'], row['source_ms'], row['island_ms']), (2, 120, 175))
        self.assertEqual(row['island_state'], 'playing')

    def test_track_change_waits_for_a_new_track_hash(self):
        rows = audit_module.audit([
            island('01:00:00.000', 'playing', 'old'),
            key('01:00:01.000', 'NextTrack', ID),
            route('01:00:01.001', ID, 'com.soda.music'),
            line('01:00:01.140', 'mediaremoted',
                 f'Set: {QISHUI_PATH} setting nowPlayingItem from <<private>> to <<private>>'),
            island('01:00:01.150', 'playing', 'old'),
            island('01:00:01.400', 'playing', 'new'),
        ])
        self.assertEqual((rows[0]['source_ms'], rows[0]['island_ms']), (140, 400))

    def test_key_routed_to_another_player_has_no_qishui_layers(self):
        rows = audit_module.audit([
            key('07:50:28.626', 'TogglePlayPause', ID),
            route('07:50:28.627', ID, 'com.netease.163music'),
            island('07:50:28.700', 'paused', 'aaa'),
        ])
        self.assertEqual(rows[0]['target'], 'com.netease.163music')
        self.assertIsNone(rows[0]['island_ms'])
        self.assertIn('其他播放器 1 次', audit_module.report(rows))

    def test_island_reaction_outside_window_is_not_attributed(self):
        rows = audit_module.audit([
            key('01:00:00.000', 'TogglePlayPause', ID),
            route('01:00:00.001', ID, 'com.soda.music'),
            line('01:00:00.100', 'mediaremoted',
                 f'PlaybackState changed from Playing to Paused for {QISHUI_PATH}'),
            island('01:00:04.000', 'paused', 'aaa'),
            key('01:00:05.000', 'TogglePlayPause', OTHER),
        ])
        self.assertIsNone(rows[0]['island_ms'])
        self.assertIsNone(rows[1]['target'])
        self.assertIn('顶屿无发布：1 次', audit_module.report(rows))

    def test_report_carries_no_track_hash(self):
        rows = audit_module.audit([
            key('01:16:10.000', 'TogglePlayPause', ID),
            route('01:16:10.002', ID, 'com.soda.music'),
            line('01:16:10.120', 'mediaremoted', f'PlaybackState changed from Paused to Playing for {QISHUI_PATH}'),
            island('01:16:10.175', 'playing', 'e8c607d29fcb'),
        ])
        self.assertNotIn('e8c607d29fcb', audit_module.report(rows))


if __name__ == '__main__':
    unittest.main()
