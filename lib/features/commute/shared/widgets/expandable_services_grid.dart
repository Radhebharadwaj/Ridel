// lib/features/commute/shared/widgets/expandable_services_grid.dart

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart';

// 🚀 PREMIUM FLOATING SHADOW: Map grid ke upar population feel ke liye
class ServiceCardShadows {
  static List<BoxShadow> floating = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.35), // Pure floating deep shadow
      blurRadius: 30,
      offset: const Offset(0, 15),
      spreadRadius: 2,
    ),
    BoxShadow(
      color:
          const Color(0xFF00E5FF).withValues(alpha: 0.05), // Subtle accent tint
      blurRadius: 15,
      offset: const Offset(0, 10),
    ),
  ];
}

class ExpandableServicesGrid extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> services;
  final bool isDark;
  final Function(String id) onServiceTap;

  const ExpandableServicesGrid({
    super.key,
    required this.title,
    required this.services,
    required this.isDark,
    required this.onServiceTap,
  });

  @override
  State<ExpandableServicesGrid> createState() => _ExpandableServicesGridState();
}

class _ExpandableServicesGridState extends State<ExpandableServicesGrid> {
  bool _isExpanded = false;
  double _lastHapticOffset = 0.0;

  final Color _accentColor = const Color(0xFF00E5FF);

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final hintColor = widget.isDark ? Colors.grey : Colors.grey.shade600;

    // 🚀 RESPONSIVE UTILS: Calculate width universally for all screens
    final double screenWidth = MediaQuery.of(context).size.width;

    // Horizontal view item count based on size
    int horizontalCount = 3;
    if (screenWidth > 600) horizontalCount = 4; // Tablet peek

    const double hSpacing = 16.0;
    const double horizontalListPadding = 20.0;

    // 🌟 THE FIX: Universally calculated width for Horizontal items, based on old preference
    final double horizontalItemWidth = (screenWidth -
                (horizontalListPadding * 2) -
                ((horizontalCount - 1) * hSpacing)) /
            horizontalCount +
        40;

    // 🌟 HORIZONTAL VIEW (Collapsed State) - Pure Peek Effect
    Widget horizontalScrollView = ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent
          ],
          stops: [0.0, 0.05, 0.95, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: SizedBox(
        height: 150, // 🚀 Compacted Height
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (notification) {
              if ((notification.metrics.pixels - _lastHapticOffset).abs() >
                  40.0) {
                AppHaptics.selectionClick();
                _lastHapticOffset = notification.metrics.pixels;
              }
              return false;
            },
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding:
                  const EdgeInsets.symmetric(horizontal: horizontalListPadding),
              itemCount: widget.services.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: hSpacing),
              itemBuilder: (context, index) {
                // 🌟 FIX: Applied universal width calculation for peek effect
                return SizedBox(
                  width: horizontalItemWidth,
                  child: _buildServiceCard(
                      widget.services[index], textColor, hintColor),
                );
              },
            ),
          ),
        ),
      ),
    );

    // 🌟 GRID VIEW (Expanded State) - UNIVERSAL & OVERFLOW FREE
    Widget verticalGridView = LayoutBuilder(builder: (context, constraints) {
      // 🚀 THE BREAKPOINT FIX: Desktop par logic use nahi karenge, uske lie constraints pass honge
      // We use available screen width to decide grid count universally
      int columns = screenWidth < 600
          ? 2
          : (screenWidth < 900 ? 3 : 4); // Adaptive grid count
      double vSpacing = 16.0;

      // 🌟 THE LAYOUT FIX: Pure Wrap/Grid approach within SingleChildScrollView scope
      return SingleChildScrollView(
        physics:
            const NeverScrollableScrollPhysics(), // Scroll will be handled by parent sheet
        child: Padding(
          padding: EdgeInsets.only(
              left: 20.0,
              right: 20.0,
              bottom: (widget.services.length / columns).ceil() > 1 ? 40 : 20),
          child: GridView.builder(
            shrinkWrap: true, // 🚀 FIX 1: Allow it to take necessary height
            physics:
                const NeverScrollableScrollPhysics(), // 🚀 FIX 2: Let SingleChildScrollView/Parent Sheet handle scroll
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: hSpacing,
              mainAxisSpacing: vSpacing,
              // 🚀 FIXED CARD HEIGHT: Force premium aspect ratio to prevent bare large cards
              childAspectRatio: columns == 2 ? 1.0 : (columns == 3 ? 1.2 : 1.3),
            ),
            itemCount: widget.services.length,
            itemBuilder: (context, index) {
              return _buildServiceCard(
                  widget.services[index], textColor, hintColor);
            },
          ),
        ),
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            AppHaptics.mediumImpact();
            setState(() => _isExpanded = !_isExpanded);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.title.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 12, // Compact Title
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: widget.isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: widget.isDark ? Colors.white54 : Colors.black54,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 🚀 THE ANIMATION FIX: Ensure it can stretch
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 400),
          sizeCurve: Curves.easeOutQuart,
          crossFadeState: _isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: horizontalScrollView,
          secondChild: verticalGridView,
          alignment: Alignment.topCenter,
        ),
      ],
    );
  }

  Widget _buildServiceCard(
      Map<String, dynamic> service, Color textColor, Color hintColor) {
    return _ServiceCardItem(
      service: service,
      textColor: textColor,
      hintColor: hintColor,
      accentColor: _accentColor,
      onTap: () => widget.onServiceTap(service['id']),
    );
  }
}

// Dedicated Stateful Widget for individual card state
class _ServiceCardItem extends StatefulWidget {
  final Map<String, dynamic> service;
  final Color textColor;
  final Color hintColor;
  final Color accentColor;
  final VoidCallback onTap;

  const _ServiceCardItem({
    required this.service,
    required this.textColor,
    required this.hintColor,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_ServiceCardItem> createState() => _ServiceCardItemState();
}

class _ServiceCardItemState extends State<_ServiceCardItem> {
  bool isPressed = false;

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.toLowerCase().split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;

    return GestureDetector(
      onTapDown: (_) {
        AppHaptics.lightImpact();
        setState(() => isPressed = true);
      },
      onTapUp: (_) {
        AppHaptics.buttonClick();
        setState(() => isPressed = false);
        Future.delayed(const Duration(milliseconds: 150), widget.onTap);
      },
      onTapCancel: () => setState(() => isPressed = false),
      child: AnimatedScale(
        scale: isPressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutQuart,
        child: AnimatedOpacity(
          opacity: isPressed ? 0.8 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            // 🌟 FIXED PREMIUM ASPECT RATIO & SHADOW: Floating effect
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22), // More compacted
              boxShadow: isLightMode
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, spreadRadius: 0, offset: const Offset(0, 6))]
                  : ServiceCardShadows.floating, // 🚀 NEW PREMIUM SHADOW
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAliasWithSaveLayer,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Stack(
                  children: [
                    if (!isLightMode)
                      Positioned(
                        top: 2,
                        left: 16,
                        right: 16,
                        child: Container(
                          height: 15, // Refined Inner shine
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(100),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0.08),
                                Colors.white.withValues(alpha: 0)
                              ],
                            ),
                          ),
                        ),
                      ),
                    Container(
                      // 🌟 COMPACT padding to prevent stretched bare look
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        color: isLightMode ? Colors.white : null,
                        gradient: isLightMode ? null : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF161A25).withValues(alpha: 0.7),
                            const Color(0xFF161A25).withValues(alpha: 0.5),
                          ],
                        ),
                        border: Border.all(
                          color: isLightMode
                              ? Colors.black.withValues(alpha: 0.04)
                              : Colors.white.withValues(alpha: 0.04),
                          width: 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(9),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isLightMode
                                      ? Colors.black.withValues(alpha: 0.05)
                                      : Colors.white.withValues(alpha: 0.02),
                                ),
                                child: Icon(widget.service['icon'],
                                    color: const Color(0xFF00E5FF),
                                    size: 19), // Refined Icon
                              ),
                              Icon(Icons.arrow_forward_ios_rounded,
                                  color: isLightMode
                                      ? Colors.black26
                                      : widget.hintColor.withValues(alpha: 0.3),
                                  size: 13),
                            ],
                          ),
                          // Compact Spacing
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment
                                  .center, // Center text vertically
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 10),
                                Text(
                                  _toTitleCase(widget.service['name']),
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13, // Premium compact size
                                    color: isLightMode ? Colors.black87 : widget.textColor,
                                    letterSpacing: -0.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  widget.service['description'],
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.normal,
                                    fontSize: 10.5, // Refined description size
                                    color: isLightMode ? Colors.black54 : Colors.grey.shade400,
                                    letterSpacing: -0.1,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
