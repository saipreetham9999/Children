import 'dart:async';
import 'package:volume_controller/volume_controller.dart';
import 'package:flutter/foundation.dart';

/// WSpeakerController — Control speaker/audio output
class WSpeakerController extends ChangeNotifier {
  static final WSpeakerController _instance =
      WSpeakerController._internal();
  factory WSpeakerController() => _instance;
  WSpeakerController._internal();

  int _currentVolume = 100;
  int _maxVolume = 100;
  String _speakerMode = 'speaker';  // 'speaker', 'earpiece', 'bluetooth'
  bool _isMuted = false;
  StreamSubscription? _volumeSubscription;

  /// Current volume (0-100)
  int get currentVolume => _currentVolume;

  /// Max volume
  int get maxVolume => _maxVolume;

  /// Current speaker mode
  String get speakerMode => _speakerMode;

  /// Is muted
  bool get isMuted => _isMuted;

  /// Volume percentage string
  String get volumePercent => '${((_currentVolume / _maxVolume) * 100).round()}%';

  /// Volume indicator
  String get volumeIndicator {
    final vol = (_currentVolume / _maxVolume) * 100;
    if (vol == 0) return '🔇 Muted';
    if (vol < 33) return '🔈 Low';
    if (vol < 66) return '🔉 Medium';
    return '🔊 High';
  }

  /// Initialize speaker controller
  Future<void> initialize() async {
    print('[SpeakerController] Initializing...');

    try {
      // Get current volume
      _maxVolume = await VolumeController().getMaxVolume;
      _currentVolume = await VolumeController().getVolume;

      // Listen to volume changes
      VolumeController().getVolumeStream().listen((volume) {
        print('[SpeakerController] Volume changed: $volume/$_maxVolume');
        _currentVolume = volume.round();
        _isMuted = _currentVolume == 0;
        notifyListeners();
      });

      print('[SpeakerController] ✅ Initialized (Volume: $_currentVolume/$_maxVolume)');
    } catch (e) {
      print('[SpeakerController] Init error: $e');
    }
  }

  /// Set volume (0-100)
  Future<void> setVolume(int percentage) async {
    if (percentage < 0 || percentage > 100) {
      print('[SpeakerController] Invalid volume: $percentage');
      return;
    }

    print('[SpeakerController] Setting volume to $percentage%');

    try {
      final volumeValue = (percentage / 100) * _maxVolume;
      await VolumeController().setVolume(volumeValue);
      _currentVolume = percentage;
      _isMuted = _currentVolume == 0;
      notifyListeners();
    } catch (e) {
      print('[SpeakerController] Set volume error: $e');
    }
  }

  /// Increase volume
  Future<void> increaseVolume({int step = 10}) async {
    final newVolume = (_currentVolume + step).clamp(0, 100);
    await setVolume(newVolume);
  }

  /// Decrease volume
  Future<void> decreaseVolume({int step = 10}) async {
    final newVolume = (_currentVolume - step).clamp(0, 100);
    await setVolume(newVolume);
  }

  /// Mute
  Future<void> mute() async {
    print('[SpeakerController] Muting');
    await setVolume(0);
    _isMuted = true;
  }

  /// Unmute (restore previous volume or 50%)
  Future<void> unmute() async {
    print('[SpeakerController] Unmuting');
    await setVolume(50);
    _isMuted = false;
  }

  /// Set speaker mode
  /// Note: Actual implementation depends on native code for complete control
  void setSpeakerMode(String mode) {
    if (!['speaker', 'earpiece', 'bluetooth'].contains(mode)) {
      print('[SpeakerController] Invalid mode: $mode');
      return;
    }

    print('[SpeakerController] Setting speaker mode: $mode');
    _speakerMode = mode;
    notifyListeners();

    // In real implementation:
    // - 'speaker': Route audio to device speaker
    // - 'earpiece': Route to earpiece/receiver
    // - 'bluetooth': Route to connected Bluetooth device
  }

  /// Force to loudspeaker
  void forceToSpeaker() {
    setSpeakerMode('speaker');
  }

  /// Route to Bluetooth (if connected)
  void routeToBluetooth() {
    setSpeakerMode('bluetooth');
  }

  /// Get speaker stats
  Map<String, dynamic> getStats() {
    return {
      'current_volume': _currentVolume,
      'max_volume': _maxVolume,
      'volume_percent': volumePercent,
      'is_muted': _isMuted,
      'speaker_mode': _speakerMode,
      'volume_indicator': volumeIndicator,
    };
  }

  /// Cleanup
  void dispose() {
    _volumeSubscription?.cancel();
    super.dispose();
  }
}
