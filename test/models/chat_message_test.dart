import 'package:flutter_test/flutter_test.dart';
import 'package:worker/models/chat_message.dart';

void main() {
  group('WChatMessage', () {
    test('creates with defaults', () {
      final msg = WChatMessage(
        id: '1',
        sender: 'User1',
        text: 'Hello',
      );

      expect(msg.sender, 'User1');
      expect(msg.text, 'Hello');
      expect(msg.signalStrength, 100);
      expect(msg.transportType, 'http');
      expect(msg.isSynced, false);
      expect(msg.isVoiceMessage, false);
    });

    test('isVoiceMessage is true with audioPath', () {
      final msg = WChatMessage(
        id: '1',
        sender: 'User1',
        text: 'Voice',
        audioPath: '/tmp/audio.m4a',
      );

      expect(msg.isVoiceMessage, true);
    });

    test('signalColor returns correct indicator', () {
      expect(
          WChatMessage(id: '1', sender: 's', text: 't', signalStrength: 90)
              .signalColor,
          contains('🟢'));
      expect(
          WChatMessage(id: '1', sender: 's', text: 't', signalStrength: 60)
              .signalColor,
          contains('🟡'));
      expect(
          WChatMessage(id: '1', sender: 's', text: 't', signalStrength: 30)
              .signalColor,
          contains('🟠'));
      expect(
          WChatMessage(id: '1', sender: 's', text: 't', signalStrength: 10)
              .signalColor,
          contains('🔴'));
    });

    test('transportIcon returns correct icon', () {
      expect(
          WChatMessage(
                  id: '1',
                  sender: 's',
                  text: 't',
                  transportType: 'bluetooth')
              .transportIcon,
          '📡');
      expect(
          WChatMessage(
                  id: '1', sender: 's', text: 't', transportType: 'http')
              .transportIcon,
          '☁️');
      expect(
          WChatMessage(
                  id: '1', sender: 's', text: 't', transportType: 'local')
              .transportIcon,
          '💾');
    });

    test('toJson produces correct map', () {
      final msg = WChatMessage(
        id: 'test_1',
        sender: 'User1',
        text: 'Hello World',
        signalStrength: 75,
        transportType: 'bluetooth',
        isSynced: true,
      );

      final json = msg.toJson();
      expect(json['id'], 'test_1');
      expect(json['sender'], 'User1');
      expect(json['text'], 'Hello World');
      expect(json['signal_strength'], 75);
      expect(json['transport_type'], 'bluetooth');
      expect(json['is_synced'], true);
    });

    test('fromJson creates correct message', () {
      final json = {
        'id': 'test_2',
        'sender': 'User2',
        'text': 'From JSON',
        'signal_strength': 50,
        'transport_type': 'local',
        'is_synced': false,
        'timestamp': '2024-01-15T10:30:00.000',
      };

      final msg = WChatMessage.fromJson(json);
      expect(msg.id, 'test_2');
      expect(msg.sender, 'User2');
      expect(msg.text, 'From JSON');
      expect(msg.signalStrength, 50);
      expect(msg.transportType, 'local');
    });

    test('toJson/fromJson roundtrip', () {
      final original = WChatMessage(
        id: 'rt_1',
        sender: 'RoundTrip',
        text: 'Test roundtrip',
        signalStrength: 88,
        transportType: 'bluetooth',
        isSynced: true,
        audioPath: '/tmp/audio.m4a',
      );

      final restored = WChatMessage.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.sender, original.sender);
      expect(restored.text, original.text);
      expect(restored.signalStrength, original.signalStrength);
      expect(restored.transportType, original.transportType);
      expect(restored.isSynced, original.isSynced);
      expect(restored.audioPath, original.audioPath);
    });

    test('formattedTime and shortTime work', () {
      final msg = WChatMessage(
        id: '1',
        sender: 'User',
        text: 'Test',
        timestamp: DateTime(2024, 1, 15, 14, 30, 45),
      );

      expect(msg.formattedTime, '14:30:45');
      expect(msg.shortTime, '14:30');
    });

    test('toString contains key info', () {
      final msg = WChatMessage(
        id: '1',
        sender: 'TestUser',
        text: 'Hello',
      );

      final str = msg.toString();
      expect(str, contains('TestUser'));
      expect(str, contains('Hello'));
    });
  });
}
