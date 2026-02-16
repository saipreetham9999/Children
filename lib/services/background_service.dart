import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'brain_service.dart';
import 'frame_service.dart';
import 'motion_detector.dart';

/// WBackgroundService — Background management for ShaRogai
class WBackgroundService {
  static const String serviceName = 'ShaRogai';
  static const String channelId = 'sharogai_monitor_01';

  /// Initialize background service configuration
  static Future<void> initialize() async {
    try {
      final service = FlutterBackgroundService();

      // Create notification channel manually to prevent "Bad notification" error
      if (Platform.isAndroid) {
        final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          channelId,
          'ShaRogai Service',
          description: 'Background monitoring for ShaRogai',
          importance: Importance.low,
        );

        await localNotifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
      }

      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          isForegroundMode: true,
          autoStart: false,
          notificationChannelId: channelId,
          initialNotificationTitle: 'ShaRogai',
          initialNotificationContent: 'Monitoring active...',
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
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  if (service is AndroidServiceInstance) {
    // Immediate notification update to satisfy Android requirements
    service.setForegroundNotificationInfo(
      title: "ShaRogai Service",
      content: "Initializing...",
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
  final deviceName = prefs.getString('device_name') ?? 'ShaRogai-Poco';

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
      } catch (e) {
        debugPrint('[ShaRogai-BG] Camera Fail: $e');
      }
    } else if (!enable && cameraReady) {
      await frameService.dispose();
      cameraReady = false;
    }
  });

  // Main periodic loop
  int heartbeatCount = 0;
  int captureCount = 0;

  Timer.periodic(const Duration(seconds: 1), (timer) async {
    captureCount++;
    heartbeatCount++;

    try {
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
        } catch (_) {}
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
        } catch (_) {}

        // Update notification
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: "ShaRogai Monitoring",
            content: "Heartbeat: OK • Camera: ${cameraReady ? 'Active' : 'Standby'}",
          );
        }
      }
    } catch (_) {}
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}
