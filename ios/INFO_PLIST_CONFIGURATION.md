# iOS Audio Configuration Guide

## Required Info.plist Additions

Add the following keys to `ios/Runner/Info.plist` to enable audio features on iOS:

### 1. Background Modes (Required for background audio playback)

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>location</string>
    <string>voip</string>
</array>
```

**What these do:**
- `audio`: Allows app to play audio in background
- `location`: Allows GPS tracking in background
- `voip`: Allows audio processing for voice communication

### 2. Microphone Permissions (Required for voice input)

```xml
<key>NSMicrophoneUsageDescription</key>
<string>ShaRogai uses the microphone to record voice messages for group chat.</string>
```

### 3. Audio Session Category (Set at runtime, not in plist)

The app configures `AVAudioSession.Category.playback` at runtime for:
- Background audio playback
- Duck other audio (reduces volume of other apps)
- Default to speaker output

### 4. iOS Device Capabilities

Add supported device types for optimal experience:

```xml
<key>UISupportedInterfaceOrientations</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationPortraitUpsideDown</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
</array>

<key>UISupportedInterfaceOrientations~ipad</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationPortraitUpsideDown</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
</array>
```

## Capabilities.plist or Xcode Configuration

### Audio, AirPlay, and Picture in Picture

In Xcode:
1. Select Runner target
2. Signing & Capabilities
3. + Capability
4. Select "Audio, AirPlay, and Picture in Picture"

This enables:
- Background audio playback
- AirPlay speaker support (for iPad/AirPods)
- Picture in Picture mode (for iPad)

### Bluetooth (For mesh networking)

In Xcode:
1. Signing & Capabilities
2. + Capability
3. Select "HomeKit" (optional, for smart home integration)

Or manually in plist:

```xml
<key>NSBluetoothPeripheralUsageDescription</key>
<string>ShaRogai uses Bluetooth to connect with nearby devices for mesh messaging.</string>

<key>NSBluetoothAlwaysUsageDescription</key>
<string>ShaRogai needs Bluetooth to discover and communicate with nearby devices.</string>
```

## iOS Version-Specific Considerations

### iOS 13-14
- Basic audio playback ✅
- Background audio ✅
- Microphone ✅
- Bluetooth LE ✅

### iOS 15
- All above +
- Focus modes (respects Do Not Disturb)
- Spatial audio support
- Enhanced speech recognition

### iOS 16+
- All above +
- Lossless audio codecs
- Enhanced background audio
- Improved Focus mode integration

## iPad-Specific Considerations

### Larger Speaker
- iPad has significantly larger and more powerful speakers than iPhone
- Audio output is automatically louder by default
- Consider using `DefaultToSpeaker` option in all audio sessions

### Multi-App Support
- iPad supports Split View and Slide Over
- Audio may need to be managed across multiple apps
- Use AVAudioSession interruption handling

### Audio Routing
- External speakers (Bluetooth, AirPlay) preferred on iPad
- Headphone jack (iPad Air 2 and older)
- Lightning connector audio (iPad mini 2-4)
- USB-C audio (newer iPad models)

### Recommended Config for iPad

```swift
// In AudioSessionManager.swift, add iPad-specific handling:

let device = UIDevice.current.model
if device.contains("iPad") {
    // Increase volume for better speaker output
    // Use AirPlay support
    try audioSession.setCategory(
        .playback,
        mode: .default,
        options: [
            .duckOthers,
            .defaultToSpeaker,
            .allowAirPlay  // Enable AirPlay for iPad
        ]
    )
}
```

## Testing Checklist

### iPhone Testing
- [ ] Audio plays with speaker
- [ ] Audio pauses on phone call
- [ ] Audio resumes after call
- [ ] Headphones work
- [ ] Bluetooth speakers work
- [ ] Volume buttons control audio
- [ ] Lock screen controls work
- [ ] Background playback works (lock device)
- [ ] Voice input works
- [ ] Microphone permissions granted

### iPad Testing
- [ ] All iPhone tests pass
- [ ] Sound is loud enough (larger speaker)
- [ ] AirPlay works with AirPods
- [ ] AirPlay works with other speakers
- [ ] Split View audio handling
- [ ] Landscape orientation audio

### iOS 15+ Testing
- [ ] Focus mode respected (silenced if in Focus)
- [ ] Spatial audio works (if device supports)
- [ ] Speech recognition accurate

### Apple Watch Testing (if implemented)
- [ ] Watch speakers work (speaker is tiny, limited audio quality)
- [ ] Volume control from watch
- [ ] Haptic feedback works
- [ ] Watch connectivity stable

## Common Issues & Solutions

### Issue: Audio doesn't play in background
**Solution:**
- Verify "Audio, AirPlay, and Picture in Picture" capability is enabled
- Check `UIBackgroundModes` includes `audio`
- Ensure audio session category is set to `.playback`

### Issue: Microphone not working for voice input
**Solution:**
- Check `NSMicrophoneUsageDescription` in Info.plist
- Request microphone permission from user
- Check microphone is enabled in Settings

### Issue: Audio plays from earpiece instead of speaker
**Solution:**
- Use `defaultToSpeaker` option in audio session
- Call `setSpeakerMode("speaker")` explicitly
- Check if headphones are connected (auto-detected)

### Issue: Volume too quiet on iPad
**Solution:**
- Check physical volume buttons
- Verify speaker mode is enabled
- Use `DefaultToSpeaker` option
- Consider adding volume boost in audio processing

### Issue: Bluetooth audio not working
**Solution:**
- Verify Bluetooth is enabled in device settings
- Check Bluetooth permission in Info.plist
- Ensure AVAudioSession routes audio to Bluetooth
- Test with known working Bluetooth speaker

## Entitlements.plist (Advanced)

For advanced audio features, add to `ios/Runner/Entitlements.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Allows background processing -->
    <key>com.apple.developer.networking.multicast</key>
    <true/>

    <!-- Allows local network access (for Bluetooth mesh) -->
    <key>com.apple.developer.networking.local-outbound</key>
    <true/>

    <!-- HealthKit (optional, for fitness features) -->
    <key>com.apple.developer.healthkit</key>
    <true/>
</dict>
</plist>
```

## Final Checklist Before Release

- [ ] Info.plist has all required permissions
- [ ] Background modes enabled in Xcode
- [ ] "Audio, AirPlay, Picture in Picture" capability added
- [ ] iOS 13+ compatibility tested
- [ ] iPad tested (larger screen, speaker)
- [ ] iPhone tested (various models)
- [ ] Background audio works
- [ ] Microphone works for voice input
- [ ] Bluetooth connectivity works
- [ ] Audio session respects interruptions (phone calls)
- [ ] Volume control works
- [ ] Lock screen controls work
- [ ] Tested with headphones connected/disconnected
- [ ] Tested with Bluetooth speakers
