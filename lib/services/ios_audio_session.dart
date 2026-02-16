import 'dart:io';
import 'package:flutter/services.dart';

/// WiOSAudioSession — iOS-specific audio session management via platform channel
/// Allows Dart code to control iOS audio routing and session settings
class WiOSAudioSession {
  static const platform =
      MethodChannel('com.sharogai.audio/session');

  /// Initialize audio session (iOS only)
  static Future<void> initializeAudioSession() async {
    if (!Platform.isIOS) return;

    try {
      final result = await platform.invokeMethod<Map>(
        'initializeAudioSession',
      );
      print('[iOSAudioSession] ✅ Initialized: $result');
    } catch (e) {
      print('[iOSAudioSession] Error: $e');
    }
  }

  /// Set speaker mode (speaker, earpiece, or bluetooth)
  static Future<void> setSpeakerMode(String mode) async {
    if (!Platform.isIOS) return;

    try {
      final result = await platform.invokeMethod<Map>(
        'setSpeakerMode',
        mode,
      );
      print('[iOSAudioSession] Speaker mode set: $result');
    } catch (e) {
      print('[iOSAudioSession] Error setting speaker mode: $e');
    }
  }

  /// Get current audio route
  static Future<String?> getCurrentRoute() async {
    if (!Platform.isIOS) return null;

    try {
      final result = await platform.invokeMethod<Map>(
        'getCurrentRoute',
      );
      final route = result?['route'] as String?;
      print('[iOSAudioSession] Current route: $route');
      return route;
    } catch (e) {
      print('[iOSAudioSession] Error getting route: $e');
      return null;
    }
  }

  /// Setup audio route change listener
  static Future<void> setupRouteChangeListener() async {
    if (!Platform.isIOS) return;

    try {
      await platform.invokeMethod<Map>(
        'setupRouteChangeListener',
      );
      print('[iOSAudioSession] Route change listener setup');
    } catch (e) {
      print('[iOSAudioSession] Error: $e');
    }
  }

  /// Enable background audio playback (iOS only)
  static Future<void> enableBackgroundAudio() async {
    if (!Platform.isIOS) return;

    try {
      await platform.invokeMethod<Map>(
        'enableBackgroundAudio',
      );
      print('[iOSAudioSession] Background audio enabled');
    } catch (e) {
      print('[iOSAudioSession] Error: $e');
    }
  }

  /// Configure for iOS Focus modes (iOS 15+)
  static Future<void> configureFocusMode() async {
    if (!Platform.isIOS) return;

    try {
      await platform.invokeMethod<Map>(
        'configureFocusMode',
      );
      print('[iOSAudioSession] Focus mode configured');
    } catch (e) {
      print('[iOSAudioSession] Error: $e');
    }
  }
}
