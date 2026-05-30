import 'dart:async';
import 'dart:ui'; // 🌟 Added for ImageFilter (Native Blur)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AuthHeader extends StatefulWidget {
  const AuthHeader({
    required this.texts,
    required this.neonColor,
    this.isPaused = false,
    super.key,
  });

  final List<String> texts;
  final Color neonColor;
  final bool isPaused;

  @override
  State<AuthHeader> createState() => _AuthHeaderState();
}

class _AuthHeaderState extends State<AuthHeader> {
  String _displayedText = '';
  int _currentTextIndex = 0;

  @override
  void initState() {
    super.initState();
    _startTypingLoop();
  }

  bool get _canPlayHaptic {
    if (widget.isPaused) return false;
    final hasFocus = FocusManager.instance.primaryFocus?.hasFocus ?? false;
    if (hasFocus) return false;
    return true;
  }

  Future<void> _startTypingLoop() async {
    while (mounted) {
      final currentTarget = widget.texts[_currentTextIndex];

      // Typing Forward
      for (var i = 0; i <= currentTarget.length; i++) {
        if (!mounted) return;
        setState(() => _displayedText = currentTarget.substring(0, i));

        if (i > 0 && i % 2 == 0 && _canPlayHaptic) {
          HapticFeedback.selectionClick();
        }

        await Future.delayed(const Duration(milliseconds: 60));
      }

      await Future.delayed(const Duration(milliseconds: 1500));

      // Backspacing
      for (var i = currentTarget.length; i >= 0; i--) {
        if (!mounted) return;
        setState(() => _displayedText = currentTarget.substring(0, i));

        if (i % 3 == 0 && _canPlayHaptic) {
          HapticFeedback.lightImpact();
        }

        await Future.delayed(const Duration(milliseconds: 30));
      }

      if (mounted) {
        setState(() {
          _currentTextIndex = (_currentTextIndex + 1) % widget.texts.length;
        });
      }

      await Future.delayed(const Duration(milliseconds: 400));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🌟 THEME CONSTANT: Syncing with our new Native Glass logic
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    const Color glassTint = Color(0x1AFFFFFF);

    return SizedBox(
      height: 100,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 🚀 HIGH-FIDELITY LAYERED GLASS TEXT ENGINE
          Flexible(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!isLightMode) ...[
                  Text(
                    _displayedText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      shadows: [
                        Shadow(
                          color: widget.neonColor.withValues(alpha: 0.4),
                          blurRadius: 20,
                        ),
                        Shadow(
                          color: Colors.white.withValues(alpha: 0.1),
                          blurRadius: 30,
                        ),
                      ],
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(-0.4, -0.6),
                    child: Text(
                      _displayedText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ],
                if (isLightMode)
                  Text(
                    _displayedText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.black87,
                    ),
                  )
                else
                  ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.5),
                        Colors.white.withValues(alpha: 0.20),
                        widget.neonColor.withValues(alpha: 0.50),
                        widget.neonColor,
                        Colors.white.withValues(alpha: 0.1),
                      ],
                      stops: const [0.0, 0.12, 0.45, 0.85, 1.0],
                    ).createShader(bounds),
                    child: Text(
                      _displayedText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 14),

          // 🚀 ELEGANT NATIVE GLASS DROPLET CURSOR
          // Synced entirely with the ridel_liquid_button physics
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: isLightMode 
                      ? Colors.black.withValues(alpha: 0.05) 
                      : Colors.black.withValues(alpha: 0.25),
                  blurRadius: isLightMode ? 8 : 15,
                  spreadRadius: isLightMode ? 0 : -2,
                  offset: Offset(0, isLightMode ? 2 : 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(50),
              clipBehavior: Clip.antiAlias, // Ensures perfectly round edges
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // 🌟 3D Glass Bevel Effect
                    color: isLightMode ? Colors.black.withValues(alpha: 0.04) : null,
                    gradient: isLightMode ? null : LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        glassTint.withValues(
                            alpha: (glassTint.a + 0.06).clamp(0.0, 1.0)),
                        glassTint,
                        glassTint.withValues(
                            alpha: (glassTint.a - 0.02).clamp(0.0, 1.0)),
                      ],
                    ),
                    border: Border.all(
                      color: isLightMode 
                          ? Colors.black.withValues(alpha: 0.08)
                          : Colors.white.withValues(alpha: 0.15),
                      width: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
