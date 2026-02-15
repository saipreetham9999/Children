class Config {
  static const String brainIp = "192.168.0.183";
  static const int port = 8080;
  static const String baseUrl = "http://$brainIp:$port/api";
  static const String deviceId = "Poco-M2-Pro";
  static const int heartbeatInterval = 5; // Seconds
}
