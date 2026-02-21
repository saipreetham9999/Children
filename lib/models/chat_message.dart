import 'package:intl/intl.dart';

/// WChatMessage — Runtime chat message model (no persistence)
class WChatMessage {
  final String id;
  final String sender;
  final String text;
  final DateTime timestamp;
  final String? audioPath;  // Path to voice message if available
  final int signalStrength;  // 0-100 (Bluetooth RSSI or HTTP latency)
  final String transportType;  // 'bluetooth', 'http', 'local'
  final bool isSynced;  // Whether sent to Brain

  WChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    DateTime? timestamp,
    this.audioPath,
    this.signalStrength = 100,
    this.transportType = 'http',
    this.isSynced = false,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Get formatted time (HH:mm:ss)
  String get formattedTime {
    return DateFormat('HH:mm:ss').format(timestamp);
  }

  /// Get formatted short time (HH:mm)
  String get shortTime {
    return DateFormat('HH:mm').format(timestamp);
  }

  /// Is voice message
  bool get isVoiceMessage => audioPath != null && audioPath!.isNotEmpty;

  /// Get signal indicator color
  String get signalColor {
    if (signalStrength >= 80) return '🟢';  // Strong
    if (signalStrength >= 50) return '🟡';  // Medium
    if (signalStrength >= 20) return '🟠';  // Weak
    return '🔴';  // Very weak
  }

  /// Get transport icon
  String get transportIcon {
    switch (transportType) {
      case 'bluetooth':
        return '📡';
      case 'mesh':
        return '🔗';
      case 'http':
        return '☁️';
      case 'local':
        return '💾';
      default:
        return '?';
    }
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'sender': sender,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        'audio_path': audioPath,
        'signal_strength': signalStrength,
        'transport_type': transportType,
        'is_synced': isSynced,
      };

  /// Create from JSON
  factory WChatMessage.fromJson(Map<String, dynamic> json) {
    return WChatMessage(
      id: json['id'] ?? '',
      sender: json['sender'] ?? 'Unknown',
      text: json['text'] ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : null,
      audioPath: json['audio_path'],
      signalStrength: json['signal_strength'] ?? 100,
      transportType: json['transport_type'] ?? 'http',
      isSynced: json['is_synced'] ?? false,
    );
  }

  @override
  String toString() =>
      'Message($sender @ $formattedTime: "$text" $signalColor $transportIcon)';
}
