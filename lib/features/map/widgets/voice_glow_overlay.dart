import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/map/map_provider.dart';

class VoiceGlowOverlay extends StatelessWidget {
  const VoiceGlowOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Selector<MapProvider, ValueNotifier<bool>>(
          selector: (context, provider) => provider.isSpeaking,
          builder: (context, isSpeakingNotifier, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: isSpeakingNotifier,
              builder: (context, isSpeaking, child) {
                return AnimatedOpacity(
                  duration: isSpeaking
                      ? const Duration(milliseconds: 600)
                      : const Duration(milliseconds: 1500),
                  curve: Curves.easeInOutCubic,
                  opacity: isSpeaking ? 1.0 : 0.0,
                  child: isSpeaking ? child : const SizedBox.shrink(),
                );
              },
              child: RepaintBoundary(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(seconds: 4),
                  builder: (context, value, staticChild) {
                    return Transform.rotate(
                      angle: value * 2 * 3.141592653589793,
                      child: staticChild,
                    );
                  },
                  onEnd: () {
                    // Loop animation if needed, but TweenAnimationBuilder loops require re-triggering.
                    // Instead, we just rotate it.
                  },
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 80.0, sigmaY: 80.0),
                    child: ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return const SweepGradient(
                          colors: [
                            Colors.cyan,
                            Colors.purpleAccent,
                            Colors.pinkAccent,
                            Colors.cyan
                          ],
                        ).createShader(bounds);
                      },
                      blendMode: BlendMode.srcIn,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          border: Border.all(color: Colors.white, width: 30.0),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
