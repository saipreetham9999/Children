import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:async';
import '../models/alert_model.dart';
import '../services/motion_detector.dart';
import '../services/frame_service.dart';
import '../services/brain_service.dart';
import '../services/background_service.dart';
import '../widgets/status_indicator.dart';
import '../widgets/alert_card.dart';

class WMainScreen extends StatefulWidget {
  const WMainScreen({Key? key}) : super(key: key);

  @override
  State<WMainScreen> createState() => _WMainScreenState();
}

class _WMainScreenState extends State<WMainScreen> {
  WBrainService? _brainService;
  SharedPreferences? _prefs;
  List<WAlertModel> _alerts = [];
  bool _isOnline = false;
  DateTime? _lastSync;
  bool _isCapturing = false;
  bool _isInitialized = false;
  bool _motionEnabled = false;

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
      
      final brainUrl = _prefs!.getString('brain_url');
      final deviceName = _prefs!.getString('device_name');

      if (brainUrl == null || deviceName == null) {
        if (mounted) Navigator.of(context).pushReplacementNamed('/connect');
        return;
      }

      _brainService = WBrainService(brainUrl: brainUrl, deviceName: deviceName);

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _motionEnabled = _prefs!.getBool('motion_enabled') ?? false;
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

  Future<void> _toggleMotion(bool value) async {
    setState(() => _motionEnabled = value);
    await _prefs?.setBool('motion_enabled', value);
    
    // Notify background service
    FlutterBackgroundService().invoke('toggle_camera', {'enable': value});
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
        title: const Text('Dashboard'),
        backgroundColor: Colors.amber,
        actions: [
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
            _buildMotionToggle(),
            const SizedBox(height: 12),
            _buildActions(),
            const SizedBox(height: 24),
            Align(alignment: Alignment.centerLeft, child: Text('Activity', style: Theme.of(context).textTheme.titleMedium)),
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
            _statusRow('Brain', _isOnline ? 'Connected' : 'Searching...'),
            _statusRow('Device', _brainService?.deviceName ?? 'Worker'),
            _statusRow('Target IP', _brainService?.brainUrl ?? '127.0.0.1'),
            const Divider(height: 24),
            _statusRow('Last Sync', _lastSync == null ? 'Never' : '${_lastSync!.hour}:${_lastSync!.minute.toString().padLeft(2, '0')}'),
          ],
        ),
      ),
    );
  }

  Widget _buildMotionToggle() {
    return Card(
      elevation: 0,
      color: _motionEnabled ? Colors.green[50] : Colors.red[50],
      child: SwitchListTile(
        title: const Text('Motion Monitoring', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(_motionEnabled ? 'Camera is active in background' : 'Camera is off (Standby mode)'),
        value: _motionEnabled,
        onChanged: _toggleMotion,
        activeColor: Colors.green,
      ),
    );
  }

  Widget _buildActions() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _isCapturing ? null : _takePhoto,
        icon: const Icon(Icons.camera_alt),
        label: _isCapturing ? const CircularProgressIndicator() : const Text('Test Camera (Manual)'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
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
    if (_alerts.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No events')));
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
