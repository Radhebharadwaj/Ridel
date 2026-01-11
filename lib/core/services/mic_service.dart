import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart'; // debugPrint के लिए


class MicService with ChangeNotifier {
  // --- STATE VARIABLES ---
  bool _isListening = false;
  String _recognizedText = '';
  String? _listenError;
  bool _autoSubmitTriggered = false; // "Done", "Go", आदि पर सबमिट हुआ
  
  // MOCK: Timer for simulating listening timeout or auto-stop logic
  Timer? _stopTimer; 

  // --- GETTERS ---
  bool get isListening => _isListening;
  String get recognizedText => _recognizedText;
  String? get listenError => _listenError;
  bool get autoSubmitTriggered => _autoSubmitTriggered;

  // --- MOCK CONSTANTS (Auto-stop trigger words) ---
  static const List<String> _autoStopWords = ['done', 'go', 'ok', 'stop', 'enter'];

  // --- PUBLIC API METHODS ---

  /// वॉयस रिकग्निशन सुनना शुरू करता है।
  void startListening() {
    if (_isListening) return;

    _isListening = true;
    _listenError = null;
    _recognizedText = '';
    _autoSubmitTriggered = false;
    notifyListeners();

    // MOCK: Simulating the recognition process
    _stopTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _mockSpeechRecognition(timer.tick);
      _checkAutoStop(onAutoSubmit: () {
         stopListening(autoSubmit: true);
      });
      
      // Simulate timeout after 8 seconds of silence/listening
      if (timer.tick >= 8) {
          stopListening();
      }
    });

    debugPrint('MicService: Listening started (MOCK)');
  }

  /// वॉयस रिकग्निशन को बंद करता है।
  void stopListening({bool autoSubmit = false}) {
    if (!_isListening) return;

    _stopTimer?.cancel();
    _isListening = false;
    _autoSubmitTriggered = autoSubmit;
    notifyListeners();
    
    // Clear the recognized text after it is assumed to be used by the UI
    if (autoSubmit) {
       // This text will be used by the calling screen (e.g., home_screen)
    }
    
    debugPrint('MicService: Listening stopped. Auto-Submit: $autoSubmit');
  }

  // --- PRIVATE MOCK LOGIC ---
  
  // MOCK: Speech recognition को सिम्युलेट करता है
  void _mockSpeechRecognition(int tick) {
    if (tick == 1) {
      _recognizedText = 'I want to find the ';
    } else if (tick == 3) {
      _recognizedText = 'I want to find the fastest route to ';
    } else if (tick == 5) {
      _recognizedText = 'I want to find the fastest route to Hauz Khas. Done.';
    }
    // Update UI only if text changed
    if (tick > 0 && tick % 2 != 0) {
      notifyListeners();
    }
  }

  /// MOCK: ऑटो-स्टॉप शब्दों की जाँच करता है।
  void _checkAutoStop({required VoidCallback onAutoSubmit}) {
    final lowerText = _recognizedText.toLowerCase();
    
    // पूर्ण शब्द के आधार पर जाँच करें (जैसे 'done' या 'go')
    final isDone = _autoStopWords.any((word) => 
        lowerText.contains(' $word') || lowerText.endsWith('$word.'));
    
    if (isDone) {
      onAutoSubmit();
    }
  }

  // --- DISPOSE ---
  @override
  void dispose() {
    _stopTimer?.cancel();
    super.dispose();
  }
}