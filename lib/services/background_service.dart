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

class WBackgroundService {
  static const String channelId = 'sharogai_monitor_01';

  static Future<void> initialize() async {
    try {
      final service = FlutterBackgroundService();

      if (Platform.isAndroid) {
        final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          channelId,
          'ShaRogai Service',
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
    } catch (e) {
      debugPrint('Init error: $e');
    }
  }

  static Future<void> start() async {
    final service = FlutterBackgroundService();
    if (!(await service.isRunning())) await service.startService();
  }

  static Future<void> stop() async {
    FlutterBackgroundService().invoke('stop');
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(title: "ShaRogai Service", content: "Initializing...");
    service.on('setAsForeground').listen((_) => service.setAsForegroundService());
    service.on('setAsBackground').listen((_) => service.setAsBackgroundService());
  }

  service.on('stop').listen((_) => service.stopSelf());

  final prefs = await SharedPreferences.getInstance();
  final brainUrl = prefs.getString('brain_url') ?? 'http://192.168.0.183:8080';
  final deviceName = prefs.getString('device_name') ?? 'ShaRogai-Poco';

  final brainService = WBrainService(brainUrl: brainUrl, deviceName: deviceName);
  final frameService = WFrameService();
  final motionDetector = WMotionDetector();

  bool cameraReady = false;
  bool isCapturingExtra = false;
  int extraFramesToTake = 0;

  service.on('toggle_camera').listen((event) async {
    final bool enable = event?['enable'] ?? false;
    if (enable && !cameraReady) {
      try {
        await frameService.initialize();
        cameraReady = true;
      } catch (_) {}
    } else if (!enable && cameraReady) {
      await frameService.dispose();
      cameraReady = false;
    }
  });

  // Main Loop
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    try {
      // 1. Check for commands from Brain (e.g., 'request_photo')
      final events = await brainService.getEvents();
      for (var event in events) {
        if (event.type == 'request_photo') {
          extraFramesToTake = 5; // Take 5 more photos
        }
      }

      // 2. Handling Motion & Commands
      if (cameraReady) {
        final frame = await frameService.captureFrame();
        if (frame.isNotEmpty) {
          final compressed = frameService.compressFrame(frame);
          
          bool shouldSend = false;
          Map<String, dynamic> ctx = {'timestamp': DateTime.now().toIso8601String()};

          if (motionDetector.detectMotion(compressed)) {
            shouldSend = true;
            ctx['source'] = 'motion';
            // When motion is detected, auto-request 3 follow-up shots
            extraFramesToTake = 3; 
          } else if (extraFramesToTake > 0) {
            shouldSend = true;
            ctx['source'] = 'follow_up';
            ctx['frames_remaining'] = extraFramesToTake;
            extraFramesToTake--;
          }

          if (shouldSend) {
            await brainService.sendFrame(compressed, context: ctx);
          }
        }
      }

      // 3. Heartbeat & Notification
      if (timer.tick % 5 == 0) {
        await brainService.sendHeartbeat();
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: "ShaRogai Active",
            content: "Sync: OK • Motion: ${cameraReady ? 'Monitoring' : 'Standby'}",
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
