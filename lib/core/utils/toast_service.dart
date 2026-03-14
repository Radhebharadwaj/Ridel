import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_haptics.dart'; 

class ToastService {
  static OverlayEntry? _overlayEntry;

  static void showSuccess(BuildContext context, String message) {
    _show(context, message, type: _ToastType.success);
  }

  static void showError(BuildContext context, String message) {
    _show(context, message, type: _ToastType.error);
  }

  static void showInfo(BuildContext context, String message) {
    _show(context, message, type: _ToastType.info);
  }

  static void _show(BuildContext context, String message, {required _ToastType type}) {
    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    }

    AppHaptics.lightImpact(); // Haptic feedback on trigger

    _overlayEntry = OverlayEntry(
      builder: (context) => _GlassToastWidget(
        message: message,
        type: type,
        onDismiss: () {
          _overlayEntry?.remove();
          _overlayEntry = null;
        },
      ),
    );

    // Overlay screen par insert karo
    Overlay.of(context).insert(_overlayEntry!);
  }
}

enum _ToastType { success, error, info }

class _GlassToastWidget extends StatefulWidget {
  final String message;
  final _ToastType type;
  final VoidCallback onDismiss;

  const _GlassToastWidget({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<_GlassToastWidget> createState() => _GlassToastWidgetState();
}

class _GlassToastWidgetState extends State<_GlassToastWidget> {
  bool _isBottom = false;
  bool _isDragging = false;
  double _dragOffsetX = 0;
  double _dragOffsetY = 0;
  bool _isExiting = false;
  bool _isEntering = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Entry Animation trigger karna next frame me
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isEntering = false;
        });
        _startTimer();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ⏱️ Smart Timer Logic
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 4), _autoDismiss);
  }

  void _autoDismiss() {
    if (_isBottom) {
      _dismissDown();
    } else {
      _dismissUp();
    }
  }

  // 🚀 Swipe Dismiss Actions
  void _dismissUp() {
    if (!mounted || _isExiting) return;
    setState(() {
      _isExiting = true;
      _dragOffsetY = -200; // Slide up off-screen
    });
    _finishDismiss();
  }

  void _dismissDown() {
    if (!mounted || _isExiting) return;
    setState(() {
      _isExiting = true;
      _dragOffsetY = 200; // Slide down off-screen
    });
    _finishDismiss();
  }

  void _dismissSide(double velocityX) {
    if (!mounted || _isExiting) return;
    setState(() {
      _isExiting = true;
      _dragOffsetX = velocityX >= 0 ? 500 : -500; // Left ya Right slide
    });
    _finishDismiss();
  }

  void _finishDismiss() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    Color iconColor;
    IconData icon;
    
    switch (widget.type) {
      case _ToastType.success:
        icon = Icons.check_circle_rounded;
        iconColor = const Color(0xFF00E5FF); // Neon Cyan
        break;
      case _ToastType.error:
        icon = Icons.error_rounded;
        iconColor = Colors.redAccent;
        break;
      case _ToastType.info:
      default:
        icon = Icons.info_rounded;
        iconColor = isDark ? Colors.white : Colors.black;
        break;
    }

    // Ekdum perfect placement without status bar overlapping
    double screenHeight = MediaQuery.of(context).size.height;
    double topResting = MediaQuery.of(context).padding.top + 15;
    if (topResting < 40) topResting = 50; 
    double bottomResting = screenHeight - MediaQuery.of(context).padding.bottom - 100;

    // Yahan target position calculate ho rahi hai
    double targetTop = _isBottom ? bottomResting : topResting;
    
    if (_isEntering) {
      targetTop = -150; // Aasmaan se girega
    } else if (_isExiting && _dragOffsetX == 0) {
      targetTop = _dragOffsetY < 0 ? -150 : screenHeight + 50;
    } else {
      targetTop += _dragOffsetY; // Finger tracking
    }

    // Side swipe math
    double targetLeft = 20 + _dragOffsetX;
    double targetRight = 20 - _dragOffsetX;

    return AnimatedPositioned(
      // Dragging ke time pe 0 duration taaki perfectly finger track kare
      duration: Duration(milliseconds: _isDragging ? 0 : 400),
      curve: _isDragging ? Curves.linear : Curves.easeOutCubic,
      top: targetTop,
      left: targetLeft,
      right: targetRight,
      child: GestureDetector(
        onPanStart: (_) {
          _timer?.cancel(); // Drag start hote hi timer roko
          setState(() => _isDragging = true);
        },
        onPanUpdate: (details) {
          setState(() {
            _dragOffsetX += details.delta.dx;
            _dragOffsetY += details.delta.dy;
          });
        },
        onPanEnd: (details) {
          setState(() => _isDragging = false);
          
          double vX = details.velocity.pixelsPerSecond.dx;
          double vY = details.velocity.pixelsPerSecond.dy;

          // 1. Horizontal Swipe (Fling) -> Dismiss
          if (_dragOffsetX.abs() > 80 || vX.abs() > 300) {
            _dismissSide(vX >= 0 ? 1 : -1);
            return;
          }

          // 2. Vertical Logic Tree
          if (!_isBottom) {
            // Hum abhi TOP par hain
            if (_dragOffsetY < -40 || vY < -300) {
              _dismissUp();
            } else if (_dragOffsetY > 80 || vY > 300) {
              AppHaptics.mediumImpact();
              _isBottom = true; // Send to Bottom
              _dragOffsetY = 0;
              _dragOffsetX = 0;
              _startTimer();
            } else {
              _dragOffsetY = 0;
              _dragOffsetX = 0;
              _startTimer();
            }
          } else {
            // Hum abhi BOTTOM par hain
            if (_dragOffsetY > 40 || vY > 300) {
              _dismissDown();
            } else if (_dragOffsetY < -80 || vY < -300) {
              AppHaptics.mediumImpact();
              _isBottom = false; // Send to Top
              _dragOffsetY = 0;
              _dragOffsetX = 0;
              _startTimer();
            } else {
              _dragOffsetY = 0;
              _dragOffsetX = 0;
              _startTimer();
            }
          }
        },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _isExiting || _isEntering ? 0.0 : 1.0,
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark 
                        ? const Color(0xFF1C1C1E).withOpacity(0.85) 
                        : Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.05),
                      width: 1
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: iconColor.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: iconColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: GoogleFonts.inter(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2, // Chota notification
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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