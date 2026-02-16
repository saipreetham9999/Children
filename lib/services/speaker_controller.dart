import 'dart:async';
import 'package:volume_controller/volume_controller.dart';
import 'package:flutter/foundation.dart';

/// WSpeakerController — Control speaker/audio output using volume_controller 2.x
class WSpeakerController extends ChangeNotifier {
  static final WSpeakerController _instance =
      WSpeakerController._internal();
  factory WSpeakerController() => _instance;
  WSpeakerController._internal();

  double _currentVolume = 1.0; // 0.0 to 1.0
  String _speakerMode = 'speaker';  // 'speaker', 'earpiece', 'bluetooth'
  bool _isMuted = false;
  StreamSubscription? _volumeSubscription;

  /// Current volume (0-100)
  int get currentVolume => (_currentVolume * 100).round();

  /// Current speaker mode
  String get speakerMode => _speakerMode;

  /// Is muted
  bool get isMuted => _isMuted;

  /// Volume percentage string
  String get volumePercent => '${currentVolume}%';

  /// Volume indicator
  String get volumeIndicator {
    final vol = currentVolume;
    if (vol == 0) return '🔇 Muted';
    if (vol < 33) return '🔈 Low';
    if (vol < 66) return '🔉 Medium';
    return '🔊 High';
  }

  /// Initialize speaker controller
  Future<void> initialize() async {
    print('[SpeakerController] Initializing...');

    try {
      // Get initial volume
      _currentVolume = await VolumeController().getVolume();
      _isMuted = _currentVolume <= 0.001;

      // Listen to volume changes
      _volumeSubscription = VolumeController().listener((volume) {
        print('[SpeakerController] Volume changed: $volume');
        _currentVolume = volume;
        _isMuted = _currentVolume <= 0.001;
        notifyListeners();
      });

      print('[SpeakerController] ✅ Initialized (Volume: $currentVolume%)');
    } catch (e) {
      print('[SpeakerController] Init error: $e');
    }
  }

  /// Set volume (0-100)
  Future<void> setVolume(int percentage) async {
    final double volValue = (percentage / 100).clamp(0.0, 1.0);
    print('[SpeakerController] Setting volume to $percentage% ($volValue)');

    try {
      VolumeController().setVolume(volValue);
      _currentVolume = volValue;
      _isMuted = _currentVolume <= 0.001;
      notifyListeners();
    } catch (e) {
      print('[SpeakerController] Set volume error: $e');
    }
  }

  /// Toggle system volume UI visibility
  void showVolumeUI(bool show) {
    VolumeController().showSystemUI = show;
  }

  /// Increase volume
  Future<void> increaseVolume({int step = 10}) async {
    final newVolume = (currentVolume + step).clamp(0, 100);
    await setVolume(newVolume);
  }

  /// Decrease volume
  Future<void> decreaseVolume({int step = 10}) async {
    final newVolume = (currentVolume - step).clamp(0, 100);
    await setVolume(newVolume);
  }

  /// Mute
  Future<void> mute() async {
    print('[SpeakerController] Muting');
    await setVolume(0);
  }

  /// Unmute (restore to 50%)
  Future<void> unmute() async {
    print('[SpeakerController] Unmuting');
    await setVolume(50);
  }

  /// Set speaker mode
  void setSpeakerMode(String mode) {
    if (!['speaker', 'earpiece', 'bluetooth'].contains(mode)) return;
    _speakerMode = mode;
    notifyListeners();
  }

  /// Get speaker stats
  Map<String, dynamic> getStats() {
    return {
      'current_volume': currentVolume,
      'volume_percent': volumePercent,
      'is_muted': _isMuted,
      'speaker_mode': _speakerMode,
      'volume_indicator': volumeIndicator,
    };
  }

  @override
  void dispose() {
    _volumeSubscription?.cancel();
    VolumeController().removeListener();
    super.dispose();
  }
}
