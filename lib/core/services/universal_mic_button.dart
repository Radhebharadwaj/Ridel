import 'package:flutter/material.dart';
import 'package:avatar_glow/avatar_glow.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/services/speech_service.dart';

class UniversalMicButton extends StatefulWidget {
  final Function(String) onTextRecognized;
  final bool isDark;
  final Color? activeColor;
  final double size; // Icon size

  const UniversalMicButton({
    super.key,
    required this.onTextRecognized,
    required this.isDark,
    this.activeColor,
    this.size = 20, // Default thoda chota rakha hai cute look ke lie
  });

  @override
  State<UniversalMicButton> createState() => _UniversalMicButtonState();
}

class _UniversalMicButtonState extends State<UniversalMicButton> {
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
  }

  void _toggleListening() async {
    AppHaptics.heavyImpact();

    if (_isListening) {
      SpeechService().stop();
      setState(() => _isListening = false);
    } else {
      bool available = await SpeechService().init();
      if (!mounted) return;
      if (available) {
        setState(() => _isListening = true);

        SpeechService().startListening(
          onResult: (text) {
            if (text.trim().isNotEmpty) {
              widget.onTextRecognized(text.trim());
              AppHaptics.heavyImpact();
            }
          },
          onDone: () {
            if (mounted) setState(() => _isListening = false);
          },
          onSoundLevel: (level) {},
        );
      } else {
        ToastService.showError(context, "Microphone permission denied");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Colors
    final Color mainColor = widget.activeColor ??
        (widget.isDark ? const Color(0xFF00E5FF) : Colors.black);
    final Color iconColor = _isListening
        ? mainColor // Active state me icon colored hoga (Glass style)
        : (widget.isDark ? Colors.white38 : Colors.black38);

    return GestureDetector(
      onTap: _toggleListening,
      child: SizedBox(
        width: 44, // Compact touch area
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 🌊 GLASSY WAVE ANIMATION
            if (_isListening)
              AvatarGlow(
                animate: true,
                // Glow color me opacity kam taki wo "Hawa" jaisa lage
                glowColor: mainColor,
                duration: const Duration(milliseconds: 1500),
                repeat: true,
                startDelay: const Duration(milliseconds: 100),
                // ✨ Update: Radius chota kar dia (Cute & Compact)
                endRadius: 28.0,
                curve: Curves.easeInOut,
                child:
                    const SizedBox.shrink(), // Child khali, sirf glow chahiye
              ),

            // 🎤 MAIN BUTTON (Glassy Container)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _isListening
                  ? 36
                  : 32, // Active hone par thoda sa bada hoga (Pop effect)
              height: _isListening ? 36 : 32,
              decoration: BoxDecoration(
                // ✨ Glass Effect: Low Opacity Background
                color: _isListening
                    ? mainColor.withValues(alpha: 0.15)
                    : Colors.transparent,
                shape: BoxShape.circle,
                // ✨ Border tabhi dikhega jab active ho (Glass Edge)
                border: _isListening
                    ? Border.all(
                        color: mainColor.withValues(alpha: 0.3), width: 1)
                    : null,
              ),
              child: Center(
                child: Icon(
                  _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: iconColor,
                  size: widget.size,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
