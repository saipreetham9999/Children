import 'package:flutter_test/flutter_test.dart';
import 'package:worker/services/chat_service.dart';
import 'package:worker/models/chat_message.dart';

void main() {
  group('WChatService', () {
    late WChatService chatService;

    setUp(() {
      chatService = WChatService();
    });

    test('starts with empty messages', () {
      expect(chatService.messages, isEmpty);
      expect(chatService.messageCount, 0);
    });

    test('addMessage adds to front of list', () {
      final msg = WChatMessage(
        id: '1',
        sender: 'TestUser',
        text: 'Hello',
      );
      chatService.addMessage(msg);

      expect(chatService.messageCount, 1);
      expect(chatService.messages.first.text, 'Hello');
    });

    test('sendMessage creates message with correct fields', () async {
      final msg = await chatService.sendMessage(
        'User1',
        'Test message',
        transportType: 'bluetooth',
        signalStrength: 75,
      );

      expect(msg.sender, 'User1');
      expect(msg.text, 'Test message');
      expect(msg.transportType, 'bluetooth');
      expect(msg.signalStrength, 75);
      expect(msg.isSynced, false);
    });

    test('markSynced updates message sync status', () async {
      final msg = await chatService.sendMessage('User1', 'Test');
      expect(chatService.messages.first.isSynced, false);

      chatService.markSynced(msg.id);
      expect(chatService.messages.first.isSynced, true);
    });

    test('respects maxMessages limit', () {
      for (int i = 0; i < 210; i++) {
        chatService.addMessage(WChatMessage(
          id: 'msg_$i',
          sender: 'User',
          text: 'Message $i',
        ));
      }

      expect(chatService.messageCount, 200);
    });

    test('clearMessages empties the list', () async {
      await chatService.sendMessage('User1', 'Test');
      await chatService.sendMessage('User2', 'Test2');
      expect(chatService.messageCount, 2);

      chatService.clearMessages();
      expect(chatService.messageCount, 0);
    });

    test('getAverageSignalStrength computes correctly', () async {
      await chatService.sendMessage('U', 'A', signalStrength: 80);
      await chatService.sendMessage('U', 'B', signalStrength: 60);

      expect(chatService.getAverageSignalStrength(), 70);
    });

    test('getTransportDistribution counts correctly', () async {
      await chatService.sendMessage('U', 'A', transportType: 'http');
      await chatService.sendMessage('U', 'B', transportType: 'http');
      await chatService.sendMessage('U', 'C', transportType: 'bluetooth');

      final dist = chatService.getTransportDistribution();
      expect(dist['http'], 2);
      expect(dist['bluetooth'], 1);
    });

    test('unsyncedMessages returns only unsynced', () async {
      final msg1 = await chatService.sendMessage('U', 'A');
      await chatService.sendMessage('U', 'B');

      chatService.markSynced(msg1.id);

      expect(chatService.unsyncedMessages.length, 1);
      expect(chatService.unsyncedMessages.first.text, 'B');
    });

    test('getStats returns complete statistics', () async {
      await chatService.sendMessage('U1', 'Hello');
      await chatService.sendMessage('U2', 'World');

      final stats = chatService.getStats();
      expect(stats['total_messages'], 2);
      expect(stats['senders'], 2);
    });

    test('getMessagesSince filters by timestamp', () async {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      await chatService.sendMessage('U', 'After');

      final msgs = chatService.getMessagesSince(before);
      expect(msgs.length, 1);
      expect(msgs.first.text, 'After');
    });
  });
}
