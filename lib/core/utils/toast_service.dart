// lib/core/utils/toast_service.dart

import 'dart:async';
import 'dart:collection';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:ridel/core/utils/app_haptics.dart';

enum ToastType { success, error, info, warning }

class ToastService {
  static OverlayEntry? _overlayEntry;
  static final Queue<Map<String, dynamic>> _queue = Queue<Map<String, dynamic>>();
  static bool _isShowing = false;

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

  static void showActionToast(
    BuildContext context, {
    required String message,
    required String actionLabel,
    required VoidCallback onActionTap,
    String? title,
  }) {
    _showApplePill(
      context,
      type: ToastType.info, // You can make a new type or use info
      title: title ?? "Alert",
      message: message,
      actionLabel: actionLabel,
      onActionTap: onActionTap,
    );
  }

  static void _showApplePill(
    BuildContext context, {
    required ToastType type,
    required String title,
    required String message,
    VoidCallback? onTap,
    String? actionLabel,
    VoidCallback? onActionTap,
  }) {
    _queue.add({
      'context': context,
      'type': type,
      'title': title,
      'message': message,
      'onTap': onTap,
      'actionLabel': actionLabel,
      'onActionTap': onActionTap,
    });
    
    _processQueue();
  }

  static void _processQueue() {
    if (_isShowing || _queue.isEmpty) return;
    _isShowing = true;

    final request = _queue.removeFirst();
    final context = request['context'] as BuildContext;
    final type = request['type'] as ToastType;
    final title = request['title'] as String;
    final message = request['message'] as String;
    final onTap = request['onTap'] as VoidCallback?;
    final actionLabel = request['actionLabel'] as String?;
    final onActionTap = request['onActionTap'] as VoidCallback?;

    if (!context.mounted) {
      _isShowing = false;
      _processQueue();
      return;
    }

    switch (type) {
      case ToastType.error:
        AppHaptics.warning();
        break;
      case ToastType.success:
        AppHaptics.heavyImpact();
        break;
      case ToastType.warning:
        AppHaptics.warning();
        break;
      case ToastType.info:
        AppHaptics.lightImpact();
        break;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => _ApplePillWidget(
        type: type,
        title: title,
        message: message,
        onTap: onTap,
        actionLabel: actionLabel,
        onActionTap: onActionTap,
        onDismiss: () {
          _overlayEntry?.remove();
          _overlayEntry = null;
          _isShowing = false;
          _processQueue();
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
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final VoidCallback onDismiss;

  const _ApplePillWidget({
    required this.type,
    required this.title,
    required this.message,
    this.onTap,
    this.actionLabel,
    this.onActionTap,
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
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 30,
                      spreadRadius: 0,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  clipBehavior: Clip.antiAlias,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(100),
                        color: isDark 
                            ? Colors.black.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.5),
                        border: Border.all(
                          color: isDark 
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.5),
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
                          if (widget.actionLabel != null && widget.onActionTap != null) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                widget.onActionTap!();
                                _dismiss();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A84FF).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  widget.actionLabel!,
                                  style: GoogleFonts.inter(
                                    color: const Color(0xFF0A84FF),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
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
