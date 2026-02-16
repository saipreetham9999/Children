import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';

/// WFrameService — Capture and process camera frames
class WFrameService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Initialize camera
  Future<void> initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isEmpty) {
        throw Exception('No cameras found');
      }
      // Use back camera (rear)
      final backCamera = _cameras!.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.low, // Low resolution for efficiency
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      _isInitialized = true;
      print('[WFrame] Camera initialized');
    } catch (e) {
      print('[WFrame] Init error: $e');
      rethrow;
    }
  }

  /// Capture single frame
  Future<Uint8List> captureFrame() async {
    if (!_isInitialized || _controller == null) {
      throw Exception('Camera not initialized');
    }
    try {
      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      print('[WFrame] Captured ${bytes.length} bytes');
      return bytes;
    } catch (e) {
      print('[WFrame] Capture error: $e');
      rethrow;
    }
  }

  /// Compress frame (reduce quality for transmission)
  Uint8List compressFrame(Uint8List frameBytes, {int quality = 60}) {
    try {
      final image = img.decodeImage(frameBytes);
      if (image == null) return frameBytes;

      // Reduce resolution to 50%
      final resized = img.copyResize(image, width: image.width ~/ 2);
      // Compress to JPEG with quality
      final compressed = img.encodeJpg(resized, quality: quality);
      final ratio = (compressed.length / frameBytes.length * 100).toStringAsFixed(0);
      print('[WFrame] Compressed to $ratio% (${compressed.length} bytes)');
      return Uint8List.fromList(compressed);
    } catch (e) {
      print('[WFrame] Compress error: $e, returning original');
      return frameBytes;
    }
  }

  /// Dispose camera controller
  Future<void> dispose() async {
    await _controller?.dispose();
    _isInitialized = false;
    print('[WFrame] Disposed');
  }
}
