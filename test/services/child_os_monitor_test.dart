import 'package:flutter_test/flutter_test.dart';
import 'package:worker/services/child_os_monitor.dart';

void main() {
  group('ChildDeviceInfo', () {
    test('creates with required fields', () {
      final info = ChildDeviceInfo(
        deviceName: 'KidPhone',
        osType: 'ios',
        osVersion: '17.0',
        model: 'iPhone 15',
        batteryLevel: 80,
      );

      expect(info.deviceName, 'KidPhone');
      expect(info.osType, 'ios');
      expect(info.batteryLevel, 80);
      expect(info.isOnline, true);
    });

    test('batteryIndicator returns correct levels', () {
      expect(
          ChildDeviceInfo(
            deviceName: 'a',
            osType: 'ios',
            osVersion: '',
            model: '',
            batteryLevel: 90,
          ).batteryIndicator,
          'Full');

      expect(
          ChildDeviceInfo(
            deviceName: 'a',
            osType: 'ios',
            osVersion: '',
            model: '',
            batteryLevel: 50,
          ).batteryIndicator,
          'Good');

      expect(
          ChildDeviceInfo(
            deviceName: 'a',
            osType: 'ios',
            osVersion: '',
            model: '',
            batteryLevel: 15,
          ).batteryIndicator,
          'Critical');
    });

    test('toJson/fromJson roundtrip', () {
      final original = ChildDeviceInfo(
        deviceName: 'Test',
        osType: 'android',
        osVersion: '14',
        model: 'Pixel 8',
        batteryLevel: 65,
        batteryState: 'charging',
        screenTimeUsedMinutes: 45,
        networkType: 'wifi',
        appUsage: {'com.app': 30},
      );

      final json = original.toJson();
      final restored = ChildDeviceInfo.fromJson(json);

      expect(restored.deviceName, 'Test');
      expect(restored.osType, 'android');
      expect(restored.batteryLevel, 65);
      expect(restored.batteryState, 'charging');
      expect(restored.screenTimeUsedMinutes, 45);
      expect(restored.appUsage['com.app'], 30);
    });
  });

  group('WChildOSMonitor', () {
    late WChildOSMonitor monitor;

    setUp(() {
      monitor = WChildOSMonitor();
    });

    tearDown(() {
      monitor.dispose();
    });

    test('starts with no children', () {
      expect(monitor.connectedChildCount, 0);
      expect(monitor.childDevices, isEmpty);
    });

    test('registerChildDevice adds device', () {
      monitor.registerChildDevice(ChildDeviceInfo(
        deviceName: 'KidPhone',
        osType: 'ios',
        osVersion: '17.0',
        model: 'iPhone 15',
        batteryLevel: 80,
      ));

      expect(monitor.connectedChildCount, 1);
      expect(monitor.childDevices.containsKey('KidPhone'), true);
    });

    test('removeChildDevice removes device', () {
      monitor.registerChildDevice(ChildDeviceInfo(
        deviceName: 'KidPhone',
        osType: 'ios',
        osVersion: '17.0',
        model: 'iPhone 15',
        batteryLevel: 80,
      ));

      monitor.removeChildDevice('KidPhone');
      expect(monitor.connectedChildCount, 0);
    });

    test('markChildOffline sets online to false', () {
      monitor.registerChildDevice(ChildDeviceInfo(
        deviceName: 'KidPhone',
        osType: 'ios',
        osVersion: '17.0',
        model: 'iPhone 15',
        batteryLevel: 80,
        isOnline: true,
      ));

      monitor.markChildOffline('KidPhone');
      expect(monitor.childDevices['KidPhone']!.isOnline, false);
    });

    test('onlineChildren filters correctly', () {
      monitor.registerChildDevice(ChildDeviceInfo(
        deviceName: 'Online1',
        osType: 'ios',
        osVersion: '17',
        model: 'iPhone',
        batteryLevel: 80,
        isOnline: true,
      ));
      monitor.registerChildDevice(ChildDeviceInfo(
        deviceName: 'Offline1',
        osType: 'android',
        osVersion: '14',
        model: 'Pixel',
        batteryLevel: 30,
        isOnline: false,
      ));

      expect(monitor.onlineChildren.length, 1);
      expect(monitor.offlineChildren.length, 1);
    });

    test('lowBatteryChildren filters at 20%', () {
      monitor.registerChildDevice(ChildDeviceInfo(
        deviceName: 'LowBat',
        osType: 'ios',
        osVersion: '17',
        model: 'iPhone',
        batteryLevel: 10,
      ));
      monitor.registerChildDevice(ChildDeviceInfo(
        deviceName: 'GoodBat',
        osType: 'ios',
        osVersion: '17',
        model: 'iPhone',
        batteryLevel: 80,
      ));

      expect(monitor.lowBatteryChildren.length, 1);
      expect(monitor.lowBatteryChildren.first.deviceName, 'LowBat');
    });

    test('childrenByScreenTime sorts descending', () {
      monitor.registerChildDevice(ChildDeviceInfo(
        deviceName: 'Low',
        osType: 'ios',
        osVersion: '17',
        model: 'iPhone',
        batteryLevel: 80,
        screenTimeUsedMinutes: 30,
      ));
      monitor.registerChildDevice(ChildDeviceInfo(
        deviceName: 'High',
        osType: 'ios',
        osVersion: '17',
        model: 'iPhone',
        batteryLevel: 80,
        screenTimeUsedMinutes: 120,
      ));

      final sorted = monitor.childrenByScreenTime;
      expect(sorted.first.deviceName, 'High');
    });

    test('updateLocation stores coordinates', () {
      monitor.updateLocation(37.7749, -122.4194);
      expect(monitor.lastLatitude, 37.7749);
      expect(monitor.lastLongitude, -122.4194);
    });

    test('getAggregateStats with children', () {
      monitor.registerChildDevice(ChildDeviceInfo(
        deviceName: 'A',
        osType: 'ios',
        osVersion: '17',
        model: 'iPhone',
        batteryLevel: 80,
        screenTimeUsedMinutes: 60,
      ));
      monitor.registerChildDevice(ChildDeviceInfo(
        deviceName: 'B',
        osType: 'android',
        osVersion: '14',
        model: 'Pixel',
        batteryLevel: 40,
        screenTimeUsedMinutes: 90,
      ));

      final stats = monitor.getAggregateStats();
      expect(stats['total_children'], 2);
      expect(stats['total_screen_time_minutes'], 150);
      expect(stats['avg_battery'], 60);
      expect(stats['os_distribution']['ios'], 1);
      expect(stats['os_distribution']['android'], 1);
    });

    test('getAggregateStats with no children', () {
      final stats = monitor.getAggregateStats();
      expect(stats['total_children'], 0);
    });

    test('buildReport includes all sections', () {
      final report = monitor.buildReport();
      expect(report.containsKey('this_device'), true);
      expect(report.containsKey('children'), true);
      expect(report.containsKey('aggregate'), true);
      expect(report.containsKey('session'), true);
    });
  });
}
