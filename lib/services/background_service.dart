import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_background_service_ios/flutter_background_service_ios.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui';

// Absolute imports to avoid "red" classes
import 'package:worker/services/brain_service.dart';
import 'package:worker/services/frame_service.dart';
import 'package:worker/services/motion_detector.dart';

/// WBackgroundService — Background management for ShaRogai
class WBackgroundService {
  static const String serviceName = 'ShaRogai';

  /// Initialize background service configuration
  static Future<void> initialize() async {
    try {
      final service = FlutterBackgroundService();

      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          isForegroundMode: true,
          autoStart: false,
          notificationChannelId: 'sharogai_monitor_01',
          initialNotificationTitle: 'ShaRogai Monitoring',
          initialNotificationContent: 'Ready to sync...',
          foregroundServiceNotificationId: 888,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: onStart,
          onBackground: onIosBackground,
        ),
      );

      print('[ShaRogai] Background service initialized');
    } catch (e) {
      print('[ShaRogai] Init error: $e');
    }
  }

  /// Start background service
  static Future<void> start() async {
    try {
      final service = FlutterBackgroundService();
      bool isRunning = await service.isRunning();
      if (!isRunning) {
        await service.startService();
        print('[ShaRogai] Background service started');
      }
    } catch (e) {
      print('[ShaRogai] Start error: $e');
    }
  }

  /// Stop background service
  static Future<void> stop() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('stop');
    } catch (e) {
      print('[ShaRogai] Stop error: $e');
    }
  }
}

/// Main background task - MUST BE TOP-LEVEL
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Use runZonedGuarded to catch background errors
  runZonedGuarded(() async {
    DartPluginRegistrant.ensureInitialized();
    WidgetsFlutterBinding.ensureInitialized();

    if (service is AndroidServiceInstance) {
      // Set initial notification to prevent "Bad notification" crash
      service.setForegroundNotificationInfo(
        title: "ShaRogai Active",
        content: "Initializing background tasks...",
      );

      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });

      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });
    }

    service.on('stop').listen((event) {
      service.stopSelf();
    });

    // Load configuration
    final prefs = await SharedPreferences.getInstance();
    final brainUrl = prefs.getString('brain_url') ?? 'http://192.168.0.183:8080';
    final deviceName = prefs.getString('device_name') ?? 'ShaRogai-Device';

    final brainService = WBrainService(brainUrl: brainUrl, deviceName: deviceName);
    final frameService = WFrameService();
    final motionDetector = WMotionDetector();

    bool cameraReady = false;

    // Listener to enable/disable camera from UI
    service.on('toggle_camera').listen((event) async {
      final bool enable = event?['enable'] ?? false;
      if (enable && !cameraReady) {
        try {
          await frameService.initialize();
          cameraReady = true;
          debugPrint('[ShaRogai-BG] Camera Started');
        } catch (e) {
          debugPrint('[ShaRogai-BG] Camera Fail: $e');
        }
      } else if (!enable && cameraReady) {
        await frameService.dispose();
        cameraReady = false;
        debugPrint('[ShaRogai-BG] Camera Stopped');
      }
    });

    // Main periodic loop
    int heartbeatCount = 0;
    int captureCount = 0;

    Timer.periodic(const Duration(seconds: 1), (timer) async {
      captureCount++;
      heartbeatCount++;

      try {
        if (service is AndroidServiceInstance) {
          if (!(await service.isForegroundService())) return;
        }

        // 1. Capture cycle (every 2s) - ONLY if camera is ready
        if (captureCount >= 2 && cameraReady) {
          captureCount = 0;
          try {
            final frame = await frameService.captureFrame();
            if (frame.isNotEmpty) {
              final compressed = frameService.compressFrame(frame);
              if (motionDetector.detectMotion(compressed)) {
                await brainService.sendFrame(compressed, context: {
                  'source': 'background_motion',
                  'timestamp': DateTime.now().toIso8601String(),
                });
              }
            }
          } catch (e) {
            debugPrint('[ShaRogai-BG] Capture cycle error: $e');
          }
        }

        // 2. Heartbeat cycle (every 5s)
        if (heartbeatCount >= 5) {
          heartbeatCount = 0;
          try {
            await brainService.sendHeartbeat();
            final events = await brainService.getEvents();
            if (events.isNotEmpty) {
              prefs.setString('last_alert', events.first.displayText);
            }
          } catch (e) {
            debugPrint('[ShaRogai-BG] Heartbeat error: $e');
          }

          // Update notification
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: "ShaRogai Monitoring",
              content: "Heartbeat: OK • Camera: ${cameraReady ? 'Active' : 'Standby'}",
            );
          }
        }
      } catch (e) {
        debugPrint('[ShaRogai-BG] Loop error: $e');
      }
    });
  }, (error, stack) {
    debugPrint('[ShaRogai-BG] Fatal Isolate Error: $error');
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}
