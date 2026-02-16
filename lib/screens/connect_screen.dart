import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/brain_service.dart';

/// WConnectScreen — Phase MVP: IP entry and connect
class WConnectScreen extends StatefulWidget {
  const WConnectScreen({Key? key}) : super(key: key);

  @override
  State<WConnectScreen> createState() => _WConnectScreenState();
}

class _WConnectScreenState extends State<WConnectScreen> {
  final _ipController = TextEditingController();
  bool _isConnecting = false;
  String? _errorMessage;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _checkAndLoad();
  }

  Future<void> _checkAndLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIP = prefs.getString('brain_url') ?? '';
    final deviceName = prefs.getString('device_name') ?? '';

    if (!mounted) return;

    // If already registered, skip straight to main
    if (savedIP.isNotEmpty && deviceName.isNotEmpty) {
      print('[ConnectScreen] Already registered as "$deviceName", navigating to /main');
      Navigator.of(context).pushReplacementNamed('/main');
      return;
    }

    _ipController.text = savedIP;
  }

  Future<void> _checkBrainStatus() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
      _statusMessage = null;
    });

    try {
      final brainUrl = _ipController.text.trim();
      if (brainUrl.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter Brain IP address';
          _isConnecting = false;
        });
        return;
      }

      // Format URL properly
      String url = brainUrl;
      if (!url.startsWith('http')) {
        url = 'http://$url';
      }
      if (!url.contains(':')) {
        url = '$url:8080';
      }

      final brainService = WBrainService(brainUrl: url, deviceName: 'test');
      final status = await brainService.getStatus();

      setState(() {
        _statusMessage = 'Brain Online ✓';
        _errorMessage = null;
      });

      // Save IP
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('brain_url', url);

      // Navigate to register
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(
          '/register',
          arguments: {'brainUrl': url},
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection failed: $e';
        _statusMessage = null;
        _isConnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Worker — Connect'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Large W logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.deepPurple,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    'W',
                    style: Theme.of(context).textTheme.headlineLarge!.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Worker',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Motion Detection Transmitter',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: Colors.grey,
                    ),
              ),
              const SizedBox(height: 48),
              // IP Input
              TextField(
                controller: _ipController,
                decoration: InputDecoration(
                  labelText: 'Brain IP Address',
                  hintText: '192.168.1.100 or 192.168.1.100:8080',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.router),
                ),
                enabled: !_isConnecting,
              ),
              const SizedBox(height: 24),
              // Connect Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isConnecting ? null : _checkBrainStatus,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                  ),
                  child: _isConnecting
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
                          'Check & Connect',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              // If connection fails, offer shortcut to go directly to main
              if (_errorMessage != null)
                TextButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final savedUrl = _ipController.text.trim();
                    if (savedUrl.isNotEmpty) {
                      await prefs.setString('brain_url', savedUrl.startsWith('http') ? savedUrl : 'http://$savedUrl:8080');
                    }
                    if (mounted) Navigator.of(context).pushReplacementNamed('/register',
                        arguments: {'brainUrl': prefs.getString('brain_url') ?? savedUrl});
                  },
                  child: const Text('Brain offline? Register anyway →', style: TextStyle(color: Colors.deepPurple)),
                ),
              // Status messages
              if (_statusMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    border: Border.all(color: Colors.green),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: const TextStyle(color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_errorMessage != null)
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
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }
}
