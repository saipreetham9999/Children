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

// Services — critical (always loaded before UI)
import 'package:worker/services/background_service.dart';
import 'package:worker/services/chat_service.dart';
import 'package:worker/services/signal_strength_tracker.dart';

// Services — optional (loaded lazily in background)
import 'package:worker/services/voice_service.dart';
import 'package:worker/services/speaker_controller.dart';
import 'package:worker/services/bluetooth_connectivity.dart';
import 'package:worker/services/media_playback_controller.dart';
import 'package:worker/services/ios_child_control.dart';
import 'package:worker/services/child_os_monitor.dart';
import 'package:worker/services/device_policy_service.dart';

/// main() — Fast boot: only start background service, show UI immediately.
/// Everything else loads after the screen is visible.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only the non-hardware background service channel setup — no blocking I/O
  await WBackgroundService.initialize();

  runApp(const WAppBootstrapper());
}

// ─────────────────────────────────────────────────────────────────────────────
// WAppBootstrapper — Phase 1: Show UI instantly, Phase 2: Load services
// ─────────────────────────────────────────────────────────────────────────────

class WAppBootstrapper extends StatefulWidget {
  const WAppBootstrapper({Key? key}) : super(key: key);

  @override
  State<WAppBootstrapper> createState() => _WAppBootstrapperState();
}

class _WAppBootstrapperState extends State<WAppBootstrapper> {
  // ── Phase 1: Critical services (needed before ANY screen) ─────────────────
  WChatService? _chatService;
  WSignalStrengthTracker? _signalTracker;

  // ── Phase 2: Optional services (loaded after UI is up) ───────────────────
  WSpeakerController? _speakerController;
  WBluetoothConnectivity? _bluetoothConnectivity;
  WMediaPlaybackController? _mediaPlayback;
  WiOSChildControl? _childControl;
  WChildOSMonitor? _childMonitor;
  WDevicePolicyService? _policyService;

  // Boot state
  bool _criticalReady = false;   // Phase 1 done → show UI
  bool _optionalReady = false;   // Phase 2 done → all services up
  String _bootStatus = 'Starting...';

  @override
  void initState() {
    super.initState();
    _bootPhase1();
  }

  // ── Phase 1: Permissions + Critical services (~0.5s) ─────────────────────
  Future<void> _bootPhase1() async {
    _setStatus('Requesting permissions...');
    await _requestPermissions();

    _setStatus('Starting core services...');
    try {
      _chatService = WChatService();
      await _chatService!.initialize();
    } catch (e) {
      print('[Boot P1] ChatService error (non-fatal): $e');
      _chatService = WChatService(); // fallback: uninit is fine
    }

    try {
      _signalTracker = WSignalStrengthTracker();
      _signalTracker!.initialize();
    } catch (e) {
      print('[Boot P1] SignalTracker error (non-fatal): $e');
      _signalTracker = WSignalStrengthTracker();
    }

    // ✅ UI is ready — show the app NOW
    _setStatus('Ready');
    if (mounted) setState(() => _criticalReady = true);

    // Phase 2 runs in background — does NOT block the UI
    _bootPhase2();
  }

  // ── Phase 2: Optional heavy services (background, ~2-4s) ─────────────────
  Future<void> _bootPhase2() async {
    print('[Boot P2] Loading optional services in background...');

    _speakerController = WSpeakerController();
    await _safeInit(() => _speakerController!.initialize(), 'SpeakerController');
    await Future.delayed(const Duration(milliseconds: 150));

    _mediaPlayback = WMediaPlaybackController();
    await _safeInit(() => _mediaPlayback!.initialize(), 'MediaPlayback');
    await Future.delayed(const Duration(milliseconds: 150));

    _bluetoothConnectivity = WBluetoothConnectivity();
    await _safeInit(() => _bluetoothConnectivity!.initialize(), 'Bluetooth');
    await Future.delayed(const Duration(milliseconds: 150));

    _childControl = WiOSChildControl();
    await _safeInit(() => _childControl!.initialize(), 'iOSChildControl');

    _childMonitor = WChildOSMonitor();

    _policyService = WDevicePolicyService();
    _safeRun(() => _policyService!.initialize(), 'PolicyService');

    // VoiceService (last — heaviest)
    await Future.delayed(const Duration(milliseconds: 200));
    await _safeInit(() async {
      final v = WVoiceService();
      await v.initialize();
    }, 'VoiceService');

    print('[Boot P2] ✅ All optional services loaded');

    // Trigger a rebuild to inject optional providers
    if (mounted) setState(() => _optionalReady = true);
  }

  Future<void> _safeInit(Future<void> Function() fn, String name) async {
    try {
      await fn();
      print('[Boot P2] ✅ $name ready');
    } catch (e) {
      print('[Boot P2] ⚠️  $name failed (non-fatal): $e');
    }
  }

  void _safeRun(void Function() fn, String name) {
    try {
      fn();
    } catch (e) {
      print('[Boot P2] ⚠️  $name failed (non-fatal): $e');
    }
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _bootStatus = s);
  }

  // ── Permissions ──────────────────────────────────────────────────────────
  Future<void> _requestPermissions() async {
    try {
      await Permission.notification.request();
      await [
        Permission.camera,
        Permission.microphone,
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
    } catch (e) {
      print('[Boot] Permission error (non-fatal): $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Phase 1 not done yet — show minimal splash
    if (!_criticalReady) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _SplashScreen(status: _bootStatus),
      );
    }

    // Build provider list — always add critical, add optional when ready
    final providers = <ChangeNotifierProvider>[
      ChangeNotifierProvider<WChatService>.value(value: _chatService!),
      ChangeNotifierProvider<WSignalStrengthTracker>.value(value: _signalTracker!),
    ];

    if (_optionalReady) {
      if (_speakerController != null) {
        providers.add(ChangeNotifierProvider<WSpeakerController>.value(value: _speakerController!));
      }
      if (_bluetoothConnectivity != null) {
        providers.add(ChangeNotifierProvider<WBluetoothConnectivity>.value(value: _bluetoothConnectivity!));
      }
      if (_mediaPlayback != null) {
        providers.add(ChangeNotifierProvider<WMediaPlaybackController>.value(value: _mediaPlayback!));
      }
      if (_childControl != null) {
        providers.add(ChangeNotifierProvider<WiOSChildControl>.value(value: _childControl!));
      }
      if (_childMonitor != null) {
        providers.add(ChangeNotifierProvider<WChildOSMonitor>.value(value: _childMonitor!));
      }
      if (_policyService != null) {
        providers.add(ChangeNotifierProvider<WDevicePolicyService>.value(value: _policyService!));
      }
    }

    return MultiProvider(
      providers: providers,
      child: WAppContent(optionalServicesReady: _optionalReady),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Splash Screen — shown only during Phase 1 (~0.5s)
// ─────────────────────────────────────────────────────────────────────────────

class _SplashScreen extends StatelessWidget {
  final String status;
  const _SplashScreen({required this.status});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(
                color: Colors.amber,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('W', style: TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 24),
            const Text('ShaRogai', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 3)),
            const SizedBox(height: 16),
            Text(status, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WAppContent — The actual MaterialApp with routing
// ─────────────────────────────────────────────────────────────────────────────

class WAppContent extends StatelessWidget {
  final bool optionalServicesReady;
  const WAppContent({Key? key, required this.optionalServicesReady}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShaRogai',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
      ),
      home: const _WInitialRoute(),
      routes: {
        '/connect': (_) => const WConnectScreen(),
        '/register': (_) => WRegisterScreen(
              brainUrl: (ModalRoute.of(_)?.settings.arguments as Map?)?['brainUrl']
                  ?? 'http://192.168.0.183:8080',
            ),
        '/main': (_) => const WMainScreen(),
        '/chat': (_) => const WChatScreen(),
        '/controls': (_) => const WChildControlScreen(),
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WInitialRoute — decides Connect vs Main on startup
// ─────────────────────────────────────────────────────────────────────────────

class _WInitialRoute extends StatefulWidget {
  const _WInitialRoute({Key? key}) : super(key: key);

  @override
  State<_WInitialRoute> createState() => _WInitialRouteState();
}

class _WInitialRouteState extends State<_WInitialRoute> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    final prefs = await SharedPreferences.getInstance();
    final brainUrl = prefs.getString('brain_url');
    final deviceName = prefs.getString('device_name');

    if (!mounted) return;

    if (brainUrl != null && brainUrl.isNotEmpty &&
        deviceName != null && deviceName.isNotEmpty) {
      // Already registered — go straight to main
      print('[Router] Already registered as "$deviceName" → /main');
      Navigator.of(context).pushReplacementNamed('/main');
    } else {
      // First time — go to connect
      print('[Router] Not registered → /connect');
      Navigator.of(context).pushReplacementNamed('/connect');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Brief loading indicator while we read SharedPreferences
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 3),
      ),
    );
  }
}
