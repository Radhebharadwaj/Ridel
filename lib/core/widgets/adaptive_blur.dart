import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Platform-adaptive blur wrapper.
///
/// On Web (`kIsWeb`), the browser compositor handles CSS backdrop-filter
/// efficiently, so full `BackdropFilter(ImageFilter.blur)` is preserved.
///
/// On Mobile (`!kIsWeb`), `BackdropFilter` over a live MapLibre PlatformView
/// forces full-screen GPU texture readback + multi-pass Gaussian blur on every
/// frame (60/120fps), causing frame drops, glitches, and device overheating.
/// Skipping the blur pass on mobile eliminates GPU thermal spikes while keeping
/// translucent glass styling crisp and legible.
class AdaptiveBlur extends StatelessWidget {
  final double sigmaX;
  final double sigmaY;
  final Widget child;
  final bool forceBlurOnMobile;

  const AdaptiveBlur({
    super.key,
    required this.sigmaX,
    required this.sigmaY,
    required this.child,
    this.forceBlurOnMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || forceBlurOnMobile) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY),
        child: child,
      );
    }
    return child;
  }
}
