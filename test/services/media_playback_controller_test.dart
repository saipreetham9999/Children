import 'package:flutter_test/flutter_test.dart';
import 'package:worker/services/media_playback_controller.dart';

void main() {
  group('MediaCommand', () {
    test('creates with required fields', () {
      final cmd = MediaCommand(action: 'play', mediaUrl: 'https://example.com/song.mp3');
      expect(cmd.action, 'play');
      expect(cmd.mediaUrl, 'https://example.com/song.mp3');
      expect(cmd.source, 'brain');
    });

    test('fromBrainEvent parses play command', () {
      final cmd = MediaCommand.fromBrainEvent({
        'command': '/play youtube:dQw4w9WgXcQ',
        'source': 'parent',
      });
      expect(cmd.action, 'play');
      expect(cmd.mediaType, 'youtube');
      expect(cmd.mediaUrl, 'dQw4w9WgXcQ');
      expect(cmd.source, 'parent');
    });

    test('fromBrainEvent parses pause command', () {
      final cmd = MediaCommand.fromBrainEvent({
        'command': '/pause',
      });
      expect(cmd.action, 'pause');
    });

    test('fromBrainEvent parses volume command', () {
      final cmd = MediaCommand.fromBrainEvent({
        'command': '/volume 75',
      });
      expect(cmd.action, 'volume');
      expect(cmd.volumePercent, 75);
    });

    test('fromBrainEvent parses stop command', () {
      final cmd = MediaCommand.fromBrainEvent({
        'command': '/stop',
      });
      expect(cmd.action, 'stop');
    });

    test('fromBrainEvent parses mute command', () {
      final cmd = MediaCommand.fromBrainEvent({
        'command': '/mute',
      });
      expect(cmd.action, 'mute');
    });

    test('toJson produces correct map', () {
      final cmd = MediaCommand(
        action: 'play',
        mediaUrl: 'https://example.com/song.mp3',
        mediaType: 'audio',
        source: 'parent',
      );
      final json = cmd.toJson();
      expect(json['action'], 'play');
      expect(json['media_url'], 'https://example.com/song.mp3');
      expect(json['media_type'], 'audio');
      expect(json['source'], 'parent');
    });
  });

  group('WMediaPlaybackController', () {
    late WMediaPlaybackController controller;

    setUp(() {
      controller = WMediaPlaybackController();
    });

    test('starts in idle state', () {
      expect(controller.status, PlaybackStatus.idle);
      expect(controller.isPlaying, false);
      expect(controller.isPaused, false);
      expect(controller.isIdle, true);
    });

    test('default volume is 100', () {
      expect(controller.volume, 100);
      expect(controller.isMuted, false);
    });

    test('progress is 0 when idle', () {
      expect(controller.progress, 0);
    });

    test('positionFormatted returns correct format', () {
      expect(controller.positionFormatted, '00:00');
    });

    test('durationFormatted returns correct format', () {
      expect(controller.durationFormatted, '00:00');
    });

    test('commandHistory starts empty', () {
      expect(controller.commandHistory, isEmpty);
    });

    test('getStats returns complete data', () {
      final stats = controller.getStats();
      expect(stats['status'], 'idle');
      expect(stats['volume'], 100);
      expect(stats['is_muted'], false);
      expect(stats['command_count'], 0);
    });

    test('currentMediaUrl is null when idle', () {
      expect(controller.currentMediaUrl, null);
      expect(controller.currentMediaType, null);
    });
  });

  group('MediaCommand.fromBrainEvent edge cases', () {
    test('handles empty command', () {
      final cmd = MediaCommand.fromBrainEvent({'command': ''});
      expect(cmd.action, 'play');
    });

    test('handles play without URL', () {
      final cmd = MediaCommand.fromBrainEvent({'command': '/play'});
      expect(cmd.action, 'play');
      expect(cmd.mediaUrl, null);
    });

    test('handles volume without number', () {
      final cmd = MediaCommand.fromBrainEvent({'command': '/volume'});
      expect(cmd.action, 'volume');
      expect(cmd.volumePercent, null);
    });

    test('handles unknown command', () {
      final cmd = MediaCommand.fromBrainEvent({'command': '/shuffle'});
      expect(cmd.action, 'shuffle');
    });

    test('handles play with full URL', () {
      final cmd = MediaCommand.fromBrainEvent({
        'command': '/play https://example.com/audio.mp3',
      });
      expect(cmd.action, 'play');
      expect(cmd.mediaUrl, 'https://example.com/audio.mp3');
    });
  });
}
