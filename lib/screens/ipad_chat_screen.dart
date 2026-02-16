import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_service.dart';
import '../services/signal_strength_tracker.dart';
import '../services/speaker_controller.dart';
import '../models/chat_message.dart';

/// WiPadChatScreen — iPad-optimized chat screen
/// Uses wider layout and larger controls for tablet
class WiPadChatScreen extends StatefulWidget {
  const WiPadChatScreen({Key? key}) : super(key: key);

  @override
  State<WiPadChatScreen> createState() => _WiPadChatScreenState();
}

class _WiPadChatScreenState extends State<WiPadChatScreen> {
  final _messageController = TextEditingController();
  bool _isWideLayout = false;

  @override
  void initState() {
    super.initState();
    // Check orientation
    _updateLayout();
  }

  void _updateLayout() {
    final mediaQuery = MediaQuery.of(context);
    _isWideLayout = mediaQuery.size.width > 800;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateLayout();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final chatService = context.read<WChatService>();
    final signalTracker = context.read<WSignalStrengthTracker>();

    await chatService.sendMessage(
      'You',
      text,
      transportType: signalTracker.preferredTransport,
      signalStrength: signalTracker.overallSignal,
    );

    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        return _isWideLayout
            ? _buildLandscapeLayout()
            : _buildPortraitLayout();
      },
    );
  }

  // Portrait layout (standard chat)
  Widget _buildPortraitLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Chat'),
        elevation: 0,
        actions: [
          Consumer<WSignalStrengthTracker>(
            builder: (context, signal, _) {
              return Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(signal.signalBars,
                        style: TextStyle(fontSize: 12)),
                    Text(signal.transportEmoji,
                        style: TextStyle(fontSize: 16)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSignalBar(),
          Expanded(child: _buildMessagesList()),
          _buildInputArea(),
        ],
      ),
    );
  }

  // Landscape layout (split view for iPad)
  Widget _buildLandscapeLayout() {
    return Scaffold(
      body: Row(
        children: [
          // Left: Messages list (larger on iPad)
          Expanded(
            flex: 2,
            child: Column(
              children: [
                AppBar(
                  title: const Text('ShaRogai Group Chat'),
                  elevation: 0,
                ),
                _buildSignalBar(),
                Expanded(child: _buildMessagesList()),
              ],
            ),
          ),
          // Right: Controls and info panel
          Expanded(
            flex: 1,
            child: Column(
              children: [
                AppBar(
                  title: const Text('Controls'),
                  elevation: 0,
                  automaticallyImplyLeading: false,
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.all(16),
                    children: [
                      _buildSignalInfo(),
                      SizedBox(height: 16),
                      _buildVolumeControl(),
                      SizedBox(height: 16),
                      _buildChatStats(),
                    ],
                  ),
                ),
                Divider(height: 1),
                _buildInputArea(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalBar() {
    return Consumer<WSignalStrengthTracker>(
      builder: (context, signal, _) {
        return Container(
          color: _getSignalColor(signal.overallSignal),
          padding: EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(
                signal.signalIndicator,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                '${signal.overallSignal}% • ${signal.preferredTransport.toUpperCase()}',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              Text(
                '${signal.httpLatencyMs}ms',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              Text(
                'RSSI: ${signal.bluetoothRssi}',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessagesList() {
    return Consumer<WChatService>(
      builder: (context, chatService, _) {
        final messages = chatService.messages;
        if (messages.isEmpty) {
          return Center(
            child: Text(
              'No messages yet\nStart a conversation!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 18),
            ),
          );
        }

        return ListView.builder(
          reverse: true,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final isOwn = message.sender == 'You';

            return Align(
              alignment:
                  isOwn ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isOwn
                      ? Colors.blue.withOpacity(0.7)
                      : Colors.grey[300],
                  borderRadius: BorderRadius.circular(14),
                ),
                constraints: BoxConstraints(
                  maxWidth: _isWideLayout ? 400 : 250,
                ),
                child: Column(
                  crossAxisAlignment: isOwn
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (!isOwn)
                      Text(
                        message.sender,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    SizedBox(height: 4),
                    Text(
                      message.text,
                      style: TextStyle(
                        color: isOwn ? Colors.white : Colors.black87,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.shortTime,
                          style: TextStyle(
                            fontSize: 11,
                            color: isOwn
                                ? Colors.white70
                                : Colors.black54,
                          ),
                        ),
                        SizedBox(width: 6),
                        Text(
                          message.transportIcon,
                          style: TextStyle(fontSize: 12),
                        ),
                        SizedBox(width: 4),
                        Text(
                          message.signalColor,
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSignalInfo() {
    return Consumer<WSignalStrengthTracker>(
      builder: (context, signal, _) {
        return Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Signal Quality',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 12),
                LinearProgressIndicator(
                  value: signal.overallSignal / 100,
                  minHeight: 8,
                ),
                SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Overall: ${signal.overallSignal}%'),
                    Text(signal.signalBars),
                  ],
                ),
                SizedBox(height: 12),
                Text('HTTP: ${signal.httpLatencyMs}ms',
                    style: TextStyle(fontSize: 13)),
                Text(
                    'Success: ${signal.httpSuccessRate.toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 13)),
                SizedBox(height: 8),
                Text('Bluetooth RSSI: ${signal.bluetoothRssi}',
                    style: TextStyle(fontSize: 13)),
                Text(
                    'Connected: ${signal.isBluetoothConnected ? "Yes" : "No"}',
                    style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVolumeControl() {
    return Consumer<WSpeakerController>(
      builder: (context, controller, _) {
        return Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Speaker Control',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      controller.volumeIndicator,
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Slider(
                  value: controller.currentVolume.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${controller.currentVolume}%',
                  onChanged: (value) {
                    controller.setVolume(value.toInt());
                  },
                ),
                SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () =>
                          controller.setSpeakerMode('speaker'),
                      icon: Icon(Icons.volume_up),
                      label: Text('Speaker'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () =>
                          controller.setSpeakerMode('bluetooth'),
                      icon: Icon(Icons.bluetooth),
                      label: Text('Bluetooth'),
                    ),
                    ElevatedButton.icon(
                      onPressed: controller.isMuted
                          ? controller.unmute
                          : controller.mute,
                      icon: Icon(controller.isMuted
                          ? Icons.volume_off
                          : Icons.volume_mute),
                      label: Text(controller.isMuted
                          ? 'Unmute'
                          : 'Mute'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatStats() {
    return Consumer<WChatService>(
      builder: (context, chatService, _) {
        final stats = chatService.getStats();
        return Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chat Statistics',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 12),
                Text('Total Messages: ${stats['total_messages']}',
                    style: TextStyle(fontSize: 13)),
                Text('Unsynced: ${stats['unsynced_count']}',
                    style: TextStyle(fontSize: 13, color: Colors.orange)),
                Text('Avg Signal: ${stats['avg_signal_strength']}%',
                    style: TextStyle(fontSize: 13)),
                Text('Contributors: ${stats['senders']}',
                    style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.all(12),
      color: Colors.grey[100],
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              maxLines: null,
            ),
          ),
          SizedBox(width: 8),
          FloatingActionButton(
            onPressed: _messageController.text.isEmpty
                ? null
                : _sendMessage,
            backgroundColor: _messageController.text.isEmpty
                ? Colors.grey
                : Colors.green,
            child: Icon(Icons.send, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Color _getSignalColor(int signal) {
    if (signal >= 80) return Colors.green;
    if (signal >= 50) return Colors.orange;
    if (signal >= 20) return Colors.deepOrange;
    return Colors.red;
  }
}
