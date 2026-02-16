import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ios_child_control.dart';
import '../services/child_os_monitor.dart';
import '../services/device_policy_service.dart';

/// WChildControlScreen — Parent dashboard for controlling all child devices
class WChildControlScreen extends StatelessWidget {
  const WChildControlScreen({Key? key}) : super(key: key);

  /// Safely look up a provider — returns null if not registered yet
  static T? _tryRead<T>(BuildContext context) {
    try {
      return Provider.of<T>(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if optional services are ready
    final childMonitor = _tryRead<WChildOSMonitor>(context);
    final childControl = _tryRead<WiOSChildControl>(context);
    final policyService = _tryRead<WDevicePolicyService>(context);

    if (childMonitor == null || childControl == null || policyService == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Child Controls')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.amber),
              SizedBox(height: 16),
              Text('Services loading in background...'),
              SizedBox(height: 8),
              Text('This takes a few seconds on first launch.',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Child Controls'),
        actions: [
          Consumer<WChildOSMonitor>(
            builder: (_, monitor, __) => Chip(
              label: Text('${monitor.connectedChildCount} devices'),
              backgroundColor: monitor.connectedChildCount > 0
                  ? Colors.green.shade100
                  : Colors.grey.shade200,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildScreenTimeCard(context),
            const SizedBox(height: 12),
            _buildBedtimeCard(context),
            const SizedBox(height: 12),
            _buildContentFilterCard(context),
            const SizedBox(height: 12),
            _buildAppBlockCard(context),
            const SizedBox(height: 12),
            _buildConnectedDevicesCard(context),
            const SizedBox(height: 12),
            _buildPolicyViolationsCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildScreenTimeCard(BuildContext context) {
    return Consumer<WiOSChildControl>(
      builder: (_, control, __) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.timer, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Text('Screen Time',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text(control.remainingTimeFormatted,
                      style: TextStyle(
                        color: control.isScreenTimeLimitReached
                            ? Colors.red
                            : Colors.green,
                        fontWeight: FontWeight.bold,
                      )),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: control.screenTimeUsagePercent / 100,
                backgroundColor: Colors.grey.shade200,
                color: control.screenTimeUsagePercent >= 80
                    ? Colors.red
                    : Colors.blue,
              ),
              const SizedBox(height: 8),
              Text(
                '${control.usedScreenTimeMinutes}m / ${control.dailyScreenTimeLimitMinutes}m '
                '(${control.usageStatusIndicator})',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _timeChip(context, '1h', 60, control),
                  const SizedBox(width: 8),
                  _timeChip(context, '2h', 120, control),
                  const SizedBox(width: 8),
                  _timeChip(context, '3h', 180, control),
                  const SizedBox(width: 8),
                  _timeChip(context, '4h', 240, control),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeChip(BuildContext context, String label, int minutes,
      WiOSChildControl control) {
    final isSelected = control.dailyScreenTimeLimitMinutes == minutes;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => control.setDailyScreenTimeLimit(minutes),
    );
  }

  Widget _buildBedtimeCard(BuildContext context) {
    return Consumer<WiOSChildControl>(
      builder: (_, control, __) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bedtime, color: Colors.indigo),
                  const SizedBox(width: 8),
                  const Text('Bedtime Mode',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Switch(
                    value: control.bedtimeModeActive,
                    onChanged: (v) => control.setBedtimeMode(enabled: v),
                  ),
                ],
              ),
              if (control.bedtimeModeActive) ...[
                const SizedBox(height: 8),
                Text(
                  '${control.bedtimeStart} - ${control.bedtimeEnd}',
                  style: const TextStyle(fontSize: 16),
                ),
                if (control.isInBedtimeHours())
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Bedtime is active now',
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentFilterCard(BuildContext context) {
    return Consumer<WiOSChildControl>(
      builder: (_, control, __) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Text('Content Filter',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'off', label: Text('Off')),
                  ButtonSegment(value: 'moderate', label: Text('Moderate')),
                  ButtonSegment(value: 'strict', label: Text('Strict')),
                ],
                selected: {control.contentFilterLevel},
                onSelectionChanged: (v) =>
                    control.setContentFilterLevel(v.first),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBlockCard(BuildContext context) {
    return Consumer<WiOSChildControl>(
      builder: (_, control, __) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.block, color: Colors.red),
                  const SizedBox(width: 8),
                  const Text('Blocked Apps',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${control.blockedApps.length} blocked'),
                ],
              ),
              if (control.blockedApps.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: control.blockedApps
                      .map((app) => Chip(
                            label: Text(app.split('.').last),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => control.unblockApp(app),
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Web filter: ${control.webFilterEnabled ? "ON" : "OFF"} '
                '(${control.blockedWebsites.length} sites blocked)',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectedDevicesCard(BuildContext context) {
    return Consumer<WChildOSMonitor>(
      builder: (_, monitor, __) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.devices, color: Colors.teal),
                  const SizedBox(width: 8),
                  const Text('Connected Devices',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              if (monitor.thisDevice != null)
                _deviceTile(monitor.thisDevice!, isThisDevice: true),
              ...monitor.childDevices.values.map(
                (d) => _deviceTile(d),
              ),
              if (monitor.connectedChildCount == 0 &&
                  monitor.thisDevice == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No devices connected',
                      style: TextStyle(color: Colors.grey)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deviceTile(ChildDeviceInfo device, {bool isThisDevice = false}) {
    return ListTile(
      leading: Icon(
        device.osType == 'ios' ? Icons.phone_iphone : Icons.phone_android,
        color: device.isOnline ? Colors.green : Colors.grey,
      ),
      title: Text(
        '${device.deviceName}${isThisDevice ? " (This)" : ""}',
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${device.osType.toUpperCase()} ${device.osVersion} | '
        'Battery: ${device.batteryLevel}% ${device.batteryIndicator} | '
        'Screen: ${device.screenTimeUsedMinutes}m',
      ),
      trailing: Icon(
        Icons.circle,
        size: 12,
        color: device.isOnline ? Colors.green : Colors.red,
      ),
    );
  }

  Widget _buildPolicyViolationsCard(BuildContext context) {
    return Consumer<WDevicePolicyService>(
      builder: (_, policyService, __) {
        final recent = policyService.recentViolations;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning,
                        color: recent.isNotEmpty
                            ? Colors.orange
                            : Colors.grey),
                    const SizedBox(width: 8),
                    const Text('Policy Alerts',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (recent.isNotEmpty)
                      Text('${recent.length} recent',
                          style: const TextStyle(color: Colors.orange)),
                  ],
                ),
                if (recent.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No policy violations',
                        style: TextStyle(color: Colors.grey)),
                  ),
                ...recent.take(5).map((v) => ListTile(
                      dense: true,
                      leading: Icon(
                        v.severity == 'critical'
                            ? Icons.error
                            : Icons.warning,
                        color: v.severity == 'critical'
                            ? Colors.red
                            : Colors.orange,
                        size: 20,
                      ),
                      title: Text(v.policyName,
                          style: const TextStyle(fontSize: 14)),
                      subtitle: Text(v.description,
                          style: const TextStyle(fontSize: 12)),
                    )),
              ],
            ),
          ),
        );
      },
    );
  }
}
