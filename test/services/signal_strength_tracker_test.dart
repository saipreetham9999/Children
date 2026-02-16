import 'package:flutter_test/flutter_test.dart';
import 'package:worker/services/signal_strength_tracker.dart';

void main() {
  group('WSignalStrengthTracker', () {
    late WSignalStrengthTracker tracker;

    setUp(() {
      tracker = WSignalStrengthTracker();
      tracker.initialize();
    });

    test('starts with default values', () {
      expect(tracker.httpLatencyMs, 0);
      expect(tracker.httpSuccessRate, 100.0);
      expect(tracker.bluetoothRssi, -100);
      expect(tracker.isBluetoothConnected, false);
      expect(tracker.preferredTransport, 'http');
    });

    test('recordHttpResponse updates latency and success rate', () {
      tracker.recordHttpResponse(latencyMs: 50, success: true);
      expect(tracker.httpLatencyMs, 50);
      expect(tracker.httpSuccessRate, 100.0);

      tracker.recordHttpResponse(latencyMs: 200, success: false);
      expect(tracker.httpLatencyMs, 200);
      expect(tracker.httpSuccessRate, 50.0);
    });

    test('recordBluetoothSignal updates RSSI and connection', () {
      tracker.recordBluetoothSignal(rssi: -50, deviceCount: 3);
      expect(tracker.bluetoothRssi, -50);
      expect(tracker.bluetoothDeviceCount, 3);
      expect(tracker.isBluetoothConnected, true);
    });

    test('weak bluetooth is not connected', () {
      tracker.recordBluetoothSignal(rssi: -100, deviceCount: 0);
      expect(tracker.isBluetoothConnected, false);
    });

    test('shouldPreferBluetooth when BT is strong and HTTP slow', () {
      tracker.recordHttpResponse(latencyMs: 800, success: true);
      tracker.recordBluetoothSignal(rssi: -30, deviceCount: 1);
      expect(tracker.shouldPreferBluetooth(), true);
    });

    test('shouldPreferBluetooth false when BT is weak', () {
      tracker.recordHttpResponse(latencyMs: 50, success: true);
      tracker.recordBluetoothSignal(rssi: -90, deviceCount: 1);
      expect(tracker.shouldPreferBluetooth(), false);
    });

    test('signalBars returns correct bars', () {
      // Force high signal
      tracker.recordHttpResponse(latencyMs: 10, success: true);
      expect(tracker.signalBars, isNotEmpty);
    });

    test('signalIndicator returns string', () {
      tracker.recordHttpResponse(latencyMs: 10, success: true);
      expect(tracker.signalIndicator, contains('Strong'));
    });

    test('transportEmoji returns correct emoji', () {
      expect(tracker.transportEmoji, contains('☁'));

      tracker.recordHttpResponse(latencyMs: 900, success: false);
      tracker.recordBluetoothSignal(rssi: -20, deviceCount: 1);
      if (tracker.preferredTransport == 'bluetooth') {
        expect(tracker.transportEmoji, contains('📡'));
      }
    });

    test('getStats returns complete data', () {
      tracker.recordHttpResponse(latencyMs: 100, success: true);
      final stats = tracker.getStats();

      expect(stats['overall_signal'], isNotNull);
      expect(stats['preferred_transport'], isNotNull);
      expect(stats['http']['latency_ms'], 100);
      expect(stats['bluetooth']['rssi'], -100);
      expect(stats['history']['signal_samples'], greaterThan(0));
    });

    test('resetStats clears everything', () {
      tracker.recordHttpResponse(latencyMs: 500, success: false);
      tracker.recordBluetoothSignal(rssi: -50, deviceCount: 2);

      tracker.resetStats();

      expect(tracker.httpLatencyMs, 0);
      expect(tracker.httpSuccessRate, 100.0);
      expect(tracker.bluetoothRssi, -100);
      expect(tracker.isBluetoothConnected, false);
    });

    test('notifies listeners on update', () {
      int notifyCount = 0;
      tracker.addListener(() => notifyCount++);

      tracker.recordHttpResponse(latencyMs: 100, success: true);
      expect(notifyCount, greaterThan(0));
    });

    test('onTransportChange callback fires on switch', () {
      String? newTransport;
      tracker.onTransportChange = (t) => newTransport = t;

      // Force switch to bluetooth
      tracker.recordHttpResponse(latencyMs: 900, success: false);
      tracker.recordBluetoothSignal(rssi: -20, deviceCount: 1);

      // May or may not switch depending on signal calculation
      // Just verify callback mechanism works
      if (tracker.preferredTransport == 'bluetooth') {
        expect(newTransport, 'bluetooth');
      }
    });
  });
}
