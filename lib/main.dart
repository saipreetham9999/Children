import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:children/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request permissions
  await [
    Permission.location,
    Permission.camera,
    Permission.notification,
  ].request();

  await initializeService();
  runApp(const MyApp());
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );

  service.startService();
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final battery = Battery();
  final deviceInfo = DeviceInfoPlugin();

  // Get device info once on startup
  String deviceName = Config.deviceId;
  String deviceType = "unknown";
  try {
    if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      deviceName = android.model;
      deviceType = "android";
    } else if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      deviceName = ios.model;
      deviceType = "ios";
    }
  } catch (e) {
    print("Error getting device info: $e");
  }

  // Step 1: Register this device with Brain on startup
  print("Connecting to Brain...");
  try {
    final connectPayload = {
      "device_name": deviceName,
      "device_type": deviceType,
      "capabilities": ["camera", "location", "battery"],
      "token": null,
    };

    final connectResponse = await http.post(
      Uri.parse("${Config.baseUrl}/connect"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(connectPayload),
    );
    print("Connect response: ${connectResponse.statusCode} - ${connectResponse.body}");
  } catch (e) {
    print("Error connecting to Brain: $e");
  }

  // Step 2: Send heartbeats every 5 seconds
  Timer.periodic(const Duration(seconds: Config.heartbeatInterval), (timer) async {
    if (service is AndroidServiceInstance) {
      if (!(await service.isForegroundService())) {
        return;
      }
    }

    try {
      // 1. Get Battery Info
      final batteryLevel = await battery.batteryLevel;

      // 2. Get Location
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        );
      } catch (e) {
        print("Error getting location: $e");
      }

      // 3. Prepare Heartbeat Data
      final heartbeatData = {
        "deviceId": Config.deviceId,
        "battery": batteryLevel,
        "location": position != null
          ? "${position.latitude},${position.longitude}"
          : "unknown",
        "timestamp": DateTime.now().toIso8601String(),
      };

      // 4. Send Heartbeat with proper JSON and headers
      final response = await http.post(
        Uri.parse("${Config.baseUrl}/heartbeat"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(heartbeatData),
      ).timeout(const Duration(seconds: 10));

      print("Heartbeat sent: ${response.statusCode}");
      if (response.statusCode != 200) {
        print("Heartbeat error: ${response.body}");
      }
    } catch (e) {
      print("Error sending heartbeat: $e");
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text("Worker Node")),
        body: Center(
          child: FutureBuilder<http.Response>(
            future: http.get(Uri.parse("${Config.baseUrl}/status")),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }
              if (snapshot.hasError) {
                return Text("Brain Status: Offline (${snapshot.error})");
              }
              return Text("Brain Status: ${snapshot.data?.body ?? 'Online'}");
            },
          ),
        ),
      ),
    );
  }
}
