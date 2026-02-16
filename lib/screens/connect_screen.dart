import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worker/services/brain_service.dart';

class WConnectScreen extends StatefulWidget {
  const WConnectScreen({Key? key}) : super(key: key);

  @override
  State<WConnectScreen> createState() => _WConnectScreenState();
}

class _WConnectScreenState extends State<WConnectScreen> {
  final _ipController = TextEditingController();
  bool _isConnecting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedIP();
  }

  Future<void> _loadSavedIP() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIP = prefs.getString('brain_url') ?? '';
    if (mounted) {
      _ipController.text = savedIP.replaceFirst('http://', '').split(':')[0];
    }
  }

  Future<void> _handleConnect({bool skipStatusCheck = false}) async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      final input = _ipController.text.trim();
      if (input.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter Brain IP address';
          _isConnecting = false;
        });
        return;
      }

      // Format URL
      String url = input;
      if (!url.startsWith('http')) url = 'http://$url';
      if (!url.contains(':', 6)) url = '$url:8080';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('brain_url', url);

      if (!skipStatusCheck) {
        print('[Connect] Validating Brain at $url...');
        final brainService = WBrainService(brainUrl: url, deviceName: 'probe');
        await brainService.getStatus();
      }

      if (mounted) {
        Navigator.of(context).pushReplacementNamed(
          '/register',
          arguments: {'brainUrl': url},
        );
      }
    } catch (e) {
      print('[Connect] Connection failed: $e');
      setState(() {
        _errorMessage = 'Could not reach Brain. Is the server running?';
        _isConnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ShaRogai Link'), backgroundColor: Colors.deepPurple),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.router, size: 80, color: Colors.deepPurple),
              const SizedBox(height: 32),
              TextField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: 'iPad Brain IP',
                  hintText: '192.168.0.183',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                enabled: !_isConnecting,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isConnecting ? null : () => _handleConnect(),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                  child: _isConnecting 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : const Text('CONNECT & CHECK'),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                TextButton(
                  onPressed: () => _handleConnect(skipStatusCheck: true),
                  child: const Text('Skip Check & Register Anyway →', style: TextStyle(color: Colors.deepPurple)),
                ),
              ],
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
