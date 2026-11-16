import 'package:flutter/material.dart';

/// Unified responsive breakpoints across Mobile, Foldable/Tablet, and Desktop/Web.
///
/// Uses `MediaQuery.sizeOf(context)` so widgets only rebuild when window
/// dimensions change (never on keyboard animation frames).
class ResponsiveLayout {
  ResponsiveLayout._();

  static const double compactMobileBreakpoint = 380.0;
  static const double tabletBreakpoint = 600.0;
  static const double desktopBreakpoint = 768.0;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopBreakpoint;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= tabletBreakpoint && w < desktopBreakpoint;
  }

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < desktopBreakpoint;

  static bool isCompactMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compactMobileBreakpoint;

  static double horizontalMargin(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= desktopBreakpoint) return 32.0;
    if (w < compactMobileBreakpoint) return 16.0;
    return 20.0;
  }

  static double clampedOverlayWidth(
    BuildContext context, {
    double horizontalInset = 32.0,
    double minWidth = 260.0,
    double maxWidth = 520.0,
  }) {
    final available = MediaQuery.sizeOf(context).width - horizontalInset;
    return available.clamp(minWidth, maxWidth);
  }
}
