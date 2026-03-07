import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter/material.dart';

class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;

  // 🚀 Initialize exactly once
  Future<bool> init() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (val) => debugPrint("Speech Error: $val"),
        onStatus: (val) => debugPrint("Speech Status: $val"),
      );
      return _isInitialized;
    } catch (e) {
      debugPrint("Mic Init Error: $e");
      return false;
    }
  }

  // 🎤 Smart Listen Logic
  void startListening({
    required Function(String) onResult,
    required VoidCallback onDone,
    required Function(double) onSoundLevel,
  }) {
    if (!_isInitialized) return;

    _speech.listen(
      onResult: (result) {
        // Sirf tab return kare jab wo confident ho ki user bol chuka hai
        if (result.finalResult) {
          onResult(result.recognizedWords);
          onDone(); // Stop automatically after getting result
        } else {
          // Live partial results (optional, can be removed if you only want final)
           if(result.recognizedWords.isNotEmpty) {
             // onResult(result.recognizedWords); // Uncomment for live typing effect
           }
        }
      },
      // 🎛️ NOISE & FOCUS SETTINGS
      listenFor: const Duration(seconds: 10), // Max 10 sec sunega
      pauseFor: const Duration(seconds: 2),   // 2 sec chup rehne par band ho jayega (Noise ignore)
      partialResults: true,
      onSoundLevelChange: onSoundLevel,
      cancelOnError: true,
      listenMode: ListenMode.confirmation, // 🔥 Best for short commands, filters background chatter
    );
  }

  void stop() async {
    await _speech.stop();
  }

  bool get isListening => _speech.isListening;
}