import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'brain_service.dart';
import 'frame_service.dart';
import 'motion_detector.dart';
import 'package:flutter/widgets.dart';

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

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();

    prefs = await SharedPreferences.getInstance();
    final brainUrl = prefs.getString('brain_url') ?? 'http://localhost:8080';
    final deviceName = prefs.getString('device_name') ?? 'Unknown';

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

    int heartbeatCount = 0;
    int captureCount = 0;

    late Timer timer;

    timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      captureCount++;
      heartbeatCount++;

      try {
        // Capture every 2 seconds
        if (captureCount >= 2) {
          captureCount = 0;

          final frameBytes = await frameService.captureFrame();
          final compressed = frameService.compressFrame(frameBytes);

          if (motionDetector.detectMotion(compressed)) {
            await brainService.sendFrame(compressed);
          }
        }

        // Heartbeat every 5 seconds
        if (heartbeatCount >= 5) {
          heartbeatCount = 0;

          await brainService.sendHeartbeat();

          final events = await brainService.getEvents();
          if (events.isNotEmpty) {
            prefs.setString('last_alert', events.first.displayText);
            print('[WBG] Received ${events.length} events');
          }

          // 🔥 In v6, you must update notification like this:
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: 'Worker',
              content:
              'Online • Frames: ${motionDetector.getStats()['motion_detections']}',
            );
          }
        }
      } catch (e) {
        print('[WBG] Loop error: $e');
      }
    });

    // Stop handler
    service.on('stopService').listen((event) {
      timer.cancel();
      frameService.dispose();
      service.stopSelf();
    });
  }

  /// iOS background handler
  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    return true;
  }
}

