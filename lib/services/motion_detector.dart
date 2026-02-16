import 'package:image/image.dart' as img;
import 'dart:typed_data';

/// ShaRogai Motion Detector — On-device motion detection
class WMotionDetector {
  img.Image? _previousFrame;
  final double motionThreshold; // 0.0 to 1.0
  int _frameCount = 0;
  int _motionDetections = 0;

  WMotionDetector({this.motionThreshold = 0.15});

  bool detectMotion(Uint8List frameBytes) {
    try {
      final currentFrame = img.decodeImage(frameBytes);
      if (currentFrame == null) return false;

      _frameCount++;

      // First frame baseline
      if (_previousFrame == null) {
        _previousFrame = currentFrame;
        print('[WMotion] Frame 1 stored as baseline');
        return false;
      }

      if (currentFrame.width != _previousFrame!.width ||
          currentFrame.height != _previousFrame!.height) {
        _previousFrame = currentFrame;
        return false;
      }

      double pixelDiffCount = 0;
      final totalPixels = currentFrame.width * currentFrame.height;

      for (int y = 0; y < currentFrame.height; y++) {
        for (int x = 0; x < currentFrame.width; x++) {
          final curr = currentFrame.getPixel(x, y);
          final prev = _previousFrame!.getPixel(x, y);

          final diffR = (curr.r - prev.r).abs();
          final diffG = (curr.g - prev.g).abs();
          final diffB = (curr.b - prev.b).abs();

          if (diffR > 30 || diffG > 30 || diffB > 30) {
            pixelDiffCount++;
          }
        }
      }

      final motionPercentage = pixelDiffCount / totalPixels;

      _previousFrame = currentFrame;

      final isMotion = motionPercentage > motionThreshold;

      if (isMotion) {
        _motionDetections++;
        final percent = (motionPercentage * 100).toStringAsFixed(1);
        print(
          '[WMotion] Motion detected: $percent% (threshold: ${(motionThreshold * 100).toStringAsFixed(0)}%)',
        );
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

  void dispose() {
    _previousFrame = null;
  }
}
