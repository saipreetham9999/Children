import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_model.dart';
import '../services/brain_service.dart';

/// WRegisterScreen — Phase MVP: Register device with Brain
class WRegisterScreen extends StatefulWidget {
  final String brainUrl;

  const WRegisterScreen({
    Key? key,
    required this.brainUrl,
  }) : super(key: key);

  @override
  State<WRegisterScreen> createState() => _WRegisterScreenState();
}

class _WRegisterScreenState extends State<WRegisterScreen> {
  final _nameController = TextEditingController();
  late WDeviceModel _deviceModel;
  bool _isRegistering = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _detectDeviceInfo();
  }

  Future<void> _detectDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String deviceType = 'unknown';
      String osVersion = 'unknown';
      String deviceModel = 'unknown';
      String defaultName = 'Worker Device';

      if (Theme.of(context).platform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceType = 'android';
        osVersion = 'Android ${androidInfo.version.release}';
        deviceModel = androidInfo.model;
        defaultName = androidInfo.model;
      } else if (Theme.of(context).platform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceType = 'ios';
        osVersion = 'iOS ${iosInfo.systemVersion}';
        deviceModel = iosInfo.utsname.machine;
        defaultName = deviceModel;
      }

      _deviceModel = WDeviceModel(
        deviceName: defaultName,
        deviceType: deviceType,
        osVersion: osVersion,
        deviceModel: deviceModel,
        capabilities: ['camera', 'screen', 'audio'],
      );

      if (mounted) {
        setState(() {
          _nameController.text = _deviceModel.deviceName;
        });
      }
    } catch (e) {
      print('[WRegister] Device detect error: $e');
      _deviceModel = WDeviceModel(
        deviceName: 'Worker',
        deviceType: 'unknown',
        osVersion: 'unknown',
        deviceModel: 'unknown',
      );
    }
  }

  Future<void> _registerDevice() async {
    setState(() {
      _isRegistering = true;
      _errorMessage = null;
    });

    try {
      final updatedDevice = WDeviceModel(
        deviceName: _nameController.text.trim(),
        deviceType: _deviceModel.deviceType,
        osVersion: _deviceModel.osVersion,
        deviceModel: _deviceModel.deviceModel,
        capabilities: _deviceModel.capabilities,
      );

      final brainService = WBrainService(
        brainUrl: widget.brainUrl,
        deviceName: updatedDevice.deviceName,
      );

      final response = await brainService.connect(updatedDevice);

      // Save to device
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_name', updatedDevice.deviceName);
      await prefs.setString('device_type', updatedDevice.deviceType);
      await prefs.setString('brain_url', widget.brainUrl);

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/main');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Registration failed: $e';
        _isRegistering = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Worker — Register'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text(
              'Device Registration',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            // Device Name
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Device Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.phone_android),
              ),
              enabled: !_isRegistering,
            ),
            const SizedBox(height: 24),
            // Device Info (read-only)
            _buildInfoCard('Device Type', _deviceModel.deviceType),
            const SizedBox(height: 16),
            _buildInfoCard('Device Model', _deviceModel.deviceModel),
            const SizedBox(height: 16),
            _buildInfoCard('OS Version', _deviceModel.osVersion),
            const SizedBox(height: 16),
            _buildInfoCard(
              'Capabilities',
              _deviceModel.capabilities.join(', '),
            ),
            const SizedBox(height: 48),
            // Register Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isRegistering ? null : _registerDevice,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                ),
                child: _isRegistering
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        'Register with Brain',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}
