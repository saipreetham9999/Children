import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_background_service_ios/flutter_background_service_ios.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'brain_service.dart';
import 'frame_service.dart';
import 'motion_detector.dart';

/// WBackgroundService — Continuous monitoring for ShaRogai
/// Runs in background: heartbeat + frame capture + motion detection
class WBackgroundService {
  static const String serviceName = 'ShaRogai';
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
            notificationChannelId: 'sharogai_channel',
            initialNotificationTitle: 'ShaRogai',
            initialNotificationContent: 'Motion Detection Ready',
            foregroundServiceNotificationId: 888,
          ),
          iosConfiguration: IosConfiguration(
            autoStart: true,
            onForeground: onStart,
            onBackground: onIosBackground,
          ),
        );
      }

      print('[ShaRogai] Background service initialized');
    } catch (e) {
      print('[ShaRogai] Init error: $e');
    }
  }

  /// Start background service
  static Future<void> start() async {
    try {
      final service = FlutterBackgroundService();
      await service.startService();
      print('[ShaRogai] Background service started');
    } catch (e) {
      print('[ShaRogai] Start error: $e');
    }
  }

  /// Stop background service
  static Future<void> stop() async {
    try {
      final service = FlutterBackgroundService();
      service.invoke('stop');
      print('[ShaRogai] Background service stopped');
    } catch (e) {
      print('[ShaRogai] Stop error: $e');
    }
  }

  /// Main background task
  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();

    prefs = await SharedPreferences.getInstance();
    final brainUrl = prefs.getString('brain_url') ?? 'http://localhost:8080';
    final deviceName = prefs.getString('device_name') ?? 'ShaRogai Device';

    brainService = WBrainService(brainUrl: brainUrl, deviceName: deviceName);
    frameService = WFrameService();
    motionDetector = WMotionDetector();

    try {
      await frameService.initialize();
      print('[ShaRogai] Camera initialized');
    } catch (e) {
      print('[ShaRogai] Camera error: $e');
      return;
    }

    int heartbeatCount = 0;
    int captureCount = 0;
    Timer? bgTimer;

    bgTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      captureCount++;
      heartbeatCount++;

      try {
        // Every 2 seconds: capture + motion detect
        if (captureCount >= 2) {
          captureCount = 0;
          try {
            final frameBytes = await frameService.captureFrame();
            final compressed = frameService.compressFrame(frameBytes);

            if (motionDetector.detectMotion(compressed)) {
              await brainService.sendFrame(compressed);
            }
          } catch (e) {
            print('[ShaRogai] Frame error: $e');
          }
        }

        // Every 5 seconds: heartbeat + events
        if (heartbeatCount >= 5) {
          heartbeatCount = 0;
          await brainService.sendHeartbeat();

          final events = await brainService.getEvents();
          if (events.isNotEmpty) {
            prefs.setString('last_alert', events.first.displayText);
          }

          // Update notification
          if (service is AndroidServiceInstance) {
            final stats = motionDetector.getStats();
            final framesCount = stats['motion_detections'] ?? 0;
            try {
              service.setForegroundNotificationTitle('ShaRogai');
              service.setForegroundNotificationContent(
                '🟢 Online • Frames: $framesCount',
              );
            } catch (e) {
              print('[ShaRogai] Notification error: $e');
            }
          }
        }
      } catch (e) {
        print('[ShaRogai] Loop error: $e');
      }
    });

    // Handle stop
    if (service is AndroidServiceInstance) {
      service.on('stop').listen((_) {
        bgTimer?.cancel();
        frameService.dispose();
        service.stopSelf();
      });
    }
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    return true;
  }
}
