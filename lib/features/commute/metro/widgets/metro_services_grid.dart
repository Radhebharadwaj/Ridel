import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import '../map/metro_map_screen.dart'; 
import 'nearest_station_card.dart'; 

class MetroServicesGrid extends StatefulWidget {
  const MetroServicesGrid({super.key});

  @override
  State<MetroServicesGrid> createState() => _MetroServicesGridState();
}

class _MetroServicesGridState extends State<MetroServicesGrid> {
  bool _isExpanded = false;

  void _toggleExpanded() {
    AppHaptics.lightImpact();
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final cardColor = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
    const accentColor = Color(0xFF00E5FF);

    List<Widget> serviceCards = [
      _buildIOSCardAction(
        context,
        Icons.map_rounded,
        "Network\nMap",
        cardColor,
        textColor,
        accentColor,
        onTap: () {
          RidelSheet.show(
            context,
            title: "Network Map",
            showBackButton: true,
            sheetColor: const Color(0xFF0B0E17),
            child: const MetroMapScreen(),
          );
        },
      ),
      const NearestStationCard(),
      _buildIOSCardAction(context, Icons.currency_rupee_rounded, "Check\nFares", cardColor, textColor, accentColor),
      _buildIOSCardAction(context, Icons.train_rounded, "First/Last\nTrain", cardColor, textColor, accentColor),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // METRO SERVICES Clickable Header
        InkWell(
          onTap: _toggleExpanded,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "METRO SERVICES",
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                Icon(
                  _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: isDark ? Colors.white54 : Colors.black54,
                  size: 20,
                )
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        AnimatedCrossFade(
          duration: const Duration(milliseconds: 350),
          sizeCurve: Curves.easeOutCubic,
          crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          
          // 🚀 FIRST CHILD: iOS App Switcher Style Horizontal Scroll
          firstChild: SizedBox(
            height: 120, // Fixed height for cards
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              // Ye physics iOS jaisa snap aur bounce deta hai
              physics: const BouncingScrollPhysics(parent: PageScrollPhysics()), 
              clipBehavior: Clip.none,
              itemCount: serviceCards.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) => serviceCards[index],
            ),
          ),
          
          // SECOND CHILD: Expanded Wrap Dropdown
          secondChild: SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: 14, 
              runSpacing: 14, 
              children: serviceCards,
            ),
          ),
        ),
      ],
    );
  }

  // 🚀 CUSTOM WIDGET: Scaling iOS Capsule Card
  Widget _buildIOSCardAction(BuildContext context, IconData icon, String label, Color bg, Color textColor, Color accentColor, {VoidCallback? onTap}) {
    return _IOSBouncyCard(
      onTap: onTap,
      child: Container(
        width: 90,
        height: 120,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(32), // 🚀 Capsule type roundness
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: accentColor),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: textColor, height: 1.2),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// 🚀 NAYA WIDGET: iOS Native click (Scale down) effect create karne ke liye
class _IOSBouncyCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _IOSBouncyCard({required this.child, this.onTap});

  @override
  State<_IOSBouncyCard> createState() => _IOSBouncyCardState();
}

class _IOSBouncyCardState extends State<_IOSBouncyCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        if (widget.onTap != null) {
          AppHaptics.lightImpact();
          widget.onTap!();
        }
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0, // 🚀 iOS click shrink effect
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32), // Capsule
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}