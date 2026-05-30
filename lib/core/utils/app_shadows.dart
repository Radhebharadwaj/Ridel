import 'package:flutter/material.dart';

class AppShadows {
  /// 🌟 LEVEL 1: Subtle & Soft Shadow (Interactive Buttons / Small capsules)
  static List<BoxShadow> get buttonSoft => [
        // Ultra-low alpha, high diffusion
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            offset: const Offset(0, 4),
            blurRadius: 12),
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            offset: const Offset(0, 8),
            blurRadius: 24,
            spreadRadius: -2),
      ];

  /// 🌟 LEVEL 2: Deep Layered Shadow (Modal Sheets, Profile Cards, Big Containers)
  static List<BoxShadow> get cardFloating => [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            offset: const Offset(0, 4),
            blurRadius: 8),
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            offset: const Offset(0, 12),
            blurRadius: 32,
            spreadRadius: -4),
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            offset: const Offset(0, 24),
            blurRadius: 64,
            spreadRadius: -8),
      ];

  /// 🌟 LEVEL 3: Ambient Glass Glow (For map overlays and frosted backgrounds)
  static List<BoxShadow> glassAmbient(Color baseColor) => [
        BoxShadow(
            color: baseColor.withValues(alpha: 0.06),
            offset: const Offset(0, 8),
            blurRadius: 24),
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            offset: const Offset(0, 4),
            blurRadius: 12),
      ];

  /// 🌟 LEVEL 4: Premium Cyberpunk/Neon Ambient Pop
  static List<BoxShadow> get neonGlowCyan => [
        BoxShadow(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
            offset: const Offset(0, 4),
            blurRadius: 16),
        BoxShadow(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
            offset: const Offset(0, 12),
            blurRadius: 40,
            spreadRadius: -4),
      ];
}
