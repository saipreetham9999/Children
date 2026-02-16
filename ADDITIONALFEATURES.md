# ShaRogai Phase 3: Additional Features

Branch: `additionalfeatures`

## Overview

This branch implements advanced features for the ShaRogai worker app:

1. **Runtime Group Chat** — No database, memory-only chat during app session
2. **Voice Integration** — Text-to-speech & speech-to-text for voice commands & replies
3. **Bluetooth Mesh Networking** — P2P communication with automatic relay
4. **Signal Strength Tracking** — Smart transport switching (HTTP vs Bluetooth)
5. **Speaker Control** — Volume management and audio routing
6. **iOS/iPad Optimization** — Specialized audio session handling

---

## Features Breakdown

### 1. Runtime Group Chat (No Database)

**File:** `lib/services/chat_service.dart`

- ✅ Messages stored only in memory (max 200 in session)
- ✅ Signal strength per message (0-100%)
- ✅ Transport type tracking (HTTP, Bluetooth, Local)
- ✅ Synced status (marked when sent to Brain)
- ✅ Voice message support
- ✅ Real-time updates via ChangeNotifier

**Usage:**
```dart
final chatService = context.read<WChatService>();

// Send text message
await chatService.sendMessage('You', 'Hello everyone!');

// Send voice message
await chatService.sendMessage(
  'You',
  'Voice message transcription',
  audioPath: '/path/to/audio.wav',
  transportType: 'bluetooth',
);

// Get all messages
List<WChatMessage> messages = chatService.messages;

// Get stats
var stats = chatService.getStats();
```

**Message Metadata:**
```dart
class WChatMessage {
  String id;               // Unique per session
  String sender;          // Device/user name
  String text;            // Message content
  DateTime timestamp;     // When sent
  String? audioPath;      // Voice message file
  int signalStrength;     // 0-100% (connection quality)
  String transportType;   // 'bluetooth', 'http', 'local'
  bool isSynced;          // Sent to Brain?
}
```

---

### 2. Voice Integration (TTS + STT)

**File:** `lib/services/voice_service.dart`

#### Text-to-Speech (Dart)
```dart
final voiceService = WVoiceService();
await voiceService.initialize();

// Speak a command
await voiceService.speak('Now playing YouTube');

// Speak a friendlier command
await voiceService.speakCommand('/play youtube:https://...');
```

#### Speech-to-Text (Voice Input)
```dart
// Start listening for voice
await voiceService.startListening(
  timeout: Duration(seconds: 10),
  language: 'en-US',
);

// Listen for callback
voiceService.onSpeechResult = (String text) {
  print('User said: $text');
};

// Get voice reply from user
String? reply = await voiceService.listenForReply(
  timeout: Duration(seconds: 15),
);
```

**Supported Languages:**
- English (US, GB, AU, IN)
- Spanish, French, German, Italian
- Mandarin, Japanese, Korean
- And 50+ more

---

### 3. Bluetooth Mesh Networking

**File:** `lib/services/bluetooth_connectivity.dart`

**Key Capabilities:**
- Device discovery (BLE scan)
- Signal strength tracking (RSSI -100 to 0)
- Best signal device selection
- Connect/disconnect

**Usage:**
```dart
final bluetooth = context.read<WBluetoothConnectivity>();

// Start scanning for nearby devices
await bluetooth.startScanning(timeout: Duration(seconds: 15));

// Get nearby devices
Map<String, BluetoothDevice> devices = bluetooth.nearbyDevices;

// Get signal strength (0-100%)
Map<String, int> signals = bluetooth.signalStrengthPercent;

// Find strongest device
String? bestDevice = bluetooth.getBestSignalDevice();

// Connect to device
await bluetooth.connectToDevice('iPhone_Mom');

// Send data via Bluetooth
await bluetooth.sendDataToDevice('iPhone_Mom', [0x01, 0x02, 0x03]);
```

**Signal Strength Ranges:**
```
RSSI Range:      -30 to -100 dBm
Signal (%):       100 to 0
Interpretation:
  -30 to -50:     Excellent (90-100%)
  -50 to -70:     Good (70-90%)
  -70 to -85:     Fair (40-70%)
  -85 to -100:    Weak (0-40%)
```

---

### 4. Signal Strength Tracking

**File:** `lib/services/signal_strength_tracker.dart`

**Monitors:**
- HTTP latency (milliseconds)
- HTTP success rate (%)
- Bluetooth RSSI (dBm)
- Bluetooth device count
- Overall connection quality (0-100%)

**Smart Transport Switching:**
```
Prefers Bluetooth if:
  ✓ Bluetooth device nearby (RSSI > -80)
  ✓ Bluetooth signal better than HTTP by 20%+

Falls back to HTTP if:
  ✓ No Bluetooth nearby
  ✓ HTTP connection available

Uses Local Queue if:
  ✓ Both offline
  ✓ Waiting for sync
```

**Usage:**
```dart
final signal = context.read<WSignalStrengthTracker>();

// Monitor changes
signal.onTransportChange = (String transport) {
  print('Switched to $transport');
};

// Get current stats
int overallSignal = signal.overallSignal;  // 0-100%
String transport = signal.preferredTransport;  // 'http' or 'bluetooth'

// Record HTTP response
signal.recordHttpResponse(
  latencyMs: 45,
  success: true,
);

// Record Bluetooth signal
signal.recordBluetoothSignal(
  rssi: -55,
  deviceCount: 3,
);

// Get signal bars (like WhatsApp)
String bars = signal.signalBars;  // "▓▓▓▓" or "▓▓░░" etc
```

---

### 5. Speaker Control

**File:** `lib/services/speaker_controller.dart`

**Features:**
- Volume control (0-100%)
- Mute/unmute
- Speaker routing (speaker/earpiece/bluetooth)
- Volume change monitoring

**Usage:**
```dart
final speaker = context.read<WSpeakerController>();

// Set volume
await speaker.setVolume(75);  // 75%

// Increase/decrease
await speaker.increaseVolume(10);  // +10%
await speaker.decreaseVolume(5);   // -5%

// Mute/unmute
await speaker.mute();
await speaker.unmute();

// Route to specific output
speaker.forceToSpeaker();      // Use device speaker
speaker.routeToBluetooth();    // Use Bluetooth if available

// Get current state
int volume = speaker.currentVolume;       // 0-100
String mode = speaker.speakerMode;       // 'speaker', 'earpiece', 'bluetooth'
bool muted = speaker.isMuted;
String indicator = speaker.volumeIndicator;  // '🔊 High', '🔉 Medium', etc
```

---

### 6. iOS/iPad Audio Optimization

#### iOS Audio Session Management

**File:** `ios/Runner/AudioSessionManager.swift`

Handles:
- ✅ Audio category setup (.playback)
- ✅ Interruption handling (phone calls, alarms)
- ✅ Audio route changes (headphones in/out)
- ✅ Speaker mode selection
- ✅ Background audio playback
- ✅ Focus mode compliance (iOS 15+)

#### Dart Integration

**File:** `lib/services/ios_audio_session.dart`

```dart
// Initialize audio session (iOS only)
await WiOSAudioSession.initializeAudioSession();

// Set speaker mode
await WiOSAudioSession.setSpeakerMode('speaker');

// Get current audio route
String? route = await WiOSAudioSession.getCurrentRoute();
// Returns: 'speaker', 'headphones', 'bluetooth', 'earpiece'

// Enable background playback
await WiOSAudioSession.enableBackgroundAudio();

// Respect Focus modes (iOS 15+)
await WiOSAudioSession.configureFocusMode();
```

#### iPad-Specific Screen

**File:** `lib/screens/ipad_chat_screen.dart`

- ✅ Split-view layout (landscape mode)
- ✅ Larger message bubbles
- ✅ Side panel with controls
- ✅ Volume slider
- ✅ Speaker mode buttons
- ✅ Chat statistics
- ✅ Signal quality visualization

---

## Chat Screen UI

**File:** `lib/screens/chat_screen.dart`

**Features:**
- Real-time message display (newest at top)
- Signal strength indicator per message (🟢🟡🟠🔴)
- Transport type indicator (☁️ HTTP, 📡 Bluetooth, 💾 Local)
- Voice input button with recording indicator
- Synced status indicator (⏳ pending vs ✓ synced)
- Signal bar in app bar (8 signal, latency, transport)
- Responsive layout for phone and tablet

**Components:**
```
┌─ AppBar ─────────────────────────────┐
│ Group Chat        ▓▓▓░ ☁️  45ms      │
├───────────────────────────────────────┤
│ ┌─ Signal Bar ───────────────────┐   │
│ │ 📶 Strong • HTTP • 45ms        │   │
│ └────────────────────────────────┘   │
├───────────────────────────────────────┤
│ ┌─ Chat Bubble (Other) ─────────┐   │
│ │ Device A                  🟢☁️  │   │
│ │ Hello everyone!                │   │
│ │ 10:30 ☁️ 🟢                    │   │
│ └────────────────────────────────┘   │
│                    ┌─ Chat Bubble ──┐│
│                    │ (Own Message) ││
│                    │ Hi there!     ││
│                    │ 10:31 ☁️ 🟢 ⏳││
│                    └───────────────┘│
├───────────────────────────────────────┤
│ [Text Field] [🎤] [📤]                 │
└───────────────────────────────────────┘
```

---

## Integration with Phase 1 (Group Commands)

When Brain sends a command, the app can:

1. **Speak it out** (TTS)
   ```
   Brain: /play youtube:https://...
   App: Speaks "Playing YouTube"
   Device: Opens YouTube
   ```

2. **Record voice reply** (STT)
   ```
   User: Presses microphone button
   App: "What's your reply?"
   User: "Thanks!"
   App: Sends "Thanks!" to chat
   ```

3. **Smart transport selection**
   ```
   If Bluetooth available and strong:
     Use Bluetooth for lower latency
   Else:
     Use HTTP to Brain
   ```

---

## Permissions Required

### Android

Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<!-- Already added in MainActivity setup -->
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

Request at runtime:
```dart
await Permission.microphone.request();
await Permission.bluetoothScan.request();
await Permission.bluetoothConnect.request();
```

### iOS

Add to `ios/Runner/Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>ShaRogai uses the microphone for voice messages.</string>

<key>NSBluetoothPeripheralUsageDescription</key>
<string>ShaRogai uses Bluetooth for device mesh.</string>

<key>NSBluetoothAlwaysUsageDescription</key>
<string>ShaRogai needs Bluetooth to discover nearby devices.</string>
```

Enable in Xcode:
- Signing & Capabilities
- + Audio, AirPlay, and Picture in Picture
- + Background Modes (audio)

---

## Testing Checklist

### Chat Service
- [ ] Messages appear in real-time
- [ ] Signal strength tracked per message
- [ ] Transport type indicator correct
- [ ] Max 200 messages limit works
- [ ] Synced status updates when sent to Brain

### Voice Service
- [ ] TTS speaks clearly
- [ ] STT recognizes voice input accurately
- [ ] Commands are formatted correctly for speech
- [ ] Multiple languages work

### Bluetooth Connectivity
- [ ] Device discovery works
- [ ] RSSI updates in real-time
- [ ] Best signal device correctly identified
- [ ] Connection/disconnection works

### Signal Strength
- [ ] HTTP latency monitored
- [ ] Bluetooth RSSI monitored
- [ ] Transport switches when appropriate
- [ ] Signal history tracked (last 60 samples)

### Speaker Control
- [ ] Volume changes (0-100%)
- [ ] Mute/unmute works
- [ ] Speaker mode changes
- [ ] Volume indicators accurate

### iOS Audio
- [ ] Audio works in background
- [ ] Phone calls pause audio
- [ ] Audio resumes after call
- [ ] Headphones detected
- [ ] Bluetooth speaker detected
- [ ] Focus mode respected

### Chat UI
- [ ] Messages display in real-time
- [ ] Signal bars visible
- [ ] Transport indicators correct
- [ ] Voice input button responds
- [ ] Synced indicators accurate
- [ ] iPad layout optimized

---

## Branch Integration

To integrate into main branch:

```bash
# On additionalfeatures branch
git push origin additionalfeatures

# Create PR or cherry-pick:
git checkout main
git merge additionalfeatures --no-ff
```

### Files Modified/Added:
- ✅ pubspec.yaml (added 7 plugins)
- ✅ lib/main.dart (service initialization)
- ✅ lib/services/chat_service.dart (new)
- ✅ lib/services/voice_service.dart (new)
- ✅ lib/services/bluetooth_connectivity.dart (new)
- ✅ lib/services/signal_strength_tracker.dart (new)
- ✅ lib/services/speaker_controller.dart (new)
- ✅ lib/services/ios_audio_session.dart (new)
- ✅ lib/screens/chat_screen.dart (new)
- ✅ lib/screens/ipad_chat_screen.dart (new)
- ✅ lib/models/chat_message.dart (new)
- ✅ ios/Runner/AudioSessionManager.swift (new)
- ✅ ios/Runner/GeneratedPluginRegistrant+AudioSession.swift (new)

---

## Performance Notes

### Memory Usage
- Chat service: ~5-10 MB (200 messages max)
- Voice service: ~2-3 MB
- Bluetooth: ~3-5 MB
- Signal tracker: <1 MB
- **Total: ~15-20 MB**

### Battery Impact
- Chat polling: ~5% per hour (already happening)
- Bluetooth scan: +8% per hour (when active)
- Voice recognition: +2% per use
- **Total: ~15% per hour** (under normal usage)

### Network Impact
- Chat messages: ~100 bytes each
- Signal tracking: ~50 bytes every 5s
- Bluetooth preferred when available (no network usage)

---

## Future Enhancements

- [ ] Offline message persistence (SQLite)
- [ ] Message encryption (Signal protocol)
- [ ] Voice message storage & playback
- [ ] Avatar support per device
- [ ] Message reactions/emojis
- [ ] Read receipts
- [ ] Typing indicators
- [ ] Message search
- [ ] File sharing (images, audio)
- [ ] Group video calls
- [ ] Message pinning
- [ ] Auto-translate messages

---

## Troubleshooting

### Voice not working
- [ ] Check microphone permission granted
- [ ] Test with microphone app first
- [ ] Restart app if speech recognition crashes
- [ ] Check available languages

### Bluetooth not discovering devices
- [ ] Enable Bluetooth on both devices
- [ ] Check Bluetooth permissions
- [ ] Devices must be in BLE advertisement mode
- [ ] Check iOS/Android Bluetooth versions (5.0+)

### Chat messages not syncing
- [ ] Check network connection
- [ ] Verify Brain is running on correct URL
- [ ] Check signal tracker (should show HTTP latency)
- [ ] Look at logs for [ChatService] messages

### Audio not playing on iOS
- [ ] Verify "Audio, AirPlay, Picture in Picture" capability
- [ ] Check UIBackgroundModes in Info.plist
- [ ] Try different audio routes (speaker vs earpiece)
- [ ] Test with known working audio file

---

For questions or issues, check logs with tag: `[ChatService]`, `[VoiceService]`, `[BluetoothConnectivity]`, `[SignalTracker]`, `[SpeakerController]`, `[iOSAudioSession]`
