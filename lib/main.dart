import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/connect_screen.dart';
import 'screens/register_screen.dart';
import 'screens/main_screen.dart';
import 'services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Request permissions FIRST
  await _requestPermissions();

  // 2. Then initialize service configuration (but don't auto-start yet)
  await WBackgroundService.initialize();

  runApp(const WApp());
}

Future<void> _requestPermissions() async {
  // Notification permission is critical for background services on Android 13+
  await Permission.notification.request();
  
  // Request camera and location
  await [
    Permission.camera,
    Permission.location,
    Permission.locationAlways, // Needed for background GPS
  ].request();
}

class WApp extends StatelessWidget {
  const WApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Worker',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      // Use a splash or initial check before navigating to Connect
      home: const WConnectScreen(),
      routes: {
        '/connect': (_) => const WConnectScreen(),
        '/register': (_) => WRegisterScreen(
              brainUrl: (ModalRoute.of(_)?.settings.arguments as Map?)?['brainUrl'] ?? 'http://192.168.0.183:8080',
            ),
        '/main': (_) => const WMainScreen(),
      },
    );
  }
}
