import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'brain_service.dart';
import 'frame_service.dart';
import 'motion_detector.dart';

/// WBackgroundService — Continuous monitoring for ShaRogai
/// Runs in background: heartbeat + frame capture + motion detection
@pragma('vm:entry-point')
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

    // Try to initialize camera, but don't fail if it's not available
    bool cameraReady = false;
    try {
      await frameService.initialize();
      cameraReady = true;
      print('[ShaRogai] ✅ Camera initialized');
    } catch (e) {
      print('[ShaRogai] ⚠️  Camera init failed: $e');
      print('[ShaRogai] ℹ️  Service will run without camera (heartbeat only)');
    }

    int heartbeatCount = 0;
    int captureCount = 0;
    int frameCount = 0;
    Timer? bgTimer;

    bgTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      captureCount++;
      heartbeatCount++;

      try {
        // Every 2 seconds: capture + motion detect (if enabled and camera ready)
        if (captureCount >= 2) {
          captureCount = 0;

          if (!cameraReady) {
            print('[BG-Loop] ⏸️  Camera not available, skipping capture');
          } else {
            // Check if motion detection is enabled
            final motionEnabled = prefs.getBool('motion_enabled') ?? true;
            if (!motionEnabled) {
              print('[BG-Loop] ⏸️  Motion detection disabled, skipping capture');
            } else {
              print('[BG-Loop] 📸 Capture cycle starting...');
              try {
                print('[BG-Loop] Capturing frame...');
                final frameBytes = await frameService.captureFrame();
                print('[BG-Loop] ✅ Frame captured: ${frameBytes.length} bytes');

                print('[BG-Loop] Compressing frame...');
                final compressed = frameService.compressFrame(frameBytes);
                print('[BG-Loop] ✅ Compressed: ${compressed.length} bytes');

                print('[BG-Loop] Detecting motion...');
                final hasMotion = motionDetector.detectMotion(compressed);
                print('[BG-Loop] Motion detected: $hasMotion');

                if (hasMotion) {
                  frameCount++;
                  print('[BG-Loop] 🔥 MOTION FOUND! Sending frame to Brain...');
                  final motionContext = {
                    'source': 'motion_detection',
                    'motion': true,
                    'camera_position': 'front',
                    'timestamp': DateTime.now().toIso8601String(),
                    'frame_number': frameCount,
                    'motion_percentage': '20.0',
                  };
                  await brainService.sendFrame(compressed, context: motionContext);
                  print('[BG-Loop] ✅ Frame sent to Brain');
                } else {
                  print('[BG-Loop] No motion, frame discarded');
                }
              } catch (e) {
                print('[BG-Loop] ❌ Frame error: $e');
                print('[BG-Loop] Error type: ${e.runtimeType}');
              }
            }
          }
        }

        // Every 5 seconds: heartbeat + events
        if (heartbeatCount >= 5) {
          heartbeatCount = 0;
          print('[BG-Loop] 💓 Heartbeat cycle...');

          try {
            await brainService.sendHeartbeat();
            print('[BG-Loop] ✅ Heartbeat sent');
          } catch (e) {
            print('[BG-Loop] ❌ Heartbeat error: $e');
          }

          try {
            print('[BG-Loop] 📬 Polling events...');
            final events = await brainService.getEvents();
            if (events.isNotEmpty) {
              print('[BG-Loop] 🔔 Got ${events.length} events');
              prefs.setString('last_alert', events.first.displayText);
            } else {
              print('[BG-Loop] No events');
            }
          } catch (e) {
            print('[BG-Loop] ❌ Events error: $e');
          }

          // Log stats (notification already set during service init)
          try {
            final stats = motionDetector.getStats();
            final framesCount = stats['motion_detections'] ?? 0;
            final totalFrames = stats['frames_processed'] ?? 0;
            final rate = stats['detection_rate'] ?? '0.0';
            print('[BG-Loop] 📊 Stats - Motion: $framesCount/$totalFrames ($rate%)');
          } catch (e) {
            print('[BG-Loop] ❌ Stats error: $e');
          }
        }
      } catch (e) {
        print('[BG-Loop] ❌ LOOP ERROR: $e');
        print('[BG-Loop] Error type: ${e.runtimeType}');
      }
    });

    // Handle stop
    if (service is AndroidServiceInstance) {
      service.on('stop').listen((_) {
        bgTimer?.cancel();
        if (cameraReady) {
          frameService.dispose();
        }
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
