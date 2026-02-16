import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_model.dart';
import '../services/brain_service.dart';

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
  WDeviceModel? _deviceModel;
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
      String defaultName = 'ShaRogai-Poco';

      if (Theme.of(context).platform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceType = 'android';
        osVersion = 'Android ${androidInfo.version.release}';
        deviceModel = androidInfo.model;
        defaultName = androidInfo.model;
      }

      setState(() {
        _deviceModel = WDeviceModel(
          deviceName: defaultName,
          deviceType: deviceType,
          osVersion: osVersion,
          deviceModel: deviceModel,
          capabilities: ['camera', 'screen', 'audio'],
        );
        _nameController.text = defaultName;
      });
    } catch (e) {
      print('[WRegister] Detect error: $e');
    }
  }

  Future<void> _registerDevice() async {
    if (_deviceModel == null) return;

    setState(() {
      _isRegistering = true;
      _errorMessage = null;
    });

    try {
      final updatedDevice = WDeviceModel(
        deviceName: _nameController.text.trim(),
        deviceType: _deviceModel!.deviceType,
        osVersion: _deviceModel!.osVersion,
        deviceModel: _deviceModel!.deviceModel,
        capabilities: _deviceModel!.capabilities,
      );

      final brainService = WBrainService(
        brainUrl: widget.brainUrl,
        deviceName: updatedDevice.deviceName,
      );

      print('[WRegister] Connecting to Brain...');
      await brainService.connect(updatedDevice);
      print('[WRegister] ✅ Brain accepted registration');

      // CRITICAL: Save to SharedPreferences BEFORE navigating
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_name', updatedDevice.deviceName);
      await prefs.setString('brain_url', widget.brainUrl);
      print('[WRegister] ✅ SharedPreferences updated');

      if (mounted) {
        print('[WRegister] Navigating to Main Screen...');
        // Use a small delay to ensure navigation happens after state is stable
        await Future.delayed(const Duration(milliseconds: 100));
        Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
      }
    } catch (e) {
      print('[WRegister] Registration failed: $e');
      setState(() {
        _errorMessage = 'Registration failed: $e';
        _isRegistering = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_deviceModel == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Register Device'), backgroundColor: Colors.amber),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Device Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            _infoRow('Model', _deviceModel!.deviceModel),
            _infoRow('OS', _deviceModel!.osVersion),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isRegistering ? null : _registerDevice,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                child: _isRegistering ? const CircularProgressIndicator() : const Text('Register & Start Monitoring'),
              ),
            ),
            if (_errorMessage != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))],
      ),
    );
  }
}
