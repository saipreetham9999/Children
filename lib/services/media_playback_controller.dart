import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// MediaCommand — A command from Brain to control media on child device
class MediaCommand {
  final String action; // 'play', 'pause', 'stop', 'volume', 'mute', 'unmute', 'seek'
  final String? mediaUrl;
  final String? mediaType; // 'youtube', 'audio', 'tts', 'stream'
  final int? volumePercent; // 0-100
  final int? seekPositionMs;
  final String source; // 'brain', 'parent', 'local'
  final DateTime timestamp;

  MediaCommand({
    required this.action,
    this.mediaUrl,
    this.mediaType,
    this.volumePercent,
    this.seekPositionMs,
    this.source = 'brain',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory MediaCommand.fromBrainEvent(Map<String, dynamic> event) {
    final command = event['command'] as String? ?? '';
    final parts = command.split(' ');

    String action = 'play';
    String? url;
    String? type;
    int? volume;

    if (parts.isNotEmpty) {
      final cmd = parts[0].replaceFirst('/', '');
      switch (cmd) {
        case 'play':
          action = 'play';
          if (parts.length > 1) {
            final media = parts[1];
            if (media.contains(':')) {
              type = media.split(':')[0];
              url = media.split(':').sublist(1).join(':');
            } else {
              url = media;
            }
          }
          break;
        case 'pause':
          action = 'pause';
          break;
        case 'stop':
          action = 'stop';
          break;
        case 'volume':
          action = 'volume';
          volume = parts.length > 1 ? int.tryParse(parts[1]) : null;
          break;
        case 'mute':
          action = 'mute';
          break;
        case 'unmute':
          action = 'unmute';
          break;
        default:
          action = cmd;
      }
    }

    return MediaCommand(
      action: action,
      mediaUrl: url,
      mediaType: type,
      volumePercent: volume,
      source: event['source'] as String? ?? 'brain',
    );
  }

  Map<String, dynamic> toJson() => {
        'action': action,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'volume_percent': volumePercent,
        'source': source,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// PlaybackState — Current playback status
enum PlaybackStatus { idle, loading, playing, paused, stopped, error }

/// WMediaPlaybackController — Controls media playback on child devices
/// Handles play commands from Brain, volume control, and playback state
class WMediaPlaybackController extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();

  // State
  PlaybackStatus _status = PlaybackStatus.idle;
  String? _currentMediaUrl;
  String? _currentMediaType;
  int _volume = 100; // 0-100
  bool _isMuted = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  final List<MediaCommand> _commandHistory = [];

  // Getters
  PlaybackStatus get status => _status;
  String? get currentMediaUrl => _currentMediaUrl;
  String? get currentMediaType => _currentMediaType;
  int get volume => _volume;
  bool get isMuted => _isMuted;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _status == PlaybackStatus.playing;
  bool get isPaused => _status == PlaybackStatus.paused;
  bool get isIdle => _status == PlaybackStatus.idle;
  List<MediaCommand> get commandHistory => List.unmodifiable(_commandHistory);

  double get progress =>
      _duration.inMilliseconds > 0
          ? _position.inMilliseconds / _duration.inMilliseconds
          : 0;

  String get positionFormatted => _formatDuration(_position);
  String get durationFormatted => _formatDuration(_duration);

  /// Callbacks
  Function(MediaCommand command)? onCommandReceived;
  Function(PlaybackStatus status)? onStatusChange;
  Function(String error)? onError;

  /// Initialize player
  Future<void> initialize() async {
    print('[MediaPlayback] Initializing...');

    // Listen to player state
    _audioPlayer.playerStateStream.listen((state) {
      if (state.playing) {
        _status = PlaybackStatus.playing;
      } else {
        switch (state.processingState) {
          case ProcessingState.idle:
            _status = PlaybackStatus.idle;
            break;
          case ProcessingState.loading:
          case ProcessingState.buffering:
            _status = PlaybackStatus.loading;
            break;
          case ProcessingState.ready:
            _status = PlaybackStatus.paused;
            break;
          case ProcessingState.completed:
            _status = PlaybackStatus.stopped;
            break;
        }
      }
      onStatusChange?.call(_status);
      notifyListeners();
    });

    // Listen to position
    _audioPlayer.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    // Listen to duration
    _audioPlayer.durationStream.listen((dur) {
      if (dur != null) _duration = dur;
      notifyListeners();
    });

    print('[MediaPlayback] Initialized');
  }

  /// Execute a media command (from Brain or parent)
  Future<void> executeCommand(MediaCommand command) async {
    print('[MediaPlayback] Command: ${command.action} from ${command.source}');
    _commandHistory.add(command);
    onCommandReceived?.call(command);

    // Keep last 100 commands
    if (_commandHistory.length > 100) {
      _commandHistory.removeRange(0, _commandHistory.length - 100);
    }

    switch (command.action) {
      case 'play':
        if (command.mediaUrl != null) {
          await play(command.mediaUrl!, mediaType: command.mediaType);
        } else {
          await resume();
        }
        break;
      case 'pause':
        await pause();
        break;
      case 'stop':
        await stop();
        break;
      case 'volume':
        if (command.volumePercent != null) {
          await setVolume(command.volumePercent!);
        }
        break;
      case 'mute':
        await mute();
        break;
      case 'unmute':
        await unmute();
        break;
      case 'seek':
        if (command.seekPositionMs != null) {
          await seekTo(Duration(milliseconds: command.seekPositionMs!));
        }
        break;
      default:
        print('[MediaPlayback] Unknown action: ${command.action}');
    }
  }

  /// Play media from URL
  Future<void> play(String url, {String? mediaType}) async {
    print('[MediaPlayback] Playing: $url (type: $mediaType)');
    _currentMediaUrl = url;
    _currentMediaType = mediaType;

    try {
      _status = PlaybackStatus.loading;
      notifyListeners();

      // Set audio source based on type
      if (url.startsWith('http://') || url.startsWith('https://')) {
        await _audioPlayer.setUrl(url);
      } else if (url.startsWith('asset://')) {
        await _audioPlayer.setAsset(url.replaceFirst('asset://', ''));
      } else {
        // Try as URL
        await _audioPlayer.setUrl(url);
      }

      await _audioPlayer.play();
      _status = PlaybackStatus.playing;
      print('[MediaPlayback] Playing');
    } catch (e) {
      print('[MediaPlayback] Play error: $e');
      _status = PlaybackStatus.error;
      onError?.call(e.toString());
    }

    notifyListeners();
  }

  /// Pause playback
  Future<void> pause() async {
    print('[MediaPlayback] Pausing');
    await _audioPlayer.pause();
    _status = PlaybackStatus.paused;
    notifyListeners();
  }

  /// Resume playback
  Future<void> resume() async {
    print('[MediaPlayback] Resuming');
    await _audioPlayer.play();
    _status = PlaybackStatus.playing;
    notifyListeners();
  }

  /// Stop playback
  Future<void> stop() async {
    print('[MediaPlayback] Stopping');
    await _audioPlayer.stop();
    _status = PlaybackStatus.stopped;
    _currentMediaUrl = null;
    _currentMediaType = null;
    _position = Duration.zero;
    notifyListeners();
  }

  /// Set volume (0-100)
  Future<void> setVolume(int percent) async {
    if (percent < 0 || percent > 100) return;
    print('[MediaPlayback] Volume: $percent%');
    _volume = percent;
    _isMuted = percent == 0;
    await _audioPlayer.setVolume(percent / 100.0);
    notifyListeners();
  }

  /// Mute
  Future<void> mute() async {
    print('[MediaPlayback] Muted');
    _isMuted = true;
    await _audioPlayer.setVolume(0);
    notifyListeners();
  }

  /// Unmute (restore previous volume)
  Future<void> unmute() async {
    print('[MediaPlayback] Unmuted');
    _isMuted = false;
    await _audioPlayer.setVolume(_volume / 100.0);
    notifyListeners();
  }

  /// Seek to position
  Future<void> seekTo(Duration position) async {
    print('[MediaPlayback] Seek: ${position.inSeconds}s');
    await _audioPlayer.seek(position);
    notifyListeners();
  }

  /// Get playback stats
  Map<String, dynamic> getStats() {
    return {
      'status': _status.name,
      'current_media': _currentMediaUrl,
      'media_type': _currentMediaType,
      'volume': _volume,
      'is_muted': _isMuted,
      'position_ms': _position.inMilliseconds,
      'duration_ms': _duration.inMilliseconds,
      'progress': progress,
      'command_count': _commandHistory.length,
    };
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}
