/// WDeviceModel — Device identity and profile
class WDeviceModel {
  final String deviceName;
  final String deviceType; // android, ios
  final String osVersion;
  final String deviceModel;
  final List<String> capabilities;

  WDeviceModel({
    required this.deviceName,
    required this.deviceType,
    required this.osVersion,
    required this.deviceModel,
    this.capabilities = const ['camera', 'screen', 'audio'],
  });

  Map<String, dynamic> toJson() => {
        'device_name': deviceName,
        'device_type': deviceType,
        'os_version': osVersion,
        'device_model': deviceModel,
        'capabilities': capabilities,
      };

  @override
  String toString() =>
      'WDevice($deviceName - $deviceType $osVersion on $deviceModel)';
}
