import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:ui';
import 'brain_service.dart';
import 'frame_service.dart';
import 'motion_detector.dart';

/// Entry point for the background service
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // On Android, configure foreground notification behavior
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Initialize background logic
  final prefs = await SharedPreferences.getInstance();
  final brainUrl = prefs.getString('brain_url') ?? 'http://192.168.0.183:8080';
  final deviceName = prefs.getString('device_name') ?? 'Poco-M2-Pro';

  final brainService = WBrainService(brainUrl: brainUrl, deviceName: deviceName);
  final frameService = WFrameService();
  final motionDetector = WMotionDetector();

  // Crucial: Give the system time to setup the notification before starting heavy work
  await Future.delayed(const Duration(seconds: 2));

  try {
    await frameService.initialize();
    debugPrint('[Background] Camera initialized');
  } catch (e) {
    debugPrint('[Background] Camera Error: $e');
  }

  // Periodic task: Heartbeat and Motion Detection
  Timer.periodic(const Duration(seconds: 5), (timer) async {
    if (service is AndroidServiceInstance) {
      // Check if service is still supposed to be running
      if (await service.isForegroundService()) {
        
        // 1. Heartbeat to Brain
        try {
          await brainService.sendHeartbeat();
        } catch (e) {
          debugPrint('[Background] Heartbeat failed: $e');
        }

        // 2. Motion detection logic
        try {
          if (frameService.isInitialized) {
            final frame = await frameService.captureFrame();
            if (frame.isNotEmpty) {
              final compressed = frameService.compressFrame(frame);
              if (motionDetector.detectMotion(compressed)) {
                await brainService.sendFrame(compressed);
              }
            }
          }
        } catch (e) {
          debugPrint('[Background] Motion detection failed: $e');
        }

        // 3. Update notification to keep service alive
        service.setForegroundNotificationInfo(
          title: "Worker Active",
          content: "Battery: Monitoring • Brain: Connected",
        );
      }
    }
  });
}

class WBackgroundService {
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false, // Don't start until user is ready
        isForegroundMode: true,
        notificationChannelId: 'worker_channel_01',
        initialNotificationTitle: 'Worker Service',
        initialNotificationContent: 'Connecting to Brain...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  static Future<void> start() async {
    final service = FlutterBackgroundService();
    if (!(await service.isRunning())) {
      await service.startService();
      print('[WBG] Background service started');
    }
  }

  static Future<void> stop() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}
