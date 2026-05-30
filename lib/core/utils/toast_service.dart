// lib/core/utils/toast_service.dart

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ridel/core/utils/app_haptics.dart';

enum ToastType { success, error, info, warning }

class ToastService {
  static OverlayEntry? _overlayEntry;

  // 🌟 NAYA: Ab hum optional 'title' pass kar sakte hain
  static void showSuccess(BuildContext context, String message,
      {String? title, VoidCallback? onTap}) {
    _showApplePill(context,
        type: ToastType.success,
        title: title ??
            "Success", // Agar title diya hai toh wo use hoga, warna "Success"
        message: message,
        onTap: onTap);
  }

  static void showError(BuildContext context, String message,
      {String? title, VoidCallback? onTap}) {
    _showApplePill(context,
        type: ToastType.error,
        title: title ?? "Alert",
        message: message,
        onTap: onTap);
  }

  static void showInfo(BuildContext context, String message,
      {String? title, VoidCallback? onTap}) {
    _showApplePill(context,
        type: ToastType.info,
        title: title ?? "Info",
        message: message,
        onTap: onTap);
  }

  static void _showApplePill(
    BuildContext context, {
    required ToastType type,
    required String title,
    required String message,
    VoidCallback? onTap,
  }) {
    switch (type) {
      case ToastType.error:
        AppHaptics.warning();
        break;
      case ToastType.success:
        AppHaptics.heavyImpact();
        break;
      default:
        AppHaptics.lightImpact();
        break;
    }

    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => _ApplePillWidget(
        type: type,
        title: title,
        message: message,
        onTap: onTap,
        onDismiss: () {
          _overlayEntry?.remove();
          _overlayEntry = null;
        },
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }
}

class _ApplePillWidget extends StatefulWidget {
  final ToastType type;
  final String title;
  final String message;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  const _ApplePillWidget({
    // super.key, <-- Is line ko delete kar de
    required this.type,
    required this.title,
    required this.message,
    this.onTap,
    required this.onDismiss,
  });

  @override
  State<_ApplePillWidget> createState() => _ApplePillWidgetState();
}

class _ApplePillWidgetState extends State<_ApplePillWidget> {
  bool _isEntering = true;
  double _dragOffsetY = 0;
  // 🌟 FIX 1: Glitch hatane ke liye default scale 1.0 rakha hai
  double _scale = 1.0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 🌟 Ab scale nahi badlega launch par, sirf slide hoke aayega (Zero Glitch)
      if (mounted) setState(() => _isEntering = false);
      _startTimer();
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 4), _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    setState(() {
      _isEntering = true;
      _scale = 0.85; // 🌟 Shrink only when leaving or tapped
    });
    Future.delayed(const Duration(milliseconds: 400), widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Color _getIconColor() {
    switch (widget.type) {
      case ToastType.error:
        return const Color(0xFFFF3B30);
      case ToastType.success:
        return const Color(0xFF32D74B);
      case ToastType.warning:
        return const Color(0xFFFFD60A);
      case ToastType.info:
        return const Color(0xFF0A84FF);
    }
  }

  IconData _getIcon() {
    switch (widget.type) {
      case ToastType.error:
        return Icons.close_rounded;
      case ToastType.success:
        return Icons.check_rounded;
      case ToastType.warning:
        return Icons.priority_high_rounded;
      case ToastType.info:
        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    double targetTop = MediaQuery.of(context).padding.top + 16;

    if (_isEntering) {
      targetTop = -100;
    } else {
      targetTop += _dragOffsetY;
    }

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 600), // Butter smooth slide
      curve: Curves.elasticOut,
      top: targetTop,
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedScale(
          scale: _scale,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: GestureDetector(
            onTap: () {
              if (widget.onTap != null) widget.onTap!();
              _dismiss();
            },
            onVerticalDragUpdate: (details) {
              if (details.delta.dy < 0) {
                setState(() => _dragOffsetY += details.delta.dy);
              }
            },
            onVerticalDragEnd: (details) {
              if (_dragOffsetY < -20 || details.primaryVelocity! < -300) {
                AppHaptics.sheetInteraction();
                _dismiss();
              } else {
                setState(() => _dragOffsetY = 0);
              }
            },
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                // 🌟 FIX: minWidth add kar diya taaki pill hamesha elegant aur lambi dikhe
                constraints: const BoxConstraints(
                  maxWidth: 320,
                  minWidth:
                      240, // Ise 240-260 ke beech rakhoge toh best "Long Pill" look aayega
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 25,
                      spreadRadius: -2,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  clipBehavior: Clip.antiAlias,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                        sigmaX: 25, sigmaY: 25), // 🌟 High blur
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(100),
                        // 🌟 FIX 2: True Glass + Gradient!
                        // Isme dark base aur white shine dono blend kiye hain.
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [
                                  Colors.white.withValues(
                                      alpha: 0.15), // Top reflection
                                  const Color(0xFF0B0E17).withValues(
                                      alpha: 0.65), // Dark Glass Body
                                  const Color(0xFF0B0E17)
                                      .withValues(alpha: 0.85), // Bottom Depth
                                ]
                              : [
                                  Colors.white.withValues(alpha: 0.95),
                                  Colors.white.withValues(alpha: 0.65),
                                  Colors.white.withValues(alpha: 0.50),
                                ],
                          stops: const [0.0, 0.3, 1.0],
                        ),
                        border: Border.all(
                          color: isDark
                              ? Colors.white
                                  .withValues(alpha: 0.15) // Crisp glass edge
                              : Colors.black.withValues(alpha: 0.08),
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _getIconColor().withValues(alpha: 0.15),
                            ),
                            child: Icon(_getIcon(),
                                color: _getIconColor(), size: 16),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  style: GoogleFonts.inter(
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                    height: 1.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.message,
                                  style: GoogleFonts.inter(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.7)
                                        : Colors.black54,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    height: 1.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
