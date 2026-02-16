import 'package:image/image.dart' as img;
import 'dart:typed_data';

/// ShaRogai Motion Detector — On-device motion detection
/// Compares frames and only sends candidates when motion detected
class WMotionDetector {
  img.Image? _previousFrame;
  final double motionThreshold; // 0.0 to 1.0, default 0.15 (15% pixel change)
  int _frameCount = 0;
  int _motionDetections = 0;

  WMotionDetector({this.motionThreshold = 0.15});

  /// Detect motion between current and previous frame
  /// Returns true if motion detected above threshold
  bool detectMotion(Uint8List frameBytes) {
    try {
      final currentFrame = img.decodeImage(frameBytes);
      if (currentFrame == null) return false;

      _frameCount++;

      // First frame: no comparison, just store
      if (_previousFrame == null) {
        _previousFrame = currentFrame;
        print('[WMotion] Frame 1 stored as baseline');
        return false;
      }

      // Compare dimensions
      if (currentFrame.width != _previousFrame!.width ||
          currentFrame.height != _previousFrame!.height) {
        _previousFrame = currentFrame;
        return false;
      }

      // Calculate pixel difference percentage
      double pixelDiffCount = 0;
      final totalPixels = currentFrame.width * currentFrame.height;
      final currPixels = currentFrame.data?.toList() ?? [];
      final prevPixels = _previousFrame!.data?.toList() ?? [];

      for (int i = 0; i < totalPixels && i < currPixels.length && i < prevPixels.length; i++) {
        final curr = currPixels[i];
        final prev = prevPixels[i];

        // Extract RGB using bit shifting
        final currR = (curr >> 16) & 0xFF;
        final currG = (curr >> 8) & 0xFF;
        final currB = curr & 0xFF;

        final prevR = (prev >> 16) & 0xFF;
        final prevG = (prev >> 8) & 0xFF;
        final prevB = prev & 0xFF;

        final diffR = (currR - prevR).abs();
        final diffG = (currG - prevG).abs();
        final diffB = (currB - prevB).abs();

        // If any channel differs by > 30, count as changed
        if (diffR > 30 || diffG > 30 || diffB > 30) {
          pixelDiffCount++;
        }
      }

      final motionPercentage = pixelDiffCount / totalPixels;

      _previousFrame = currentFrame;

      final isMotion = motionPercentage > motionThreshold;
      if (isMotion) {
        _motionDetections++;
        final percent = (motionPercentage * 100).toStringAsFixed(1);
        print(
            '[WMotion] Motion detected: $percent% (threshold: ${(motionThreshold * 100).toStringAsFixed(0)}%)');
      }

      return isMotion;
    } catch (e) {
      print('[WMotion] Detection error: $e');
      return false; // Default to no motion on error
    }
  }

  /// Get motion detection stats
  Map<String, dynamic> getStats() => {
        'frames_processed': _frameCount,
        'motion_detections': _motionDetections,
        'detection_rate': _frameCount > 0
            ? (_motionDetections / _frameCount * 100).toStringAsFixed(1)
            : '0.0',
      };

  /// Reset stats
  void resetStats() {
    _frameCount = 0;
    _motionDetections = 0;
  }

  /// Dispose
  void dispose() {
    _previousFrame = null;
  }
}
