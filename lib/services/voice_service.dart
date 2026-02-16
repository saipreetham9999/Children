import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// WVoiceService — Text-to-Speech and Speech-to-Text
class WVoiceService {
  static final WVoiceService _instance = WVoiceService._internal();
  factory WVoiceService() => _instance;
  WVoiceService._internal();

  late FlutterTts _tts;
  late stt.SpeechToText _speechToText;
  bool _isSpeaking = false;
  bool _isListening = false;

  // Callbacks
  Function(String)? onSpeechResult;  // Speech recognized
  Function(String)? onSpeakComplete;  // TTS finished

  bool get isSpeaking => _isSpeaking;
  bool get isListening => _isListening;

  /// Initialize voice service
  Future<void> initialize() async {
    print('[VoiceService] Initializing...');

    // Initialize TTS
    _tts = FlutterTts();
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.8);  // Slightly slower speech
    await _tts.setVolume(1.0);  // Max volume
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      onSpeakComplete?.call('');
      print('[VoiceService] ✅ TTS completed');
    });

    // Initialize Speech-to-Text
    _speechToText = stt.SpeechToText();
    final available = await _speechToText.initialize(
      onError: (error) => print('[VoiceService] Speech error: $error'),
      onStatus: (status) => print('[VoiceService] Speech status: $status'),
    );

    if (!available) {
      print('[VoiceService] ⚠️  Speech recognition not available');
    } else {
      print('[VoiceService] ✅ Speech recognition ready');
    }

    print('[VoiceService] ✅ Initialized');
  }

  /// Speak text (Text-to-Speech)
  Future<void> speak(String text, {String speaker = 'default'}) async {
    if (text.isEmpty) return;

    print('[VoiceService] Speaking: "$text"');
    _isSpeaking = true;

    try {
      await _tts.speak(text);
    } catch (e) {
      print('[VoiceService] TTS error: $e');
      _isSpeaking = false;
    }
  }

  /// Stop speaking
  Future<void> stopSpeaking() async {
    if (!_isSpeaking) return;
    print('[VoiceService] Stopping TTS');
    await _tts.stop();
    _isSpeaking = false;
  }

  /// Start listening for speech
  Future<void> startListening({
    Duration timeout = const Duration(seconds: 10),
    String language = 'en-US',
  }) async {
    if (_isListening) {
      print('[VoiceService] Already listening');
      return;
    }

    if (!_speechToText.isAvailable) {
      print('[VoiceService] Speech recognition not available');
      return;
    }

    print('[VoiceService] Starting to listen...');
    _isListening = true;

    try {
      _speechToText.listen(
        onResult: (result) {
          print('[VoiceService] Speech result: ${result.recognizedWords}');
          if (result.finalResult) {
            _isListening = false;
            onSpeechResult?.call(result.recognizedWords);
          }
        },
        listenFor: timeout,
        pauseFor: timeout,
        localeId: language,
      );
    } catch (e) {
      print('[VoiceService] Listening error: $e');
      _isListening = false;
    }
  }

  /// Stop listening
  Future<void> stopListening() async {
    if (!_isListening) return;
    print('[VoiceService] Stopping listener');
    await _speechToText.stop();
    _isListening = false;
  }

  /// Speak command (e.g., "/play youtube" → speaks it out)
  Future<void> speakCommand(String command) async {
    final friendlyText = _formatCommandForSpeech(command);
    print('[VoiceService] Speaking command: $friendlyText');
    await speak(friendlyText);
  }

  /// Listen for voice reply
  Future<String?> listenForReply({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    print('[VoiceService] Waiting for voice reply...');

    // Speak prompt first
    await speak("Go ahead, I'm listening");

    String? result;
    Completer<String?> completer = Completer();

    final onResult = (String text) {
      if (!completer.isCompleted) {
        completer.complete(text);
      }
    };

    final previousCallback = onSpeechResult;
    onSpeechResult = onResult;

    await startListening(timeout: timeout);

    // Wait for result or timeout
    result = await completer.future
        .timeout(timeout, onTimeout: () => null);

    onSpeechResult = previousCallback;
    return result;
  }

  /// Test voice by speaking a phrase
  Future<void> testVoice() async {
    await speak("Voice service is working! I can speak to you.");
  }

  /// Get available languages
  Future<List<String>> getAvailableLanguages() async {
    try {
      final locales = await _tts.getLanguages;
      return List<String>.from(locales ?? []);
    } catch (e) {
      print('[VoiceService] Error getting languages: $e');
      return [];
    }
  }

  /// Cleanup
  void dispose() {
    _tts.stop();
    _speechToText.cancel();
    print('[VoiceService] Disposed');
  }

  // Private methods

  /// Convert command to friendly text for speaking
  String _formatCommandForSpeech(String command) {
    final parts = command.split(' ');
    if (parts[0] == '/play' && parts.length > 1) {
      final app = parts[1].split(':')[0];
      return 'Playing $app';
    } else if (parts[0] == '/pause') {
      return 'Pausing playback';
    } else if (parts[0] == '/volume' && parts.length > 1) {
      return 'Setting volume to ${parts[1]} percent';
    }
    return command.replaceFirst('/', '');
  }
}
