import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

// Screens
import 'package:worker/screens/connect_screen.dart';
import 'package:worker/screens/register_screen.dart';
import 'package:worker/screens/main_screen.dart';
import 'package:worker/screens/chat_screen.dart';
import 'package:worker/screens/child_control_screen.dart';

// Services
import 'package:worker/services/chat_service.dart';
import 'package:worker/services/signal_strength_tracker.dart';
import 'package:worker/services/background_service.dart';
import 'package:worker/services/voice_service.dart';
import 'package:worker/services/speaker_controller.dart';
import 'package:worker/services/bluetooth_connectivity.dart';
import 'package:worker/services/media_playback_controller.dart';
import 'package:worker/services/ios_child_control.dart';
import 'package:worker/services/child_os_monitor.dart';
import 'package:worker/services/device_policy_service.dart';
import 'package:worker/services/ble_mesh_service.dart';
import 'package:worker/services/mesh_chat_transport.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WAppBootstrapper());
}

class WAppBootstrapper extends StatefulWidget {
  const WAppBootstrapper({Key? key}) : super(key: key);

  @override
  State<WAppBootstrapper> createState() => _WAppBootstrapperState();
}

class _WAppBootstrapperState extends State<WAppBootstrapper> {
  WChatService? _chatService;
  WSignalStrengthTracker? _signalTracker;
  WSpeakerController? _speakerController;
  WBluetoothConnectivity? _bluetoothConnectivity;
  WMediaPlaybackController? _mediaPlayback;
  WiOSChildControl? _childControl;
  WChildOSMonitor? _childMonitor;
  WDevicePolicyService? _policyService;
  WBleMeshService? _meshService;
  WMeshChatTransport? _meshChatTransport;

  bool _isInitialized = false;
  String _bootStatus = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _fullBoot();
  }

  Future<void> _fullBoot() async {
    try {
      _setStatus('Checking Permissions...');
      await _requestPermissions();
      await Future.delayed(const Duration(milliseconds: 500));

      // Sequential initialization of ALL services before showing ANY app UI
      _setStatus('Loading Chat...');
      _chatService = WChatService();
      await _chatService!.initialize();

      _setStatus('Loading Signals...');
      _signalTracker = WSignalStrengthTracker();
      _signalTracker!.initialize();

      _setStatus('Loading Background Link...');
      await WBackgroundService.initialize();
      await Future.delayed(const Duration(milliseconds: 200));

      _setStatus('Loading Audio...');
      _speakerController = WSpeakerController();
      await _speakerController!.initialize();

      _setStatus('Loading Media...');
      _mediaPlayback = WMediaPlaybackController();
      await _mediaPlayback!.initialize();

      _setStatus('Loading Bluetooth...');
      _bluetoothConnectivity = WBluetoothConnectivity();
      await _bluetoothConnectivity!.initialize();

      _setStatus('Loading Child Controls...');
      _childControl = WiOSChildControl();
      await _childControl!.initialize();
      _childMonitor = WChildOSMonitor();

      _setStatus('Loading Security Policies...');
      _policyService = WDevicePolicyService();
      _policyService!.initialize();

      _setStatus('Loading Voice Recognition...');
      final voice = WVoiceService();
      await voice.initialize();

      _setStatus('Loading BLE Mesh...');
      _meshService = WBleMeshService();
      _meshChatTransport = WMeshChatTransport(
        meshService: _meshService!,
        chatService: _chatService!,
        signalTracker: _signalTracker!,
      );
      await _meshChatTransport!.initialize();

      _setStatus('Finalizing...');
      await Future.delayed(const Duration(milliseconds: 500));

      print('[Boot] ✅ Full System Initialization Complete');
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      print('[Boot] ❌ Critical Setup Error: $e');
      _setStatus('Initialization Failed: $e');
    }
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _bootStatus = s);
  }

  Future<void> _requestPermissions() async {
    await Permission.notification.request();
    await [
      Permission.camera,
      Permission.microphone,
      Permission.location,
      Permission.locationAlways,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber)),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Colors.amber, strokeWidth: 3),
                const SizedBox(height: 24),
                Text('ShaRogai', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_bootStatus, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<WChatService>.value(value: _chatService!),
        ChangeNotifierProvider<WSignalStrengthTracker>.value(value: _signalTracker!),
        ChangeNotifierProvider<WSpeakerController>.value(value: _speakerController!),
        ChangeNotifierProvider<WBluetoothConnectivity>.value(value: _bluetoothConnectivity!),
        ChangeNotifierProvider<WMediaPlaybackController>.value(value: _mediaPlayback!),
        ChangeNotifierProvider<WiOSChildControl>.value(value: _childControl!),
        ChangeNotifierProvider<WChildOSMonitor>.value(value: _childMonitor!),
        ChangeNotifierProvider<WDevicePolicyService>.value(value: _policyService!),
        ChangeNotifierProvider<WBleMeshService>.value(value: _meshService!),
        ChangeNotifierProvider<WMeshChatTransport>.value(value: _meshChatTransport!),
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
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
      ),
      home: const _StartRouter(),
      routes: {
        '/connect': (_) => const WConnectScreen(),
        '/register': (_) => WRegisterScreen(
              brainUrl: (ModalRoute.of(_)?.settings.arguments as Map?)?['brainUrl'] ?? '',
            ),
        '/main': (_) => const WMainScreen(),
        '/chat': (_) => const WChatScreen(),
        '/controls': (_) => const WChildControlScreen(),
      },
    );
  }
}

class _StartRouter extends StatefulWidget {
  const _StartRouter({Key? key}) : super(key: key);

  @override
  State<_StartRouter> createState() => _StartRouterState();
}

class _StartRouterState extends State<_StartRouter> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    final prefs = await SharedPreferences.getInstance();
    final brainUrl = prefs.getString('brain_url') ?? '';
    final deviceName = prefs.getString('device_name') ?? '';

    if (!mounted) return;

    if (brainUrl.isNotEmpty && deviceName.isNotEmpty) {
      Navigator.of(context).pushReplacementNamed('/main');
    } else {
      Navigator.of(context).pushReplacementNamed('/connect');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.amber)));
  }
}
