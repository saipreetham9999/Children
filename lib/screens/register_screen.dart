import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_model.dart';
import '../services/brain_service.dart';
import 'dart:io';

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
      String defaultName = 'Worker Device';

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceType = 'android';
        osVersion = 'Android ${androidInfo.version.release}';
        deviceModel = androidInfo.model;
        defaultName = androidInfo.model;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceType = 'ios';
        osVersion = 'iOS ${iosInfo.systemVersion}';
        deviceModel = iosInfo.utsname.machine;
        defaultName = deviceModel;
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
      print('[WRegister] Device detect error: $e');
      setState(() {
        _deviceModel = WDeviceModel(
          deviceName: 'Worker',
          deviceType: 'unknown',
          osVersion: 'unknown',
          deviceModel: 'unknown',
        );
      });
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

      // Perform /api/connect
      await brainService.connect(updatedDevice);

      // Save to device
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_name', updatedDevice.deviceName);
      await prefs.setString('device_type', updatedDevice.deviceType);
      await prefs.setString('brain_url', widget.brainUrl);

      if (mounted) {
        // Navigate directly to main, skipping transition if it was causing issues
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
    if (_deviceModel == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Node'),
        backgroundColor: Colors.amber,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.security, size: 64, color: Colors.amber),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Enter Device ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            _infoCard('Device Type', _deviceModel!.deviceType),
            _infoCard('Device Model', _deviceModel!.deviceModel),
            _infoCard('OS Version', _deviceModel!.osVersion),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isRegistering ? null : _registerDevice,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                child: _isRegistering 
                  ? const CircularProgressIndicator(color: Colors.black) 
                  : const Text('REGISTER & START'),
              ),
            ),
            if (_errorMessage != null) 
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
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
