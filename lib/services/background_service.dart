import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worker/services/motion_detector.dart';
import 'package:worker/services/frame_service.dart';
import 'dart:async';
import 'dart:ui';

// Absolute imports
import 'package:worker/services/brain_service.dart';

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
          initialNotificationTitle: 'ShaRogai Link',
          initialNotificationContent: 'Monitoring connection...',
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
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: "ShaRogai Link Active",
      content: "Connected to Brain • Dashboard Ready",
    );

    service.on('setAsForeground').listen((event) => service.setAsForegroundService());
    service.on('setAsBackground').listen((event) => service.setAsBackgroundService());
  }

  service.on('stop').listen((event) => service.stopSelf());

  runZonedGuarded(() async {
    final prefs = await SharedPreferences.getInstance();
    final brainUrl = prefs.getString('brain_url') ?? 'http://192.168.0.183:8080';
    final deviceName = prefs.getString('device_name') ?? 'ShaRogai-Poco';

    final brainService = WBrainService(brainUrl: brainUrl, deviceName: deviceName);
    final frameService = WFrameService();
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
    // Heartbeat Loop (Purely for connectivity and commands)
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        await brainService.sendHeartbeat();
        final events = await brainService.getEvents();
        if (events.isNotEmpty) {
          prefs.setString('last_alert', events.first.displayText);
          service.invoke('new_event', events.first.toJson());
        }

        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: "ShaRogai Online",
            content: "Heartbeat synced • Commands polled",
          );
        }
      } catch (_) {}
    });
  }, (error, stack) {
    debugPrint('[Background] Isolate Error: $error');
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}
