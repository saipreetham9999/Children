import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_background_service_ios/flutter_background_service_ios.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'brain_service.dart';
import 'frame_service.dart';
import 'motion_detector.dart';

/// WBackgroundService — Phase 2.3 continuous monitoring
/// Runs in background: heartbeat + frame capture + motion detection
class WBackgroundService {
  static const String serviceName = 'WBackgroundService';
  static late SharedPreferences prefs;
  static late WBrainService brainService;
  static late WFrameService frameService;
  static late WMotionDetector motionDetector;

  /// Initialize background service
  static Future<void> initialize() async {
    try {
      final service = FlutterBackgroundService();
      prefs = await SharedPreferences.getInstance();

      if (Platform.isAndroid) {
        await service.configure(
          androidConfiguration: AndroidConfiguration(
            onStart: onStart,
            isForegroundMode: true,
            autoStart: true,
            notificationChannelId: 'worker_channel',
            initialNotificationTitle: 'Worker',
            initialNotificationContent: 'Monitoring...',
            foregroundServiceNotificationId: 888,
          ),
          iosConfiguration: IosConfiguration(
            autoStart: true,
            onForeground: onStart,
            onBackground: onIosBackground,
          ),
        );
      }

      print('[WBG] Background service configured');
    } catch (e) {
      print('[WBG] Init error: $e');
    }
  }

  /// Start background service
  static Future<void> start() async {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();

      if (!isRunning) {
        await service.startService();
        print('[WBG] Background service started');
      }
    } catch (e) {
      print('[WBG] Start error: $e');
    }
  }

  /// Stop background service
  static Future<void> stop() async {
    try {
      final service = FlutterBackgroundService();
      await service.invoke('stopService');
      print('[WBG] Background service stopped');
    } catch (e) {
      print('[WBG] Stop error: $e');
    }
  }

  /// Main background task (Phase 2.3)
  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    // Ensure Flutter binding
    WidgetsFlutterBinding.ensureInitialized();

    // Load settings
    prefs = await SharedPreferences.getInstance();
    final brainUrl = prefs.getString('brain_url') ?? 'http://localhost:8080';
    final deviceName = prefs.getString('device_name') ?? 'Unknown';

    // Initialize services
    brainService = WBrainService(brainUrl: brainUrl, deviceName: deviceName);
    frameService = WFrameService();
    motionDetector = WMotionDetector();

    try {
      await frameService.initialize();
      print('[WBG] Frame service initialized in background');
    } catch (e) {
      print('[WBG] Camera init failed: $e');
      return;
    }

    // Foreground notification updater
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationId(888);
    }

    // Main loop: heartbeat every 5s, frame capture every 2s
    int heartbeatCount = 0;
    int captureCount = 0;

    Timer.periodic(const Duration(seconds: 1), (timer) async {
      captureCount++;
      heartbeatCount++;

      try {
        // Every 2 seconds: capture frame + motion detect
        if (captureCount >= 2) {
          captureCount = 0;
          final frameBytes = await frameService.captureFrame();
          final compressed = frameService.compressFrame(frameBytes);

          // Motion detection (Phase 2.2)
          if (motionDetector.detectMotion(compressed)) {
            // Motion found: send to Brain
            await brainService.sendFrame(compressed);
          }
        }

        // Every 5 seconds: heartbeat + poll events
        if (heartbeatCount >= 5) {
          heartbeatCount = 0;

          // Send heartbeat
          await brainService.sendHeartbeat();

          // Poll events
          final events = await brainService.getEvents();
          if (events.isNotEmpty) {
            // Store last alert for UI
            prefs.setString(
              'last_alert',
              events.first.displayText,
            );
            print('[WBG] Received ${events.length} events');
          }

          // Update notification
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationTitle('Worker');
            service.setForegroundNotificationContent(
              'Online • Frames sent: ${motionDetector.getStats()['motion_detections']}',
            );
          }
        }
      } catch (e) {
        print('[WBG] Loop error: $e');
      }
    });

    // Handle stop command
    if (service is AndroidServiceInstance) {
      service.on('stopService').listen((event) {
        timer.cancel();
        frameService.dispose();
        service.stopSelf();
      });
    }
  }

  /// iOS background handler
  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    return true;
  }
}

import 'package:flutter/widgets.dart';
