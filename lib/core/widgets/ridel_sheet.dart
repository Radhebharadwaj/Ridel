// lib/core/widgets/ridel_sheet.dart

import 'dart:ui'; // 🚀 Added for ImageFilter
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/widgets/ridel_liquid_button.dart';

class RidelSheet extends StatefulWidget {
  final String title;
  final Widget child;
  final bool showBackButton;
  final bool showCloseButton;
  final bool showFullScreenButton;
  final bool customHeader;
  final Color? sheetColor;

  const RidelSheet({
    super.key,
    required this.title,
    required this.child,
    this.showBackButton = false,
    this.showCloseButton = false,
    this.showFullScreenButton = false,
    this.customHeader = false,
    this.sheetColor,
  });

  static Future<T?> show<T>(BuildContext context,
      {required String title,
      required Widget child,
      bool showBackButton = false,
      bool showCloseButton = false,
      bool showFullScreenButton = false,
      bool customHeader = false,
      bool enableDrag = true,
      Color? sheetColor}) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    if (isDesktop && kIsWeb) {
      return showGeneralDialog<T>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'RidelSheet',
        routeSettings: RouteSettings(name: '/ridel_sheet_$title'),
        barrierColor: Colors.black.withValues(alpha: 0.4),
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (context, animation, secondaryAnimation) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final bgColor =
              sheetColor ?? Theme.of(context).scaffoldBackgroundColor;
          final textColor = isDark ? Colors.white : Colors.black;

          final btnGlassColor = isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05);

          return Align(
            alignment: Alignment.centerRight,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeInOutCubic,
              width: 400,
              height: MediaQuery.of(context).size.height - 48,
              margin: const EdgeInsets.only(right: 24, top: 24, bottom: 24),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 40,
                      spreadRadius: 5)
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Column(
                    children: [
                      if (!customHeader)
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 24, right: 16, top: 20, bottom: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (showBackButton)
                                RidelLiquidButton(
                                  width: 44,
                                  height: 44,
                                  shapeType: LiquidShapeType.circle,
                                  glassTint: btnGlassColor,
                                  onTap: () {
                                    Navigator.of(context, rootNavigator: true)
                                        .pop();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 2.0),
                                    child: Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        size: 18,
                                        color: textColor),
                                  ),
                                ),
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    style: GoogleFonts.inter(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: textColor),
                                    textAlign: showBackButton
                                        ? TextAlign.center
                                        : TextAlign.left,
                                  ),
                                ),
                              ),
                              if (showCloseButton || showFullScreenButton)
                                RidelLiquidButton(
                                  width: 44,
                                  height: 44,
                                  shapeType: LiquidShapeType.circle,
                                  glassTint: btnGlassColor,
                                  onTap: () {
                                    Navigator.of(context, rootNavigator: true)
                                        .pop();
                                  },
                                  child: Icon(Icons.close_rounded,
                                      size: 20, color: textColor),
                                ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: child,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return ScaleTransition(
            scale:
                CurvedAnimation(parent: animation, curve: Curves.easeOutQuint),
            alignment: Alignment.centerRight,
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
      );
    } else {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        enableDrag: enableDrag,
        transitionAnimationController: AnimationController(
            vsync: Navigator.of(context),
            duration: const Duration(
                milliseconds: 350)), // 🚀 Slightly smoother duration
        builder: (context) => RidelSheet(
            title: title,
            showBackButton: showBackButton,
            showCloseButton: showCloseButton,
            showFullScreenButton: showFullScreenButton,
            customHeader: customHeader,
            sheetColor: sheetColor,
            child: child),
      );
    }
  }

  @override
  State<RidelSheet> createState() => _RidelSheetState();
}

class _RidelSheetState extends State<RidelSheet> {
  bool _isFullScreen = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const double headerHeight = 85.0; // Perfect header zone

    final double screenHeight = MediaQuery.of(context).size.height;
    final double currentHeight =
        _isFullScreen ? screenHeight : (screenHeight * 0.85);

    final finalBgColor =
        widget.sheetColor ?? Theme.of(context).scaffoldBackgroundColor;
    final solidSealColor =
        widget.sheetColor ?? Theme.of(context).scaffoldBackgroundColor;

    final bool isCustomDark = widget.sheetColor != null &&
        widget.sheetColor!.computeLuminance() < 0.5;
    final textColor = (isDark || isCustomDark) ? Colors.white : Colors.black;

    final glassBtnColor = (isDark || isCustomDark)
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final iconColor = (isDark || isCustomDark) ? Colors.white : Colors.black87;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeInOutQuart,
      height: currentHeight,
      decoration: BoxDecoration(
        color: finalBgColor,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(_isFullScreen ? 0 : 35)),
        border: Border.all(color: solidSealColor, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.15),
              blurRadius: 40,
              spreadRadius: 2,
              offset: const Offset(0, -2))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // ================= CONTENT =================
          Positioned.fill(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: widget.child,
            ),
          ),

          // ================= PREMIUM GLASS HEADER =================
          if (!widget.customHeader)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: headerHeight +
                  30, // 🚀 Extra height to allow the smooth blur fade
              child: RepaintBoundary(
                child: ClipRect(
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    // 🚀 The Mask that makes the bottom of the header transparent (fade out blur)
                    return const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Colors.white, Colors.transparent],
                      stops: [0.0, 0.65, 1.0],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                        sigmaX: 20, sigmaY: 20), // 💎 Heavy Apple glass blur
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 850),
                      curve: Curves.easeInOutQuart,
                      alignment: Alignment.topCenter,
                      padding: EdgeInsets.fromLTRB(
                          20,
                          _isFullScreen
                              ? MediaQuery.of(context).padding.top + 10
                              : 20,
                          20,
                          0),
                      decoration: BoxDecoration(
                        // 🚀 Smooth Color Gradient overlay
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            finalBgColor, // 100% Solid at the very top
                            finalBgColor.withValues(alpha: 0.85), // Fading mid
                            finalBgColor.withValues(
                                alpha: 0.0) // Transparent bottom
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 850),
                        switchInCurve: Curves.easeInOutQuart,
                        switchOutCurve: Curves.easeInOutQuart,
                        child: Row(
                          key: ValueKey(isDark),
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                          SizedBox(
                              width: 44,
                              height: 44,
                              child: widget.showBackButton
                                  ? RidelLiquidButton(
                                      width: 44,
                                      height: 44,
                                      shapeType: LiquidShapeType.circle,
                                      glassTint: glassBtnColor,
                                      onTap: () => Navigator.pop(context),
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(right: 2.0),
                                        child: Icon(
                                            Icons.arrow_back_ios_new_rounded,
                                            color: iconColor,
                                            size: 18),
                                      ),
                                    )
                                  : null),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(widget.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: GoogleFonts.inter(
                                      color: textColor,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing:
                                          -0.3)), // 🚀 Refined typography
                            ),
                          ),
                          SizedBox(
                              width: 44,
                              height: 44,
                              child: widget.showFullScreenButton
                                  ? RidelLiquidButton(
                                      width: 44,
                                      height: 44,
                                      shapeType: LiquidShapeType.circle,
                                      glassTint: glassBtnColor,
                                      onTap: () => setState(
                                          () => _isFullScreen = !_isFullScreen),
                                      child: Icon(
                                          _isFullScreen
                                              ? Icons.fullscreen_exit_rounded
                                              : Icons.fullscreen_rounded,
                                          color: iconColor,
                                          size: 22),
                                    )
                                  : widget.showCloseButton
                                      ? RidelLiquidButton(
                                          width: 44,
                                          height: 44,
                                          shapeType: LiquidShapeType.circle,
                                          glassTint: glassBtnColor,
                                          onTap: () => Navigator.pop(context),
                                          child: Icon(Icons.close_rounded,
                                              color: iconColor, size: 20),
                                        )
                                      : null),
                        ],
                        ),
                      ),
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

// 🚀 REUSABLE UNIVERSAL GLASS SEARCH BAR COMPONENT
class RidelGlassSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final Widget? trailing;
  final Color? accentColor;

  const RidelGlassSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
    this.trailing,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = accentColor ?? const Color(0xFF00E5FF);

    return Container(
      height: 48.0,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2129) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.05),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth < 240 ? 240 : constraints.maxWidth,
              ),
              child: TextField(
                controller: controller,
                textAlignVertical: TextAlignVertical.center,
                onChanged: onChanged,
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: iconColor,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded, size: 24.0, color: iconColor),
                  prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  suffixIcon: controller.text.isNotEmpty
                      ? GestureDetector(
                          onTap: onClear,
                          child: Container(
                            color: Colors.transparent,
                            child: Icon(
                              Icons.close_rounded,
                              color: isDark ? Colors.white54 : Colors.black54,
                              size: 18,
                            ),
                          ),
                        )
                      : trailing,
                  suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  hintText: hintText,
                  hintStyle: GoogleFonts.inter(
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
