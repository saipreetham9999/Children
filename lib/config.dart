/// WConfig — Worker configuration constants
class WConfig {
  // Motion detection threshold (0.0 to 1.0)
  // Lower = more sensitive, Higher = less sensitive
  static const double motionThresholdDefault = 0.15; // 15% pixel change

  // Capture interval (milliseconds)
  static const int captureIntervalMs = 2000; // Every 2 seconds

  // Heartbeat interval (seconds)
  static const int heartbeatIntervalSeconds = 5;

  // Event poll interval (seconds)
  static const int eventPollIntervalSeconds = 2;

  // Frame compression quality (0-100)
  static const int frameCompressionQuality = 60;

  // Notification configuration
  static const String notificationChannelId = 'worker_channel';
  static const String notificationChannelName = 'Worker Monitoring';
  static const int foregroundNotificationId = 888;

  // Logging
  static const bool enableDebugLogs = true;
}
