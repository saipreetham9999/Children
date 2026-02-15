import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/connect_screen.dart';
import 'screens/register_screen.dart';
import 'screens/main_screen.dart';
import 'services/background_service.dart';

/// Worker — Motion Detection Transmitter App
/// Phase MVP: Connect + Register + Status
/// Phase 2.1: Manual photo capture
/// Phase 2.2: Motion detection + frame sending
/// Phase 2.3: Continuous background monitoring
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background service (Phase 2.3)
  await WBackgroundService.initialize();

  // Request permissions
  await _requestPermissions();

  runApp(const WApp());
}

/// Request all necessary permissions
Future<void> _requestPermissions() async {
  final permissions = [
    Permission.camera,
    Permission.microphone,
    Permission.location,
    Permission.storage,
  ];

  for (var permission in permissions) {
    final status = await permission.request();
    print('[Permissions] ${permission.toString()}: ${status.isDenied}');
  }

  // Background permission (Android 12+)
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }
}

class WApp extends StatelessWidget {
  const WApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Worker',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
        ),
      ),
      home: const _WAppRouter(),
      routes: {
        '/connect': (_) => const WConnectScreen(),
        '/register': (_) => WRegisterScreen(
              brainUrl: ModalRoute.of(_)?.settings.arguments as String? ??
                  'http://localhost:8080',
            ),
        '/main': (_) => const WMainScreen(),
      },
    );
  }
}

/// App router — Navigate based on state
class _WAppRouter extends StatefulWidget {
  const _WAppRouter({Key? key}) : super(key: key);

  @override
  State<_WAppRouter> createState() => _WAppRouterState();
}

class _WAppRouterState extends State<_WAppRouter> {
  late Future<String> _initRoute;

  @override
  void initState() {
    super.initState();
    _initRoute = _determineInitialRoute();
  }

  Future<String> _determineInitialRoute() async {
    await Future.delayed(const Duration(milliseconds: 500));

    // Check if already registered
    // (in real app, check SharedPreferences)
    return '/connect'; // Always start with connect
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _initRoute,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text('Worker'),
                  SizedBox(height: 4),
                  Text(
                    'Motion Detection Transmitter',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        return const WConnectScreen();
      },
    );
  }
}
