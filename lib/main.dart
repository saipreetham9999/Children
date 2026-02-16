import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'screens/connect_screen.dart';
import 'screens/register_screen.dart';
import 'screens/main_screen.dart';
import 'screens/chat_screen.dart';
import 'services/background_service.dart';
import 'services/chat_service.dart';
import 'services/voice_service.dart';
import 'services/signal_strength_tracker.dart';
import 'services/speaker_controller.dart';
import 'services/bluetooth_connectivity.dart';

/// ShaRogai — Motion Detection & Smart Home Control
/// Phase MVP: Connect + Register + Status
/// Phase 2.1: Manual photo capture
/// Phase 2.2: Motion detection + frame sending
/// Phase 2.3: Continuous background monitoring + Group commands
/// Phase 3: Group Chat + Voice + Bluetooth + Signal Tracking
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request permissions FIRST (before background service)
  await _requestPermissions();

  // Initialize services
  await WBackgroundService.initialize();
  final chatService = WChatService();
  await chatService.initialize();

  final voiceService = WVoiceService();
  await voiceService.initialize();

  final signalTracker = WSignalStrengthTracker();
  signalTracker.initialize();

  final speakerController = WSpeakerController();
  await speakerController.initialize();

  final bluetoothConnectivity = WBluetoothConnectivity();
  await bluetoothConnectivity.initialize();

  runApp(WApp(
    chatService: chatService,
    signalTracker: signalTracker,
    speakerController: speakerController,
    bluetoothConnectivity: bluetoothConnectivity,
  ));
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
  final WChatService chatService;
  final WSignalStrengthTracker signalTracker;
  final WSpeakerController speakerController;
  final WBluetoothConnectivity bluetoothConnectivity;

  const WApp({
    Key? key,
    required this.chatService,
    required this.signalTracker,
    required this.speakerController,
    required this.bluetoothConnectivity,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<WChatService>.value(value: chatService),
        ChangeNotifierProvider<WSignalStrengthTracker>.value(
            value: signalTracker),
        ChangeNotifierProvider<WSpeakerController>.value(
            value: speakerController),
        ChangeNotifierProvider<WBluetoothConnectivity>.value(
            value: bluetoothConnectivity),
      ],
      child: MaterialApp(
        title: 'ShaRogai',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.amber,
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
          '/chat': (_) => const WChatScreen(),
        },
      ),
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
                  Text('ShaRogai'),
                  SizedBox(height: 4),
                  Text(
                    'Motion Detection & Smart Home',
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
