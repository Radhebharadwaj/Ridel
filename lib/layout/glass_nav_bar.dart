import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:ridel/main.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:google_fonts/google_fonts.dart';

class GlassNavBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTabSelected;
  final VoidCallback onProfileTapped;
  final Function(bool isMetro)? onTransportModeChanged;

  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onProfileTapped,
    this.onTransportModeChanged,
  });

  @override
  State<GlassNavBar> createState() => _GlassNavBarState();
}

class _GlassNavBarState extends State<GlassNavBar> {
  int _activeSlabIndex = 0;
  bool _isMoving = false;

  // --- swipe tracking ---
  double _dragStartX = 0;
  double _dragDeltaX = 0;
  double _trackWidth = 0;

  @override
  void initState() {
    super.initState();
    _activeSlabIndex = globalTransportMode.value == 0 ? 0 : 1;
  }

  void _onSegmentTapped(int index) {
    if (_activeSlabIndex == index) return;

    AppHaptics.switchToggle(); // Crisp hardware mechanical click feedback

    setState(() {
      _isMoving = true;
      _activeSlabIndex = index;
    });

    // Animation scale reset logic
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _isMoving = false);
    });

    if (index == 0) {
      globalTransportMode.value = 0;
      globalSearchSheetOpen.value = true;
      if (widget.onTransportModeChanged != null) {
        widget.onTransportModeChanged!(true);
      }
    } else if (index == 1) {
      globalTransportMode.value = 1;
      globalSearchSheetOpen.value = true;
      if (widget.onTransportModeChanged != null) {
        widget.onTransportModeChanged!(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const double elementHeight = 42.0;

    const Color metroColor = Color(0xFF00D1FF);
    const Color busColor = Color(0xFFFF9F0A);
    final Color inactiveColor = Colors.white.withValues(alpha: 0.45);

    // Core Interior Content (Buttons & Sliders)
    Widget navBarContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      child: Row(
        children: [
          // 1. THE SWITCHER (swipeable)
          Flexible(
            flex: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 172),
              child: GestureDetector(
                onHorizontalDragStart: (details) {
                  _dragStartX = details.globalPosition.dx;
                  _dragDeltaX = 0;
                },
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _dragDeltaX = details.globalPosition.dx - _dragStartX;
                  });
                },
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  final threshold = _trackWidth * 0.3;

                  if (velocity.abs() > 300 || _dragDeltaX.abs() > threshold) {
                    final targetIndex = _dragDeltaX > 0 ? 1 : 0;
                    if (targetIndex != _activeSlabIndex) {
                      _onSegmentTapped(targetIndex);
                    }
                  }
                  setState(() {
                    _dragDeltaX = 0;
                  });
                },
                child: Container(
                  height: elementHeight,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.42)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _trackWidth = constraints.maxWidth;
                      final thumbWidth = constraints.maxWidth / 2;

                      return Stack(
                        children: [
                          /// ACTIVE GLASS THUMB
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            left: _activeSlabIndex == 0 ? 0 : thumbWidth,
                            top: 0,
                            bottom: 0,
                            child: AnimatedScale(
                              duration: const Duration(milliseconds: 120),
                              curve: Curves.easeOutCubic,
                              scale: _isMoving ? 0.97 : 1,
                              child: Container(
                                width: thumbWidth,
                                padding: const EdgeInsets.all(2),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(100),
                                    color: isDark ? null : Colors.white,
                                    gradient: isDark
                                        ? LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.white
                                                  .withValues(alpha: 0.11),
                                              Colors.white
                                                  .withValues(alpha: 0.05),
                                            ],
                                          )
                                        : null,
                                    boxShadow: [
                                      BoxShadow(
                                        color: isDark
                                            ? Colors.black
                                                .withValues(alpha: 0.22)
                                            : Colors.black
                                                .withValues(alpha: 0.04),
                                        blurRadius: isDark ? 8 : 18.0,
                                        offset: isDark
                                            ? const Offset(0, 2)
                                            : const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          /// LABELS (Original Clean ChatGPT Animation Restored)
                          Row(
                            children: [
                              _buildToggleTab(
                                title: "Metro",
                                active: _activeSlabIndex == 0,
                                activeColor:
                                    isDark ? metroColor : Colors.black87,
                                isDark: isDark,
                                onTap: () => _onSegmentTapped(0),
                              ),
                              _buildToggleTab(
                                title: "Bus",
                                active: _activeSlabIndex == 1,
                                activeColor: isDark ? busColor : Colors.black87,
                                isDark: isDark,
                                onTap: () => _onSegmentTapped(1),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          const Spacer(flex: 1),

          // 2. PROFILE ICON
          _CircularIconButton(
            size: elementHeight,
            icon: Icons.person_rounded,
            iconColor: isDark ? inactiveColor : Colors.grey.shade800,
            isActive: false,
            onTap: widget.onProfileTapped,
          ),

          const Spacer(flex: 1),

          // 3. SEARCH ICON
          _CircularIconButton(
            size: elementHeight,
            icon: CupertinoIcons.search,
            iconColor: widget.currentIndex == 1
                ? (isDark ? metroColor : Colors.black87)
                : (isDark ? inactiveColor : Colors.grey.shade800),
            isActive: widget.currentIndex == 1,
            onTabSelected: widget.onTabSelected,
          ),
        ],
      ),
    );

    return SafeArea(
      bottom: true,
      top: false,
      child: AnimatedSlide(
        offset: widget.currentIndex == 1 ? const Offset(0, 1.5) : Offset.zero,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(
                  bottom: 24.0, left: 28.0, right: 28.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(38.0),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.40)
                        : Colors.black.withValues(alpha: 0.08),
                    blurRadius: isDark ? 30 : 32,
                    spreadRadius: isDark ? -2 : 8,
                    offset:
                        isDark ? const Offset(0, 15) : const Offset(0, 12),
                  ),
                ],
              ),
              child: RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(38.0),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                    child: Container(
                      height: 56.0,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(38.0),
                        color: isDark
                            ? null
                            : Colors.white.withValues(alpha: 0.7),
                        gradient: isDark
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  const Color(0xFF20232C)
                                      .withValues(alpha: 0.85),
                                  const Color(0xFF20232C)
                                      .withValues(alpha: 0.65),
                                ],
                              )
                            : null,
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.04),
                          width: 1.0,
                        ),
                      ),
                      child: navBarContent,
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

  // 🚀 CLEAN TEXT STYLE ANIMATION (NO SIZE POP)
  Widget _buildToggleTab({
    required String title,
    required bool active,
    required Color activeColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final inactiveColor =
        isDark ? Colors.white.withValues(alpha: 0.48) : Colors.black54;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            style: GoogleFonts.inter(
              color: active ? activeColor : inactiveColor,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              fontSize: 14,
              letterSpacing: 0.1,
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

class _CircularIconButton extends StatefulWidget {
  final double size;
  final IconData icon;
  final Color iconColor;
  final bool isActive;
  final VoidCallback? onTap;
  final Function(int)? onTabSelected;

  const _CircularIconButton({
    required this.size,
    required this.icon,
    required this.iconColor,
    required this.isActive,
    this.onTap,
    this.onTabSelected,
  });

  @override
  State<_CircularIconButton> createState() => _CircularIconButtonState();
}

class _CircularIconButtonState extends State<_CircularIconButton> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails details) {
    AppHaptics.lightImpact();
    setState(() => _scale = 0.86);
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _scale = 1.0);
    AppHaptics.buttonClick();

    if (widget.onTap != null) {
      Future.microtask(widget.onTap!);
    } else if (widget.onTabSelected != null) {
      Future.microtask(() => widget.onTabSelected!(1));
    }
  }

  void _onTapCancel() => setState(() => _scale = 1.0);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.isActive
                ? (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05))
                : Colors.transparent,
            shape: BoxShape.circle,
            border: widget.isActive
                ? Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.05),
                    width: 1.0,
                  )
                : null,
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: isDark
                          ? widget.iconColor.withValues(alpha: 0.15)
                          : Colors.black.withValues(alpha: 0.04),
                      blurRadius: isDark ? 8 : 18.0,
                      offset: isDark ? Offset.zero : const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Icon(widget.icon,
              color: widget.iconColor, size: 22), // 🚀 Optimal Size 22 Kept
        ),
      ),
    );
  }
}
