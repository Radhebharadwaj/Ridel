import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RidelServiceCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback? onTap;
  final bool isLoading;
  final Color? textColor;

  const RidelServiceCard({
    super.key,
    required this.icon,
    required this.label,
    required this.accentColor,
    this.onTap,
    this.textColor,
    this.isLoading = false,
  });

  @override
  State<RidelServiceCard> createState() => _RidelServiceCardState();
}

class _RidelServiceCardState extends State<RidelServiceCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final displayTextColor =
        widget.textColor ?? (isDark ? Colors.white : Colors.black);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        if (widget.onTap != null) {
          // 🚀 Haptics wahi rakhe hain jaise tune note me bola tha
          widget.onTap!();
        }
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        // 🚀 Premium shrink effect thoda sa refine kiya (0.94)
        scale: _isPressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: SizedBox(
          // 🚀 EXACT ORIGINAL SHAPE & SIZE
          width: 90,
          height: 120,
          child: Container(
            decoration: BoxDecoration(
              // 🚀 MATTE PILL BACKGROUND
              color: isDark ? const Color(0xFF1E2129) : Colors.white,
              borderRadius: BorderRadius.circular(32), // Exact purana radius
              border: Border.all(
                // 🚀 EDGE SHINE (1px transparent white border)
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.05),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12), // Exact purani padding
                  decoration: BoxDecoration(
                    // 🚀 INSET DEPTH COLOR FOR ICON
                    color: isDark
                        ? const Color(0xFF121419)
                        : widget.accentColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.transparent,
                    ),
                  ),
                  child: widget.isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24, // Exact purana size
                          child: CircularProgressIndicator(
                              color: widget.accentColor, strokeWidth: 2))
                      : Icon(widget.icon, size: 24, color: widget.accentColor),
                ),
                const SizedBox(height: 12), // Exact purana spacing
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                      fontSize: 11, // Exact purana font size
                      fontWeight: FontWeight.w600,
                      color: displayTextColor,
                      height: 1.2),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
