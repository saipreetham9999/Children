import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui';

// Absolute imports are mandatory for background isolates
import 'package:worker/services/brain_service.dart';
import 'package:worker/services/frame_service.dart';
import 'package:worker/services/motion_detector.dart';

class WBackgroundService {
  static const String serviceName = 'ShaRogai';

  static Future<void> initialize() async {
    try {
      final service = FlutterBackgroundService();

      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          isForegroundMode: true,
          autoStart: false, 
          notificationChannelId: 'sharogai_monitor_01',
          initialNotificationTitle: 'ShaRogai',
          initialNotificationContent: 'Connecting to Brain...',
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

  static Future<void> start() async {
    final service = FlutterBackgroundService();
    if (!(await service.isRunning())) {
      await service.startService();
    }
  }

  static Future<void> stop() async {
    final service = FlutterBackgroundService();
    service.invoke('stop');
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Use runZonedGuarded to catch background errors
  runZonedGuarded(() async {
    // 1. Setup Isolate - DO NOT use WidgetsFlutterBinding here
    DartPluginRegistrant.ensureInitialized();

    if (service is AndroidServiceInstance) {
      // 2. Immediate Foregrounding to prevent "Bad notification" crash
      service.setAsForegroundService();
      service.setForegroundNotificationInfo(
        title: "ShaRogai Service",
        content: "Monitoring link...",
      );

      service.on('setAsForeground').listen((event) => service.setAsForegroundService());
      service.on('setAsBackground').listen((event) => service.setAsBackgroundService());
    }

    service.on('stop').listen((event) => service.stopSelf());

    // 3. Load configuration
    final prefs = await SharedPreferences.getInstance();
    final brainUrl = prefs.getString('brain_url') ?? 'http://192.168.0.183:8080';
    final deviceName = prefs.getString('device_name') ?? 'ShaRogai-Device';

    final brainService = WBrainService(brainUrl: brainUrl, deviceName: deviceName);
    final frameService = WFrameService();
    final motionDetector = WMotionDetector();

    bool cameraReady = false;

    // 4. Command listener
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

    // 5. Main Loop (Every 5 seconds for heartbeat)
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        // Heartbeat + Poll commands
        await brainService.sendHeartbeat();
        final events = await brainService.getEvents();
        
        if (events.isNotEmpty) {
          prefs.setString('last_alert', events.first.displayText);
        }

        // Optional Motion Check
        if (cameraReady) {
          final frame = await frameService.captureFrame();
          if (frame.isNotEmpty) {
            final compressed = frameService.compressFrame(frame);
            if (motionDetector.detectMotion(compressed)) {
              await brainService.sendFrame(compressed, context: {'source': 'bg_motion'});
            }
          }
        }

        // Update Notification
        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: "ShaRogai Online",
            content: "Link stable • Camera: ${cameraReady ? 'Active' : 'Standby'}",
          );
        }
      } catch (_) {}
    });
  }, (error, stack) {
    debugPrint('[Background] Fatal Error: $error');
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}
