import 'package:flutter_test/flutter_test.dart';
import 'package:worker/services/ios_child_control.dart';

void main() {
  group('WiOSChildControl', () {
    late WiOSChildControl control;

    setUp(() {
      control = WiOSChildControl();
    });

    test('default screen time limit is 120 minutes', () {
      expect(control.dailyScreenTimeLimitMinutes, 120);
    });

    test('setDailyScreenTimeLimit updates limit', () async {
      await control.setDailyScreenTimeLimit(90);
      expect(control.dailyScreenTimeLimitMinutes, 90);
    });

    test('rejects invalid screen time limits', () async {
      await control.setDailyScreenTimeLimit(-10);
      expect(control.dailyScreenTimeLimitMinutes, 120); // unchanged

      await control.setDailyScreenTimeLimit(2000);
      expect(control.dailyScreenTimeLimitMinutes, 120); // unchanged
    });

    test('recordScreenTime accumulates usage', () {
      control.recordScreenTime(30);
      control.recordScreenTime(20);
      expect(control.usedScreenTimeMinutes, 50);
    });

    test('isScreenTimeLimitReached works correctly', () {
      expect(control.isScreenTimeLimitReached, false);

      control.recordScreenTime(120);
      expect(control.isScreenTimeLimitReached, true);
    });

    test('remainingScreenTimeMinutes calculates correctly', () {
      control.recordScreenTime(80);
      expect(control.remainingScreenTimeMinutes, 40);
    });

    test('remainingScreenTimeMinutes does not go negative', () {
      control.recordScreenTime(200);
      expect(control.remainingScreenTimeMinutes, 0);
    });

    test('screenTimeUsagePercent calculates correctly', () {
      control.recordScreenTime(60);
      expect(control.screenTimeUsagePercent, 50.0);
    });

    test('blockApp adds to blocked list', () async {
      await control.blockApp('com.social.app');
      expect(control.blockedApps, contains('com.social.app'));
    });

    test('blockApp removes from allowed list', () {
      control.addAllowedApp('com.social.app');
      control.blockApp('com.social.app');
      expect(control.allowedApps, isNot(contains('com.social.app')));
    });

    test('unblockApp removes from blocked list', () async {
      await control.blockApp('com.social.app');
      await control.unblockApp('com.social.app');
      expect(control.blockedApps, isNot(contains('com.social.app')));
    });

    test('blockApp does not duplicate', () async {
      await control.blockApp('com.social.app');
      await control.blockApp('com.social.app');
      expect(
          control.blockedApps.where((a) => a == 'com.social.app').length, 1);
    });

    test('setContentFilterLevel updates level', () async {
      await control.setContentFilterLevel('strict');
      expect(control.contentFilterLevel, 'strict');
    });

    test('rejects invalid content filter level', () async {
      await control.setContentFilterLevel('invalid');
      expect(control.contentFilterLevel, 'moderate'); // default
    });

    test('setBedtimeMode enables/disables', () async {
      await control.setBedtimeMode(
        enabled: true,
        start: '20:00',
        end: '06:30',
      );
      expect(control.bedtimeModeActive, true);
      expect(control.bedtimeStart, '20:00');
      expect(control.bedtimeEnd, '06:30');

      await control.setBedtimeMode(enabled: false);
      expect(control.bedtimeModeActive, false);
    });

    test('isInBedtimeHours returns false when disabled', () {
      expect(control.isInBedtimeHours(), false);
    });

    test('setWebFilter enables filter and blocks sites', () async {
      await control.setWebFilter(
        enabled: true,
        blockedSites: ['badsite.com', 'evil.org'],
      );
      expect(control.webFilterEnabled, true);
      expect(control.blockedWebsites.length, 2);
    });

    test('blockWebsite adds site', () {
      control.blockWebsite('test.com');
      expect(control.blockedWebsites, contains('test.com'));
    });

    test('unblockWebsite removes site', () {
      control.blockWebsite('test.com');
      control.unblockWebsite('test.com');
      expect(control.blockedWebsites, isNot(contains('test.com')));
    });

    test('setLocationSharing toggles', () async {
      await control.setLocationSharing(true);
      expect(control.locationSharingEnabled, true);

      await control.setLocationSharing(false);
      expect(control.locationSharingEnabled, false);
    });

    test('recordAppUsage tracks per-app', () {
      control.recordAppUsage('com.game.app', 30);
      control.recordAppUsage('com.game.app', 15);
      expect(control.appUsageMinutes['com.game.app'], 45);
    });

    test('resetDailyUsage clears counters', () {
      control.recordScreenTime(60);
      control.recordAppUsage('com.app', 30);

      control.resetDailyUsage();
      expect(control.usedScreenTimeMinutes, 0);
      expect(control.appUsageMinutes, isEmpty);
    });

    test('remainingTimeFormatted shows hours and minutes', () async {
      await control.setDailyScreenTimeLimit(180);
      control.recordScreenTime(90);
      expect(control.remainingTimeFormatted, '1h 30m');
    });

    test('usageStatusIndicator reflects usage level', () {
      expect(control.usageStatusIndicator, 'Plenty left');

      control.recordScreenTime(100);
      expect(control.usageStatusIndicator, 'Almost at limit');

      control.recordScreenTime(25);
      expect(control.usageStatusIndicator, 'LIMIT REACHED');
    });

    test('getStats returns complete data', () {
      final stats = control.getStats();
      expect(stats['screen_time'], isNotNull);
      expect(stats['apps'], isNotNull);
      expect(stats['bedtime'], isNotNull);
      expect(stats['web_filter'], isNotNull);
    });
  });
}
