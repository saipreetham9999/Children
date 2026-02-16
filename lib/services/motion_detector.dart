import 'package:image/image.dart' as img;
import 'dart:typed_data';

/// WMotionDetector — Optimized on-device motion detection
class WMotionDetector {
  img.Image? _previousFrame;
  final double motionThreshold; // 0.0 to 1.0, default 0.15 (15% pixel change)
  int _frameCount = 0;
  int _motionDetections = 0;

  WMotionDetector({this.motionThreshold = 0.10}); // Lowered threshold slightly

  /// Detect motion between current and previous frame
  /// Uses sampling for performance in background isolates
  bool detectMotion(Uint8List frameBytes) {
    try {
      final currentFrame = img.decodeImage(frameBytes);
      if (currentFrame == null) return false;

      _frameCount++;

      if (_previousFrame == null) {
        _previousFrame = currentFrame;
        return false;
      }

      if (currentFrame.width != _previousFrame!.width ||
          currentFrame.height != _previousFrame!.height) {
        _previousFrame = currentFrame;
        return false;
      }

      double pixelDiffCount = 0;
      int sampledPixels = 0;
      
      // Optimization: Sample every 4th pixel to save CPU in background
      const int step = 4;

      for (int y = 0; y < currentFrame.height; y += step) {
        for (int x = 0; x < currentFrame.width; x += step) {
          sampledPixels++;
          final currPixel = currentFrame.getPixel(x, y);
          final prevPixel = _previousFrame!.getPixel(x, y);

          // Calculate simple Euclidean distance or channel diff
          final diffR = (currPixel.r - prevPixel.r).abs();
          final diffG = (currPixel.g - prevPixel.g).abs();
          final diffB = (currPixel.b - prevPixel.b).abs();

          if (diffR > 35 || diffG > 35 || diffB > 35) {
            pixelDiffCount++;
          }
        }
      }

      final motionPercentage = pixelDiffCount / sampledPixels;
      _previousFrame = currentFrame;

      final isMotion = motionPercentage > motionThreshold;
      if (isMotion) {
        _motionDetections++;
        print('[WMotion] Motion detected: ${(motionPercentage * 100).toStringAsFixed(1)}%');
      }

      return isMotion;
    } catch (e) {
      print('[WMotion] Detection error: $e');
      return false;
    }
  }

  Map<String, dynamic> getStats() => {
        'frames_processed': _frameCount,
        'motion_detections': _motionDetections,
        'detection_rate': _frameCount > 0
            ? (_motionDetections / _frameCount * 100).toStringAsFixed(1)
            : '0.0',
      };

  void resetStats() {
    _frameCount = 0;
    _motionDetections = 0;
  }
}
