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
import 'package:worker/screens/transition_screen.dart';

// Services — Phase 1: critical (tiny, fast)
import 'package:worker/services/chat_service.dart';
import 'package:worker/services/signal_strength_tracker.dart';

// Services — Phase 2: optional (heavy, deferred)
import 'package:worker/services/background_service.dart';
import 'package:worker/services/voice_service.dart';
import 'package:worker/services/speaker_controller.dart';
import 'package:worker/services/bluetooth_connectivity.dart';
import 'package:worker/services/media_playback_controller.dart';
import 'package:worker/services/ios_child_control.dart';
import 'package:worker/services/child_os_monitor.dart';
import 'package:worker/services/device_policy_service.dart';

/// main() — FAST boot: no blocking I/O here.
/// Notification channels are created natively in MainActivity.kt BEFORE this runs.
/// Background service init is deferred to Phase 2 (after UI is visible).
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Nothing heavy here — just launch the app
  runApp(const WAppBootstrapper());
}

// ─────────────────────────────────────────────────────────────────────────────
// WAppBootstrapper — Two-phase loading
//   Phase 1 (~0.5s): permissions + chat + signal → UI visible immediately
//   Phase 2 (background): all heavy services load silently
// ─────────────────────────────────────────────────────────────────────────────

class WAppBootstrapper extends StatefulWidget {
  const WAppBootstrapper({Key? key}) : super(key: key);

  @override
  State<WAppBootstrapper> createState() => _WAppBootstrapperState();
}

class _WAppBootstrapperState extends State<WAppBootstrapper> {
  // ── Phase 1 services ─────────────────────────────────────────────────────
  WChatService? _chatService;
  WSignalStrengthTracker? _signalTracker;

  // ── Phase 2 services ─────────────────────────────────────────────────────
  WSpeakerController? _speakerController;
  WBluetoothConnectivity? _bluetoothConnectivity;
  WMediaPlaybackController? _mediaPlayback;
  WiOSChildControl? _childControl;
  WChildOSMonitor? _childMonitor;
  WDevicePolicyService? _policyService;

  bool _uiReady = false;      // Phase 1 done → show UI
  bool _allReady = false;     // Phase 2 done → all providers injected
  String _bootStatus = 'Starting...';

  @override
  void initState() {
    super.initState();
    _phase1();
  }

  // ── Phase 1: ~0.5s — permissions + 2 lightweight services ────────────────
  Future<void> _phase1() async {
    _setStatus('Requesting permissions...');
    await _requestPermissions();

    _setStatus('Starting core...');

    await _safe(() async {
      _chatService = WChatService();
      await _chatService!.initialize();
    }, 'ChatService');

    await _safe(() async {
      _signalTracker = WSignalStrengthTracker();
      _signalTracker!.initialize();
    }, 'SignalTracker');

    // Fallbacks so providers always have a value
    _chatService ??= WChatService();
    _signalTracker ??= WSignalStrengthTracker();

    _setStatus('Ready');
    if (mounted) setState(() => _uiReady = true);

    // Don't await — Phase 2 runs completely in the background
    _phase2();
  }

  // ── Phase 2: background — all heavy/hardware services ────────────────────
  Future<void> _phase2() async {
    print('[Boot P2] Starting background services...');

    // Background service MUST come first so channel exists when service starts
    await _safe(() => WBackgroundService.initialize(), 'BackgroundService');
    await Future.delayed(const Duration(milliseconds: 100));

    _speakerController = WSpeakerController();
    await _safe(() => _speakerController!.initialize(), 'SpeakerController');
    await Future.delayed(const Duration(milliseconds: 100));

    _mediaPlayback = WMediaPlaybackController();
    await _safe(() => _mediaPlayback!.initialize(), 'MediaPlayback');
    await Future.delayed(const Duration(milliseconds: 100));

    _bluetoothConnectivity = WBluetoothConnectivity();
    await _safe(() => _bluetoothConnectivity!.initialize(), 'Bluetooth');
    await Future.delayed(const Duration(milliseconds: 100));

    _childControl = WiOSChildControl();
    await _safe(() => _childControl!.initialize(), 'iOSChildControl');

    _childMonitor = WChildOSMonitor();

    _policyService = WDevicePolicyService();
    try { _policyService!.initialize(); } catch (e) { print('[Boot P2] PolicyService: $e'); }

    // VoiceService last — heaviest hardware access
    await Future.delayed(const Duration(milliseconds: 150));
    await _safe(() async {
      final v = WVoiceService();
      await v.initialize();
    }, 'VoiceService');

    print('[Boot P2] ✅ All services loaded');
    if (mounted) setState(() => _allReady = true);
  }

  Future<void> _safe(Future<void> Function() fn, String name) async {
    try {
      await fn();
      print('[Boot] ✅ $name');
    } catch (e) {
      print('[Boot] ⚠️  $name failed (non-fatal): $e');
    }
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _bootStatus = s);
  }

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
      print('[Boot] Permissions error (non-fatal): $e');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_uiReady) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _BootSplash(status: _bootStatus),
      );
    }

    // Always-present providers (Phase 1)
    final providers = <ChangeNotifierProvider>[
      ChangeNotifierProvider<WChatService>.value(value: _chatService!),
      ChangeNotifierProvider<WSignalStrengthTracker>.value(value: _signalTracker!),
    ];

    // Phase 2 providers injected once ready
    if (_allReady) {
      if (_speakerController != null)
        providers.add(ChangeNotifierProvider<WSpeakerController>.value(value: _speakerController!));
      if (_bluetoothConnectivity != null)
        providers.add(ChangeNotifierProvider<WBluetoothConnectivity>.value(value: _bluetoothConnectivity!));
      if (_mediaPlayback != null)
        providers.add(ChangeNotifierProvider<WMediaPlaybackController>.value(value: _mediaPlayback!));
      if (_childControl != null)
        providers.add(ChangeNotifierProvider<WiOSChildControl>.value(value: _childControl!));
      if (_childMonitor != null)
        providers.add(ChangeNotifierProvider<WChildOSMonitor>.value(value: _childMonitor!));
      if (_policyService != null)
        providers.add(ChangeNotifierProvider<WDevicePolicyService>.value(value: _policyService!));
    }

    return MultiProvider(
      providers: providers,
      child: _WApp(allReady: _allReady),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Boot Splash — shown for ~0.5s only (Phase 1)
// ─────────────────────────────────────────────────────────────────────────────

class _BootSplash extends StatelessWidget {
  final String status;
  const _BootSplash({required this.status});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
              child: const Center(
                child: Text('W',
                    style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 24),
            const Text('ShaRogai',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            const SizedBox(
                width: 28, height: 28,
                child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 3)),
            const SizedBox(height: 12),
            Text(status, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WApp — MaterialApp with routes + startup routing logic
// ─────────────────────────────────────────────────────────────────────────────

class _WApp extends StatelessWidget {
  final bool allReady;
  const _WApp({required this.allReady});

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
              brainUrl: (ModalRoute.of(_)?.settings.arguments as Map?)?['brainUrl']
                  ?? 'http://192.168.0.183:8080',
            ),
        // Transition screen — shown after register, navigates to /main after 2.5s
        '/transition': (_) => const WTransitionScreen(
              destination: '/main',
              title: 'Setting up your device',
              subtitle: 'Loading all ShaRogai services...',
              durationMs: 2500,
            ),
        '/main': (_) => const WMainScreen(),
        '/chat': (_) => const WChatScreen(),
        '/controls': (_) => const WChildControlScreen(),
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StartRouter — reads SharedPreferences and routes to /main or /connect
// ─────────────────────────────────────────────────────────────────────────────

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
      print('[Router] Returning user "$deviceName" → /main');
      Navigator.of(context).pushReplacementNamed('/main');
    } else {
      print('[Router] New user → /connect');
      Navigator.of(context).pushReplacementNamed('/connect');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
          child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 3)),
    );
  }
}
