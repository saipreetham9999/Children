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
    setState(() {
      _isCapturing = true;
    });

    try {
      final frameService = WFrameService();
      await frameService.initialize();

      final frameBytes = await frameService.captureFrame();
      final compressed = frameService.compressFrame(frameBytes);

      await _brainService.sendFrame(compressed);

      // Add to alerts
      if (mounted) {
        setState(() {
          _alerts.insert(
            0,
            WAlertModel(
              type: 'manual_photo',
              message: 'Photo sent to Brain',
              severity: 'low',
            ),
          );
        });
      }

      await frameService.dispose();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Worker'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
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
