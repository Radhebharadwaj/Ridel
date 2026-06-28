// lib/core/utils/toast_service.dart

import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ridel/core/widgets/ridel_loading_dots.dart';

import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/main.dart';
import 'package:ridel/core/providers/app_navigation_provider.dart';
import 'package:ridel/core/widgets/branded_loader.dart';
enum ToastType { success, error, info, warning }

class ToastService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static OverlayEntry? _overlayEntry;
  static final Queue<Map<String, dynamic>> _queue = Queue<Map<String, dynamic>>();
  static bool _isShowing = false;
  static String? _currentShowingMessage;

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

  static void showWarning(BuildContext context, String message,
      {String? title, VoidCallback? onTap}) {
    _showApplePill(context,
        type: ToastType.warning,
        title: title ?? "Warning",
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

  static void showLoading(BuildContext context, String message,
      {String? title}) {
    _showApplePill(context,
        type: ToastType.info,
        title: title ?? "Loading",
        message: message,
        isLoading: true);
  }

  static void dismiss() {
    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      _isShowing = false;
      _currentShowingMessage = null;
      _processQueue();
    }
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

  static void showNearestTransportToast(
    BuildContext context, {
    required Function(String) onTapUpdateOrigin,
  }) {
    _showApplePill(
      context,
      type: ToastType.success,
      title: "",
      message: "",
      isDynamicTransportToast: true,
      onTapUpdateOrigin: onTapUpdateOrigin,
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
    bool isDynamicTransportToast = false,
    Function(String)? onTapUpdateOrigin,
    bool isLoading = false,
  }) {
    // 🚨 ANTI-SPAM FILTER: Do not queue if it's currently showing OR already in the queue
    if ((_isShowing && _currentShowingMessage == message) || 
        _queue.any((req) => req['message'] == message)) {
      return; // Silently ignore duplicate spam
    }

    _queue.add({
      'context': context,
      'type': type,
      'title': title,
      'message': message,
      'onTap': onTap,
      'actionLabel': actionLabel,
      'onActionTap': onActionTap,
      'isDynamicTransportToast': isDynamicTransportToast,
      'onTapUpdateOrigin': onTapUpdateOrigin,
      'isLoading': isLoading,
    });
    
    _processQueue();
  }

  static void _processQueue() {
    if (_isShowing || _queue.isEmpty) return;
    _isShowing = true;

    final request = _queue.removeFirst();
    final requestContext = request['context'] as BuildContext; // 🚨 Extract context
    final type = request['type'] as ToastType;
    final title = request['title'] as String;
    final message = request['message'] as String;
    final onTap = request['onTap'] as VoidCallback?;
    final actionLabel = request['actionLabel'] as String?;
    final onActionTap = request['onActionTap'] as VoidCallback?;

    final isDynamicTransportToast = request['isDynamicTransportToast'] as bool? ?? false;
    final onTapUpdateOrigin = request['onTapUpdateOrigin'] as Function(String)?;
    final isLoading = request['isLoading'] as bool? ?? false;

    _currentShowingMessage = message;

    // 🚨 CRITICAL FIX: Fallback to Overlay.of(requestContext) if navigatorKey fails
    final overlayState = navigatorKey.currentState?.overlay ?? Overlay.of(requestContext);

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
        isDynamicTransportToast: isDynamicTransportToast,
        onTapUpdateOrigin: onTapUpdateOrigin,
        isLoading: isLoading,
        onDismiss: () {
          _overlayEntry?.remove();
          _overlayEntry = null;
          _isShowing = false;
          _currentShowingMessage = null;
          _processQueue();
        },
      ),
    );
    overlayState.insert(_overlayEntry!);

    // 🚨 SAFETY FALLBACK: Guarantee toast queue unblocks even if animation stalls
    Future.delayed(const Duration(seconds: 8), () {
      if (_currentShowingMessage == message && _isShowing) {
        _overlayEntry?.remove();
        _overlayEntry = null;
        _isShowing = false;
        _currentShowingMessage = null;
        _processQueue();
      }
    });
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
  final bool isDynamicTransportToast;
  final Function(String)? onTapUpdateOrigin;
  final bool isLoading;

  const _ApplePillWidget({
    required this.type,
    required this.title,
    required this.message,
    required this.onDismiss,
    this.onTap,
    this.actionLabel,
    this.onActionTap,
    this.isDynamicTransportToast = false,
    this.onTapUpdateOrigin,
    this.isLoading = false,
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

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 🌟 Ab scale nahi badlega launch par, sirf slide hoke aayega (Zero Glitch)
      if (mounted) setState(() => _isEntering = false);
    });

    if (!widget.isLoading) {
      _startTimer();
    }
    globalTransportMode.addListener(_onTransportModeChanged);
  }

  void _onTransportModeChanged() {
    if (!_isEntering && mounted && !widget.isLoading) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 4), _dismiss);
  }

  void _dismiss() {
    if (!mounted) {
      widget.onDismiss();
      return;
    }
    setState(() {
      _isEntering = true;
      _scale = 0.85; // 🌟 Shrink only when leaving or tapped
    });
    Future.delayed(const Duration(milliseconds: 400), widget.onDismiss);
  }

  @override
  void dispose() {
    globalTransportMode.removeListener(_onTransportModeChanged);
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
    
    AppNavigationProvider? navProvider;
    try {
      navProvider = context.read<AppNavigationProvider>();
    } catch (_) {}
    
    final isMapScreen = navProvider?.currentIndex == 1;
    final bool shouldHide = isMapScreen && widget.type != ToastType.error && widget.type != ToastType.warning;

    double targetTop = 16.0;
    try {
      targetTop = MediaQuery.of(context).padding.top + 16;
    } catch (_) {}

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
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: shouldHide ? 0.0 : 1.0, // 🚨 Ensure errors are always visible
        child: AnimatedScale(
          scale: shouldHide ? 0.8 : _scale,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: IgnorePointer(
            ignoring: shouldHide, // 🚨 Ensure errors are clickable
            child: Align(
              alignment: Alignment.topCenter,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (widget.isDynamicTransportToast && widget.onTapUpdateOrigin != null) {
                    final transportMode = globalTransportMode.value;
                    final provider = navProvider;
                    String? name;
                    if (transportMode == 0) {
                      name = provider?.nearestMetroStation?['stop_name'];
                    } else {
                      name = provider?.nearestBusStop?['stop_name'];
                    }
                    if (name != null) {
                      widget.onTapUpdateOrigin!(_toTitleCase(name));
                    }
                  } else if (widget.onTap != null) {
                    widget.onTap!();
                  }
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
                constraints: const BoxConstraints(
                  maxWidth: 320,
                  minHeight: 44,
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
                    filter: ImageFilter.blur(sigmaX: 30.0, sigmaY: 30.0), // Match sheet exactly
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(100),
                        color: isDark 
                            ? const Color(0xFF0B0E17).withValues(alpha: 0.80) // Exact bottom sheet match
                            : Colors.white.withValues(alpha: 0.65), // Exact bottom sheet match
                        border: Border.all(
                          color: isDark 
                              ? Colors.white.withValues(alpha: 0.08) // Hairline subtle border
                              : Colors.black.withValues(alpha: 0.05),
                          width: 0.5,
                        ),
                      ),
                      child: ValueListenableBuilder<int>(
                        valueListenable: globalTransportMode,
                        builder: (context, transportMode, _) {
                          String dynamicTitle = widget.title;
                          String dynamicMessage = widget.message;
                          
                          bool isLoading = false;
                          
                          if (widget.isDynamicTransportToast) {
                            if (transportMode == 0) {
                              dynamicTitle = "Nearest Station";
                              final stopName = navProvider?.nearestMetroStation?['stop_name'];
                              if (stopName != null) {
                                dynamicMessage = _toTitleCase(stopName);
                              } else {
                                isLoading = true;
                              }
                            } else {
                              dynamicTitle = "Nearest Stop";
                              final stopName = navProvider?.nearestBusStop?['stop_name'];
                              if (stopName != null) {
                                dynamicMessage = _toTitleCase(stopName);
                              } else {
                                isLoading = true;
                              }
                            }
                          } else if (widget.title.startsWith("Nearest")) {
                            dynamicTitle = transportMode == 0 ? "Nearest Station" : "Nearest Stop";
                          }

                          Widget content;
                          if (isLoading) {
                            content = Row(
                              key: const ValueKey<String>("loading_state"),
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const BrandedLoader(isFullScreen: false),
                                const SizedBox(width: 8),
                                Text(
                                  "Finding nearest stop...",
                                  style: GoogleFonts.inter(
                                    color: isDark ? Colors.white54 : Colors.black54,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            );
                          } else {
                            content = Row(
                              key: ValueKey<String>("$dynamicTitle-$dynamicMessage"),
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (widget.isLoading)
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withValues(alpha: 0.15),
                                    ),
                                    child: const PremiumDotLoader(color: Colors.white),
                                  )
                                else
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
                                        dynamicTitle,
                                        style: GoogleFonts.inter(
                                          color:
                                              isDark ? Colors.white : Colors.black87,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.3,
                                          height: 1.1,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        dynamicMessage,
                                        style: GoogleFonts.inter(
                                          color: isDark
                                              ? Colors.white.withValues(alpha: 0.7)
                                              : Colors.black54,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          height: 1.2,
                                        ),
                                        maxLines: 2, // 🚨 CRITICAL: Changed from 1 to 2 to allow text wrapping
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
                            );
                          }

                          return AnimatedSize(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.center,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              layoutBuilder: (currentChild, previousChildren) => Stack(
                                alignment: Alignment.center,
                                children: <Widget>[
                                  ...previousChildren,
                                  if (currentChild != null) currentChild,
                                ],
                              ),
                              child: content,
                            ),
                          );
                        },
                      ),
                ), // Container
              ), // BackdropFilter
            ), // ClipRRect
          ), // Container
        ), // Material
      ), // GestureDetector
      ), // Align
      ), // IgnorePointer
      ), // AnimatedScale
      ), // AnimatedOpacity
    ); // AnimatedPositioned
  }
}
