import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';

/// WChatService — Runtime group chat (no database, memory only)
/// Messages persist only during app session
class WChatService extends ChangeNotifier {
  static const int maxMessages = 200;  // Keep last 200 messages in memory
  static const int maxBroadcastHistory = 500;  // Track sent for sync

  final List<WChatMessage> _messages = [];
  final Set<String> _sentMessageIds = {};  // Track what we've sent to Brain
  Timer? _syncTimer;

  // Callbacks
  Function(WChatMessage)? onNewMessage;
  Function(String)? onNewVoiceMessage;

  /// Get all messages (newest first)
  List<WChatMessage> get messages => _messages;

  /// Get unsynced messages
  List<WChatMessage> get unsyncedMessages =>
      _messages.where((m) => !m.isSynced).toList();

  /// Total message count
  int get messageCount => _messages.length;

  /// Initialize chat service
  Future<void> initialize() async {
    print('[ChatService] Initializing...');
    // Start sync timer (attempt to sync every 10 seconds)
    _syncTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _attemptSync(),
    );
    print('[ChatService] ✅ Initialized with sync timer');
  }

  /// Add message to chat (local)
  void addMessage(WChatMessage message) {
    print('[ChatService] Adding message: ${message.sender} - "${message.text}"');

    // Keep last 200 messages
    _messages.insert(0, message);
    if (_messages.length > maxMessages) {
      _messages.removeRange(maxMessages, _messages.length);
    }

    notifyListeners();
    onNewMessage?.call(message);
  }

  /// Send message (local + queue for Brain)
  Future<WChatMessage> sendMessage(
    String sender,
    String text, {
    String? audioPath,
    String transportType = 'http',
    int signalStrength = 100,
  }) async {
    print('[ChatService] Sending message from $sender: "$text"');

    final message = WChatMessage(
      id: _generateId(),
      sender: sender,
      text: text,
      audioPath: audioPath,
      signalStrength: signalStrength,
      transportType: transportType,
      isSynced: false,  // Mark as not synced initially
    );

    addMessage(message);
    return message;
  }

  /// Mark message as synced (sent to Brain)
  void markSynced(String messageId) {
    final index =
        _messages.indexWhere((m) => m.id == messageId);
    if (index >= 0) {
      final original = _messages[index];
      _messages[index] = WChatMessage(
        id: original.id,
        sender: original.sender,
        text: original.text,
        timestamp: original.timestamp,
        audioPath: original.audioPath,
        signalStrength: original.signalStrength,
        transportType: original.transportType,
        isSynced: true,  // Mark as synced
      );
      notifyListeners();
    }
    _sentMessageIds.add(messageId);
  }

  /// Get messages since timestamp (for Brain polling)
  List<WChatMessage> getMessagesSince(DateTime timestamp) {
    return _messages
        .where((m) => m.timestamp.isAfter(timestamp))
        .toList();
  }

  /// Get signal strength (average from recent messages)
  int getAverageSignalStrength() {
    if (_messages.isEmpty) return 100;
    final recent = _messages.take(10).toList();
    final sum =
        recent.fold<int>(0, (sum, m) => sum + m.signalStrength);
    return (sum / recent.length).round();
  }

  /// Get transport type distribution
  Map<String, int> getTransportDistribution() {
    final distribution = <String, int>{};
    for (var msg in _messages) {
      distribution[msg.transportType] =
          (distribution[msg.transportType] ?? 0) + 1;
    }
    return distribution;
  }

  /// Clear all messages (reset chat)
  void clearMessages() {
    print('[ChatService] Clearing all messages');
    _messages.clear();
    notifyListeners();
  }

  /// Cleanup
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  // Private methods

  /// Generate unique message ID
  String _generateId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${_messages.length}';
  }

  /// Attempt to sync unsynced messages (called by timer)
  Future<void> _attemptSync() async {
    final unsynced = unsyncedMessages;
    if (unsynced.isEmpty) return;

    print('[ChatService] Syncing ${unsynced.length} unsynced messages...');
    // Sync logic will be handled by brain_service integration
    // This just marks them as ready for sync
  }

  /// Get chat statistics
  Map<String, dynamic> getStats() {
    return {
      'total_messages': messageCount,
      'unsynced_count': unsyncedMessages.length,
      'avg_signal_strength': getAverageSignalStrength(),
      'transport_distribution': getTransportDistribution(),
      'senders': _messages.map((m) => m.sender).toSet().length,
    };
  }
}
