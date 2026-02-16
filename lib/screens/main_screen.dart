import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:async';
import '../models/alert_model.dart';
import '../services/motion_detector.dart';
import '../services/frame_service.dart';
import '../services/brain_service.dart';
import '../services/background_service.dart';
import '../services/voice_service.dart';
import '../services/chat_service.dart';
import '../widgets/status_indicator.dart';
import '../widgets/alert_card.dart';

class WMainScreen extends StatefulWidget {
  const WMainScreen({Key? key}) : super(key: key);

  @override
  State<WMainScreen> createState() => _WMainScreenState();
}

class _WMainScreenState extends State<WMainScreen> {
  WBrainService? _brainService;
  late SharedPreferences _prefs;
  List<WAlertModel> _alerts = [];
  bool _isOnline = false;
  DateTime? _lastSync;
  bool _isCapturing = false;
  bool _isInitialized = false;

  // Feature toggles
  bool _motionEnabled = false;
  bool _voiceEnabled = false;
  bool _recordingEnabled = false;

  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      _initialize();
    });
  }

  Future<void> _initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      
      final brainUrl = _prefs.getString('brain_url');
      final deviceName = _prefs.getString('device_name');

      if (brainUrl == null || deviceName == null) {
        if (mounted) Navigator.of(context).pushReplacementNamed('/connect');
        return;
      }

      _brainService = WBrainService(brainUrl: brainUrl, deviceName: deviceName);

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _motionEnabled = _prefs.getBool('motion_enabled') ?? false;
          _voiceEnabled = _prefs.getBool('voice_enabled') ?? false;
          _recordingEnabled = _prefs.getBool('recording_enabled') ?? false;
        });
      }

      await _checkStatus();
      await WBackgroundService.start();

      _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _checkStatus();
      });
    } catch (e) {
      debugPrint('[WMain] Init error: $e');
    }
  }

  Future<void> _checkStatus() async {
    if (_brainService == null || !mounted) return;
    try {
      await _brainService!.getStatus();
      final events = await _brainService!.getEvents();
      if (mounted) {
        setState(() {
          _isOnline = true;
          _lastSync = DateTime.now();
          if (events.isNotEmpty) {
            _alerts.insertAll(0, events);
            if (_alerts.length > 20) _alerts = _alerts.sublist(0, 20);
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isOnline = false);
    }
  }

  Future<void> _toggleMotion(bool value) async {
    setState(() => _motionEnabled = value);
    await _prefs.setBool('motion_enabled', value);
    FlutterBackgroundService().invoke('toggle_camera', {'enable': value});
  }

  Future<void> _toggleVoice(bool value) async {
    setState(() => _voiceEnabled = value);
    await _prefs.setBool('voice_enabled', value);
    // Future: Toggle background voice listener
  }

  Future<void> _toggleRecording(bool value) async {
    setState(() => _recordingEnabled = value);
    await _prefs.setBool('recording_enabled', value);
  }

  Future<void> _takePhoto() async {
    if (_brainService == null) return;
    setState(() => _isCapturing = true);
    try {
      final frameService = WFrameService();
      await frameService.initialize();
      final frameBytes = await frameService.captureFrame();
      final compressed = frameService.compressFrame(frameBytes);
      await _brainService!.sendFrame(compressed, context: {
        'source': 'manual_photo',
        'timestamp': DateTime.now().toIso8601String(),
      });
      if (mounted) {
        setState(() {
          _alerts.insert(0, WAlertModel(type: 'manual_photo', message: 'Test photo sent', severity: 'low'));
        });
      }
      await frameService.dispose();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo failed: $e')));
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Colors.amber)));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ShaRogai Dashboard'),
        backgroundColor: Colors.amber,
        actions: [
          IconButton(
            icon: const Icon(Icons.chat),
            onPressed: () => Navigator.pushNamed(context, '/chat'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                WStatusIndicator(isOnline: _isOnline),
                const SizedBox(width: 8),
                Text(_isOnline ? 'Online' : 'Offline', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildStatusCard(),
            const SizedBox(height: 24),
            _buildFeatureToggles(),
            const SizedBox(height: 24),
            _buildActionButtons(),
            const SizedBox(height: 24),
            Align(alignment: Alignment.centerLeft, child: Text('Activity Log', style: Theme.of(context).textTheme.titleMedium)),
            const SizedBox(height: 12),
            _buildAlertsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 0,
      color: Colors.grey[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _statusRow('Brain Connection', _isOnline ? '🟢 Connected' : '🔴 Disconnected'),
            _statusRow('Device ID', _brainService?.deviceName ?? 'Worker'),
            const Divider(height: 24),
            _statusRow('Last Sync', _lastSync == null ? 'Never' : '${_lastSync!.hour}:${_lastSync!.minute.toString().padLeft(2, '0')}'),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureToggles() {
    return Column(
      children: [
        _featureToggle('Motion Monitoring', 'Detect and send movement', _motionEnabled, _toggleMotion, Colors.red),
        const SizedBox(height: 8),
        _featureToggle('Voice Detection', 'Listen for audio events', _voiceEnabled, _toggleVoice, Colors.purple),
        const SizedBox(height: 8),
        _featureToggle('Local Recording', 'Save buffer to phone', _recordingEnabled, _toggleRecording, Colors.blue),
      ],
    );
  }

  Widget _featureToggle(String title, String subtitle, bool val, Function(bool) onChanged, Color color) {
    return Card(
      elevation: 0,
      color: val ? color.withOpacity(0.05) : Colors.grey[50],
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        value: val,
        onChanged: onChanged,
        activeColor: color,
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isCapturing ? null : _takePhoto,
            icon: const Icon(Icons.camera_alt),
            label: _isCapturing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Test Photo'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/controls'),
            icon: const Icon(Icons.settings_remote),
            label: const Text('Controls'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _statusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: const TextStyle(color: Colors.black54)), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))],
      ),
    );
  }

  Widget _buildAlertsList() {
    if (_alerts.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No events recorded')));
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _alerts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) => WAlertCard(alert: _alerts[index]),
    );
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}
