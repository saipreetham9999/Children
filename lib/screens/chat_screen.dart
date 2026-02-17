import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_service.dart';
import '../services/voice_service.dart';
import '../services/signal_strength_tracker.dart';
import '../models/chat_message.dart';

/// WChatScreen — Runtime group chat with signal strength
class WChatScreen extends StatefulWidget {
  const WChatScreen({Key? key}) : super(key: key);

  @override
  State<WChatScreen> createState() => _WChatScreenState();
}

class _WChatScreenState extends State<WChatScreen> {
  final _messageController = TextEditingController();
  late WVoiceService _voiceService;
  bool _isVoiceMode = false;
  bool _isListening = false;


  @override
  void initState() {
    super.initState();
    _voiceService = WVoiceService();

    // New callback signature: (recognizedText, audioBytes)
    _voiceService.onSpeechResult = (recognizedText, audioBytes) {
      print('[ChatScreen] Voice result: $recognizedText');
      _messageController.text = recognizedText;
      setState(() => _isListening = false);
    };
  }


  @override
  void dispose() {
    _messageController.dispose();
    if (_isListening) {
      _voiceService.stopListening();
    }
    _voiceService.dispose();
    super.dispose();
  }

  void _onVoiceResult(String text) {
    print('[ChatScreen] Voice result: $text');
    _messageController.text = text;
    setState(() => _isListening = false);
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

  Future<void> _startVoiceInput() async {
    if (_isListening) {
      await _voiceService.stopListening();
      setState(() => _isListening = false);
    } else {
      try {
        await _voiceService.initialize();  // Initialize before listening
        setState(() => _isListening = true);
        await _voiceService.startListening(
          timeout: const Duration(seconds: 10),
        );
      } catch (e) {
        print('[ChatScreen] Voice error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voice failed: $e')),
        );
        setState(() => _isListening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    Text(
                      signal.signalBars,
                      style: TextStyle(fontSize: 12),
                    ),
                    Text(
                      signal.transportEmoji,
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Signal strength bar
          Consumer<WSignalStrengthTracker>(
            builder: (context, signal, _) {
              return Container(
                color: _getSignalColor(signal.overallSignal),
                padding: EdgeInsets.all(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      signal.signalIndicator,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${signal.overallSignal}% • ${signal.preferredTransport.toUpperCase()}',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Text(
                      '${signal.httpLatencyMs}ms',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          ),
          // Messages list
          Expanded(
            child: Consumer<WChatService>(
              builder: (context, chatService, _) {
                final messages = chatService.messages;
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet\nStart a conversation!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
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
                        margin: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isOwn
                              ? Colors.blue.withOpacity(0.7)
                              : Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        constraints:
                            BoxConstraints(maxWidth: 250),
                        child: Column(
                          crossAxisAlignment: isOwn
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            // Sender + signal
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isOwn)
                                  Text(
                                    message.sender,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                SizedBox(width: 8),
                                Text(
                                  message.signalColor,
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            // Message text or voice icon
                            if (message.isVoiceMessage)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.mic,
                                      size: 16,
                                      color: isOwn
                                          ? Colors.white
                                          : Colors.black87),
                                  SizedBox(width: 8),
                                  Text(
                                    message.text,
                                    style: TextStyle(
                                      color: isOwn
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                message.text,
                                style: TextStyle(
                                  color: isOwn ? Colors.white : Colors.black87,
                                ),
                              ),
                            SizedBox(height: 4),
                            // Time + transport + synced status
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  message.shortTime,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isOwn
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  message.transportIcon,
                                  style: TextStyle(fontSize: 10),
                                ),
                                if (isOwn && !message.isSynced)
                                  Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Icon(
                                      Icons.schedule,
                                      size: 10,
                                      color: Colors.white70,
                                    ),
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
            ),
          ),
          // Input area
          Divider(height: 1),
          Container(
            padding: EdgeInsets.all(12),
            color: Colors.grey[100],
            child: Row(
              children: [
                // Text input
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText:
                          _isListening ? 'Listening...' : 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      prefixIcon: _isListening
                          ? Icon(Icons.mic, color: Colors.red)
                          : null,
                    ),
                    enabled: !_isListening,
                  ),
                ),
                SizedBox(width: 8),
                // Voice button
                FloatingActionButton(
                  onPressed: _startVoiceInput,
                  mini: true,
                  backgroundColor:
                      _isListening ? Colors.red : Colors.blue,
                  child: Icon(
                    _isListening ? Icons.stop : Icons.mic,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 8),
                // Send button
                FloatingActionButton(
                  onPressed: _messageController.text.isEmpty
                      ? null
                      : _sendMessage,
                  mini: true,
                  backgroundColor:
                      _messageController.text.isEmpty
                          ? Colors.grey
                          : Colors.green,
                  child: Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
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
