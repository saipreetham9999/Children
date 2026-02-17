import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class WVoiceService {
  static final WVoiceService _instance = WVoiceService._internal();
  factory WVoiceService() => _instance;
  WVoiceService._internal();

  late FlutterTts _tts;
  late stt.SpeechToText _speechToText;

  bool _isSpeaking = false;
  bool _isListening = false;
  Timer? _listeningTimer;

  // Callbacks
  Function(String recognizedText, List<int>? audioBytes)? onSpeechResult;
  Function(String)? onSpeakComplete;

  bool get isSpeaking => _isSpeaking;
  bool get isListening => _isListening;

  Future<void> initialize() async {
    print('[VoiceService] Initializing...');

    // Initialize TTS
    _tts = FlutterTts();
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.8);
    await _tts.setVolume(1.0);
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
      print('[VoiceService] ⚠️ Speech recognition not available');
    } else {
      print('[VoiceService] ✅ Speech recognition ready');
    }

    print('[VoiceService] ✅ Initialized');
  }

  /// Start continuous listening with audio capture via speech_to_text
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

    print('[VoiceService] Starting continuous listening...');
    _isListening = true;
    _startListeningLoop(timeout, language);
  }

  /// Internal method - handles continuous listening loop
  void _startListeningLoop(Duration timeout, String language) {
    if (!_isListening) return;

    print('[VoiceService] Listening cycle started...');

    try {
      _speechToText.listen(
        onResult: (result) {

          // When speech is finalized
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            print('[VoiceService] ✅ Final: "${result.recognizedWords}"');
            _isListening = false;

            // Note: speech_to_text library doesn't directly expose audio bytes
            // Brain will receive text with timestamp - it can sync with audio if needed
            // Pass null for audio bytes since speech_to_text doesn't provide them
            onSpeechResult?.call(result.recognizedWords, null);

            // Auto-restart listening
            if (_listeningTimer != null) {
              Future.delayed(const Duration(milliseconds: 500), () {
                if (_listeningTimer != null) {
                  _startListeningLoop(timeout, language);
                }
              });
            }
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

  Future<void> stopSpeaking() async {
    if (!_isSpeaking) return;
    print('[VoiceService] Stopping TTS');
    await _tts.stop();
    _isSpeaking = false;
  }

  Future<void> stopListening() async {
    if (!_isListening) return;
    print('[VoiceService] Stopping listener');

    _listeningTimer?.cancel();
    _listeningTimer = null;

    await _speechToText.stop();
    _isListening = false;
  }

  Future<void> speakCommand(String command) async {
    final friendlyText = _formatCommandForSpeech(command);
    print('[VoiceService] Speaking command: $friendlyText');
    await speak(friendlyText);
  }

  Future<String?> listenForReply({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    print('[VoiceService] Waiting for voice reply...');

    await speak("Go ahead, I'm listening");

    String? result;
    Completer<String?> completer = Completer();

    final onResult = (String text, List<int>? _) {
      if (!completer.isCompleted) {
        completer.complete(text);
      }
    };

    final previousCallback = onSpeechResult;
    onSpeechResult = onResult;

    await startListening(timeout: timeout);

    result = await completer.future
        .timeout(timeout, onTimeout: () => null);

    onSpeechResult = previousCallback;
    return result;
  }

  Future<void> testVoice() async {
    await speak("Voice service is working! I can speak to you.");
  }

  Future<List<String>> getAvailableLanguages() async {
    try {
      final locales = await _tts.getLanguages;
      return List<String>.from(locales ?? []);
    } catch (e) {
      print('[VoiceService] Error getting languages: $e');
      return [];
    }
  }

  void dispose() {
    _listeningTimer?.cancel();
    _tts.stop();
    _speechToText.cancel();
    print('[VoiceService] Disposed');
  }

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