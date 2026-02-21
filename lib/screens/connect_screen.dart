import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:worker/services/brain_service.dart';
import 'package:worker/services/ble_mesh_service.dart';

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
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              // Mesh relay option for children without WiFi to Brain
              const Text(
                'No WiFi to Brain?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Connect through nearby children using BLE mesh.\n'
                'Chat messages relay through other devices to reach Brain.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Consumer<WBleMeshService>(
                builder: (context, mesh, _) {
                  final peers = mesh.discoveredPeers;
                  return Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _isConnecting
                              ? null
                              : () async {
                                  setState(() => _isConnecting = true);
                                  await mesh.startScanning();
                                  setState(() => _isConnecting = false);
                                },
                          icon: const Icon(Icons.bluetooth_searching),
                          label: Text(
                            mesh.isScanning
                                ? 'Scanning...'
                                : 'Scan for Nearby Kids (${peers.length} found)',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue,
                            side: const BorderSide(color: Colors.blue),
                          ),
                        ),
                      ),
                      if (peers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...peers.take(5).map((peer) => ListTile(
                              dense: true,
                              leading: Icon(
                                peer.isBridge ? Icons.wifi : Icons.bluetooth,
                                color: peer.isBridge ? Colors.green : Colors.blue,
                                size: 20,
                              ),
                              title: Text(peer.deviceName, style: const TextStyle(fontSize: 13)),
                              subtitle: Text(
                                '${peer.signalBars} ${peer.signalPercent}% • '
                                '${peer.hopsToBrain < 99 ? "${peer.hopsToBrain} hops to Brain" : "searching..."}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: TextButton(
                                onPressed: () async {
                                  final connected = await mesh.connectToPeer(peer.deviceId);
                                  if (connected && mounted) {
                                    // Save as mesh-only device and proceed to register
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setString('brain_url', '');
                                    await prefs.setBool('mesh_only', true);
                                    if (mounted) {
                                      Navigator.of(context).pushReplacementNamed(
                                        '/register',
                                        arguments: {'brainUrl': '', 'meshOnly': true},
                                      );
                                    }
                                  }
                                },
                                child: const Text('Join', style: TextStyle(fontSize: 12)),
                              ),
                            )),
                      ],
                    ],
                  );
                },
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
