import 'package:flutter_test/flutter_test.dart';
import 'package:worker/services/device_policy_service.dart';

void main() {
  group('WDevicePolicyService', () {
    late WDevicePolicyService policyService;

    setUp(() {
      policyService = WDevicePolicyService();
      policyService.initialize();
    });

    tearDown(() {
      policyService.dispose();
    });

    test('initializes with default policies', () {
      expect(policyService.policyCount, greaterThanOrEqualTo(4));
      expect(policyService.isEnforcing, true);
    });

    test('addPolicy adds new policy', () {
      final before = policyService.policyCount;
      policyService.addPolicy(DevicePolicy(
        id: 'test_1',
        name: 'Test Policy',
        type: 'screen_time',
        config: {'limit_minutes': 60},
      ));
      expect(policyService.policyCount, before + 1);
    });

    test('addPolicy replaces policy with same ID', () {
      policyService.addPolicy(DevicePolicy(
        id: 'dup_1',
        name: 'First',
        type: 'screen_time',
      ));
      final countAfterFirst = policyService.policyCount;

      policyService.addPolicy(DevicePolicy(
        id: 'dup_1',
        name: 'Second',
        type: 'screen_time',
      ));
      expect(policyService.policyCount, countAfterFirst);
    });

    test('removePolicy removes by ID', () {
      policyService.addPolicy(DevicePolicy(
        id: 'remove_me',
        name: 'Remove Me',
        type: 'screen_time',
      ));
      final before = policyService.policyCount;

      policyService.removePolicy('remove_me');
      expect(policyService.policyCount, before - 1);
    });

    test('togglePolicy enables/disables', () {
      policyService.addPolicy(DevicePolicy(
        id: 'toggle_test',
        name: 'Toggle',
        type: 'screen_time',
        enabled: true,
      ));

      policyService.togglePolicy('toggle_test', false);
      final policy =
          policyService.policies.firstWhere((p) => p.id == 'toggle_test');
      expect(policy.enabled, false);
    });

    test('getPoliciesForDevice filters by target', () {
      policyService.addPolicy(DevicePolicy(
        id: 'device_specific',
        name: 'Device Specific',
        type: 'screen_time',
        targetDevices: ['phone1'],
      ));

      final phone1Policies =
          policyService.getPoliciesForDevice('phone1');
      final phone2Policies =
          policyService.getPoliciesForDevice('phone2');

      expect(
          phone1Policies.any((p) => p.id == 'device_specific'), true);
      expect(
          phone2Policies.any((p) => p.id == 'device_specific'), false);
    });

    test('checkDevice detects screen time violation', () {
      policyService.addPolicy(DevicePolicy(
        id: 'st_check',
        name: 'Screen Time Check',
        type: 'screen_time',
        config: {'limit_minutes': 60, 'warning_at_minutes': 50},
        targetDevices: ['child1'],
      ));

      final violations = policyService.checkDevice(
        deviceName: 'child1',
        screenTimeMinutes: 70,
        appUsage: {},
      );

      expect(violations.length, greaterThan(0));
      expect(violations.first.severity, 'critical');
    });

    test('checkDevice detects screen time warning', () {
      policyService.addPolicy(DevicePolicy(
        id: 'st_warn',
        name: 'Screen Time Warn',
        type: 'screen_time',
        config: {'limit_minutes': 60, 'warning_at_minutes': 50},
        targetDevices: ['child2'],
      ));

      final violations = policyService.checkDevice(
        deviceName: 'child2',
        screenTimeMinutes: 55,
        appUsage: {},
      );

      expect(violations.any((v) => v.severity == 'warning'), true);
    });

    test('checkDevice detects blocked app usage', () {
      policyService.addPolicy(DevicePolicy(
        id: 'app_block_check',
        name: 'App Block',
        type: 'app_block',
        config: {
          'blocked_apps': ['com.social.app']
        },
      ));

      final violations = policyService.checkDevice(
        deviceName: 'child1',
        screenTimeMinutes: 30,
        appUsage: {},
        currentApp: 'com.social.app',
      );

      expect(violations.any((v) => v.policyName == 'App Block'), true);
    });

    test('setScreenTimeForDevice creates targeted policy', () {
      policyService.setScreenTimeForDevice('kidPhone', 90);

      final policies = policyService.getPoliciesForDevice('kidPhone');
      expect(
          policies.any((p) => p.id == 'screen_time_kidPhone'), true);
    });

    test('blockAppsForDevice creates targeted policy', () {
      policyService.blockAppsForDevice('kidPhone', ['com.game.app']);

      final policies = policyService.getPoliciesForDevice('kidPhone');
      final appPolicy = policies.firstWhere(
          (p) => p.id == 'app_block_kidPhone');
      expect(appPolicy.config['blocked_apps'], contains('com.game.app'));
    });

    test('setBedtimeForDevice creates targeted policy', () {
      policyService.setBedtimeForDevice('kidPhone', '20:00', '06:30');

      final policies = policyService.getPoliciesForDevice('kidPhone');
      final bedtime = policies.firstWhere(
          (p) => p.id == 'bedtime_kidPhone');
      expect(bedtime.config['start'], '20:00');
      expect(bedtime.config['end'], '06:30');
    });

    test('violations are recorded', () {
      expect(policyService.violationCount, 0);

      policyService.addPolicy(DevicePolicy(
        id: 'v_test',
        name: 'Violation Test',
        type: 'screen_time',
        config: {'limit_minutes': 10, 'warning_at_minutes': 5},
      ));

      policyService.checkDevice(
        deviceName: 'child',
        screenTimeMinutes: 15,
        appUsage: {},
      );

      expect(policyService.violationCount, greaterThan(0));
    });

    test('clearViolations empties list', () {
      policyService.addPolicy(DevicePolicy(
        id: 'clear_test',
        name: 'Clear',
        type: 'screen_time',
        config: {'limit_minutes': 10, 'warning_at_minutes': 5},
      ));
      policyService.checkDevice(
        deviceName: 'child',
        screenTimeMinutes: 15,
        appUsage: {},
      );

      policyService.clearViolations();
      expect(policyService.violationCount, 0);
    });

    test('getStats returns complete data', () {
      final stats = policyService.getStats();
      expect(stats['total_policies'], greaterThan(0));
      expect(stats['is_enforcing'], true);
      expect(stats['policies'], isList);
    });
  });

  group('DevicePolicy', () {
    test('appliesTo returns true for empty targetDevices', () {
      final policy = DevicePolicy(
        id: '1',
        name: 'Global',
        type: 'screen_time',
      );
      expect(policy.appliesTo('anyDevice'), true);
    });

    test('appliesTo returns true only for targeted devices', () {
      final policy = DevicePolicy(
        id: '1',
        name: 'Targeted',
        type: 'screen_time',
        targetDevices: ['phone1'],
      );
      expect(policy.appliesTo('phone1'), true);
      expect(policy.appliesTo('phone2'), false);
    });

    test('toJson/fromJson roundtrip', () {
      final original = DevicePolicy(
        id: 'rt_1',
        name: 'Roundtrip',
        type: 'bedtime',
        config: {'start': '21:00'},
        targetDevices: ['d1'],
      );

      final json = original.toJson();
      final restored = DevicePolicy.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.type, original.type);
      expect(restored.config['start'], '21:00');
      expect(restored.targetDevices, contains('d1'));
    });
  });
}
