import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/connect_screen.dart';
import 'screens/register_screen.dart';
import 'screens/main_screen.dart';
import 'services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize service config
  await WBackgroundService.initialize();

  runApp(const WApp());
}

class WApp extends StatefulWidget {
  const WApp({Key? key}) : super(key: key);

  @override
  State<WApp> createState() => _WAppState();
}

class _WAppState extends State<WApp> {
  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // Critical: Request notification first to avoid service crashes
    await Permission.notification.request();
    
    // Request other essential permissions
    await [
      Permission.camera,
      Permission.location,
      Permission.locationAlways,
    ].request();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShaRogai Worker',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
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
