import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:children/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

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

  Timer.periodic(const Duration(seconds: Config.heartbeatInterval), (timer) async {
    if (service is AndroidServiceInstance) {
      if (!(await service.isForegroundService())) {
        return;
      }
    }

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

    // 3. Prepare Report
    final data = {
      "deviceId": Config.deviceId,
      "battery": batteryLevel,
      "location": position != null ? "${position.latitude},${position.longitude}" : "unknown",
      "timestamp": DateTime.now().toIso8601String(),
    };

    // 4. Send Heartbeat to Brain
    try {
      final response = await http.post(
        Uri.parse("${Config.baseUrl}/report"),
        body: data.toString(),
      );
      print("Heartbeat sent: ${response.statusCode}");
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
