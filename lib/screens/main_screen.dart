import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../models/alert_model.dart';
import '../services/motion_detector.dart';
import '../services/frame_service.dart';
import '../services/brain_service.dart';
import '../widgets/status_indicator.dart';
import '../widgets/alert_card.dart';

/// WMainScreen — Phase MVP: Status, alerts, manual photo
/// Phase 2.1: "Take Photo" button
/// Phase 2.2: Background motion detection
/// Phase 2.3: Continuous monitoring running
class WMainScreen extends StatefulWidget {
  const WMainScreen({Key? key}) : super(key: key);

  @override
  State<WMainScreen> createState() => _WMainScreenState();
}

class _WMainScreenState extends State<WMainScreen> {
  late WBrainService _brainService;
  late SharedPreferences _prefs;
  List<WAlertModel> _alerts = [];
  bool _isOnline = false;
  DateTime? _lastSync;
  bool _isCapturing = false;
  String? _statsText;

  // Feature toggles
  bool _motionDetectionEnabled = true;
  bool _voiceDetectionEnabled = false;
  bool _recordingEnabled = false;

  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final brainUrl = _prefs.getString('brain_url') ?? 'http://localhost:8080';
      final deviceName = _prefs.getString('device_name') ?? 'Worker';

      _brainService = WBrainService(
        brainUrl: brainUrl,
        deviceName: deviceName,
      );

      // Load feature preferences
      setState(() {
        _motionDetectionEnabled = _prefs.getBool('motion_enabled') ?? true;
        _voiceDetectionEnabled = _prefs.getBool('voice_enabled') ?? false;
        _recordingEnabled = _prefs.getBool('recording_enabled') ?? false;
      });

      // Check status
      await _checkStatus();

      // Start sync timer (every 2 seconds)
      _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _checkStatus();
      });
    } catch (e) {
      print('[WMain] Init error: $e');
    }
  }

  /// Toggle motion detection feature
  Future<void> _toggleMotionDetection(bool value) async {
    setState(() => _motionDetectionEnabled = value);
    await _prefs.setBool('motion_enabled', value);
    print('[Dashboard] Motion detection ${value ? 'enabled' : 'disabled'}');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value ? '📹 Motion detection enabled' : '⏸️ Motion detection disabled',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// Toggle voice detection feature
  Future<void> _toggleVoiceDetection(bool value) async {
    setState(() => _voiceDetectionEnabled = value);
    await _prefs.setBool('voice_enabled', value);
    print('[Dashboard] Voice detection ${value ? 'enabled' : 'disabled'}');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value ? '🎤 Voice detection enabled' : '⏸️ Voice detection disabled',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// Toggle recording feature
  Future<void> _toggleRecording(bool value) async {
    setState(() => _recordingEnabled = value);
    await _prefs.setBool('recording_enabled', value);
    print('[Dashboard] Recording ${value ? 'enabled' : 'disabled'}');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value ? '⏺️ Recording enabled' : '⏹️ Recording disabled',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _checkStatus() async {
    try {
      final status = await _brainService.getStatus();
      final events = await _brainService.getEvents();

      if (mounted) {
        setState(() {
          _isOnline = true;
          _lastSync = DateTime.now();
          if (events.isNotEmpty) {
            _alerts.insertAll(0, events);
            // Keep only last 20 alerts
            if (_alerts.length > 20) {
              _alerts = _alerts.sublist(0, 20);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isOnline = false;
        });
      }
    }
  }

  /// Phase 2.1: Take manual photo
  Future<void> _takePhoto() async {
    print('[TakePhoto] Starting manual photo capture...');
    setState(() {
      _isCapturing = true;
    });

    try {
      print('[TakePhoto] Initializing frame service...');
      final frameService = WFrameService();
      await frameService.initialize();
      print('[TakePhoto] ✅ Frame service ready');

      print('[TakePhoto] Capturing frame...');
      final frameBytes = await frameService.captureFrame();
      print('[TakePhoto] ✅ Frame captured: ${frameBytes.length} bytes');

      print('[TakePhoto] Compressing frame...');
      final compressed = frameService.compressFrame(frameBytes);
      print('[TakePhoto] ✅ Compressed: ${compressed.length} bytes');

      print('[TakePhoto] Sending to Brain at ${_brainService.brainUrl}');
      await _brainService.sendFrame(compressed);
      print('[TakePhoto] ✅ Frame sent successfully');

      // Add to alerts
      if (mounted) {
        setState(() {
          _alerts.insert(
            0,
            WAlertModel(
              type: 'manual_photo',
              message: 'Photo sent to Brain (${compressed.length} bytes)',
              severity: 'low',
            ),
          );
        });
      }

      // Show success feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Photo sent to Brain'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      await frameService.dispose();
    } catch (e) {
      print('[TakePhoto] ❌ Error: $e');
      print('[TakePhoto] Error type: ${e.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Photo failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  /// Build feature card with toggle
  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required Function(bool) onToggle,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: Switch(
          value: enabled,
          onChanged: onToggle,
          activeColor: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ShaRogai'),
        centerTitle: true,
        backgroundColor: Colors.amber,
        actions: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Row(
                children: [
                  WStatusIndicator(isOnline: _isOnline),
                  const SizedBox(width: 8),
                  Text(
                    _isOnline ? 'Online' : 'Offline',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Status Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Status', style: TextStyle(fontSize: 16)),
                      Text(
                        _isOnline ? '🟢 Online' : '🔴 Offline',
                        style: TextStyle(
                          fontSize: 14,
                          color: _isOnline ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Last Sync', style: TextStyle(fontSize: 14)),
                      Text(
                        _lastSync == null
                            ? 'Never'
                            : '${_lastSync!.hour}:${_lastSync!.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Alerts', style: TextStyle(fontSize: 14)),
                      Text(
                        '${_alerts.length}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Feature Cards Section
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Features',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            // Motion Detection Card
            _buildFeatureCard(
              icon: Icons.motion_photos_on,
              title: 'Motion Detection',
              subtitle: 'Detect movement and send frames',
              enabled: _motionDetectionEnabled,
              onToggle: _toggleMotionDetection,
              color: Colors.red,
            ),
            const SizedBox(height: 12),
            // Voice Detection Card
            _buildFeatureCard(
              icon: Icons.mic,
              title: 'Voice Detection',
              subtitle: 'Listen for sound/commands',
              enabled: _voiceDetectionEnabled,
              onToggle: _toggleVoiceDetection,
              color: Colors.purple,
            ),
            const SizedBox(height: 12),
            // Recording Card
            _buildFeatureCard(
              icon: Icons.videocam,
              title: 'Recording',
              subtitle: 'Record audio/video on motion',
              enabled: _recordingEnabled,
              onToggle: _toggleRecording,
              color: Colors.blue,
            ),
            const SizedBox(height: 24),
            // Phase 2.1: Take Photo Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isCapturing ? null : _takePhoto,
                icon: const Icon(Icons.camera_alt),
                label: _isCapturing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Take Photo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Alerts Header
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent Alerts (${_alerts.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            // Alerts List
            if (_alerts.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(
                      Icons.inbox,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No alerts yet',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _alerts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, index) => WAlertCard(alert: _alerts[index]),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}
