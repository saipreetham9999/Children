import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'dart:async';

// Screens
import 'package:worker/screens/connect_screen.dart';
import 'package:worker/screens/register_screen.dart';
import 'package:worker/screens/main_screen.dart';
import 'package:worker/screens/chat_screen.dart';
import 'package:worker/screens/child_control_screen.dart';

// Services
import 'package:worker/services/background_service.dart';
import 'package:worker/services/chat_service.dart';
import 'package:worker/services/voice_service.dart';
import 'package:worker/services/signal_strength_tracker.dart';
import 'package:worker/services/speaker_controller.dart';
import 'package:worker/services/bluetooth_connectivity.dart';
import 'package:worker/services/media_playback_controller.dart';
import 'package:worker/services/ios_child_control.dart';
import 'package:worker/services/child_os_monitor.dart';
import 'package:worker/services/device_policy_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initial configuration (No hardware access yet)
  await WBackgroundService.initialize();

  runApp(const WAppBootstrapper());
}

/// A Bootstrapper that handles permissions and gradual service initialization
/// to prevent crashes on Poco/Xiaomi devices.
class WAppBootstrapper extends StatefulWidget {
  const WAppBootstrapper({Key? key}) : super(key: key);

  @override
  State<WAppBootstrapper> createState() => _WAppBootstrapperState();
}

class _WAppBootstrapperState extends State<WAppBootstrapper> {
  bool _isReady = false;
  
  // All Services
  late WChatService chatService;
  late WSignalStrengthTracker signalTracker;
  late WSpeakerController speakerController;
  late WBluetoothConnectivity bluetoothConnectivity;
  late WMediaPlaybackController mediaPlayback;
  late WiOSChildControl childControl;
  late WChildOSMonitor childMonitor;
  late WDevicePolicyService policyService;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // 1. Permissions - Mandatory first step
      print('[Boot] Requesting Permissions...');
      await Permission.notification.request();
      await [
        Permission.camera,
        Permission.microphone,
        Permission.location,
        Permission.locationAlways,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();

      // Give the OS 1 second to settle after permission dialogs
      await Future.delayed(const Duration(seconds: 1));

      // 2. Gradual Service Initialization (Avoid resource contention)
      print('[Boot] Initializing Services...');
      
      chatService = WChatService();
      await chatService.initialize();
      await Future.delayed(const Duration(milliseconds: 200));

      final voiceService = WVoiceService();
      await voiceService.initialize();
      await Future.delayed(const Duration(milliseconds: 200));

      signalTracker = WSignalStrengthTracker();
      signalTracker.initialize();

      speakerController = WSpeakerController();
      await speakerController.initialize();
      await Future.delayed(const Duration(milliseconds: 200));

      bluetoothConnectivity = WBluetoothConnectivity();
      await bluetoothConnectivity.initialize();
      await Future.delayed(const Duration(milliseconds: 200));

      mediaPlayback = WMediaPlaybackController();
      await mediaPlayback.initialize();

      childControl = WiOSChildControl();
      await childControl.initialize();

      childMonitor = WChildOSMonitor();

      policyService = WDevicePolicyService();
      policyService.initialize();

      print('[Boot] ✅ All systems ready');
      if (mounted) {
        setState(() => _isReady = true);
      }
    } catch (e) {
      print('[Boot] ❌ Fatal Setup Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Colors.amber),
                const SizedBox(height: 24),
                const Text('Initializing ShaRogai...', style: TextStyle(fontWeight: FontWeight.bold)),
                const Text('Setting up secure services', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<WChatService>.value(value: chatService),
        ChangeNotifierProvider<WSignalStrengthTracker>.value(value: signalTracker),
        ChangeNotifierProvider<WSpeakerController>.value(value: speakerController),
        ChangeNotifierProvider<WBluetoothConnectivity>.value(value: bluetoothConnectivity),
        ChangeNotifierProvider<WMediaPlaybackController>.value(value: mediaPlayback),
        ChangeNotifierProvider<WiOSChildControl>.value(value: childControl),
        ChangeNotifierProvider<WChildOSMonitor>.value(value: childMonitor),
        ChangeNotifierProvider<WDevicePolicyService>.value(value: policyService),
      ],
      child: const WAppContent(),
    );
  }
}

class WAppContent extends StatelessWidget {
  const WAppContent({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShaRogai',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
      ),
      home: const WConnectScreen(),
      routes: {
        '/connect': (_) => const WConnectScreen(),
        '/register': (_) => WRegisterScreen(
              brainUrl: (ModalRoute.of(_)?.settings.arguments as Map?)?['brainUrl'] ?? 'http://192.168.0.183:8080',
            ),
        '/main': (_) => const WMainScreen(),
        '/chat': (_) => const WChatScreen(),
        '/controls': (_) => const WChildControlScreen(),
      },
    );
  }
}
