import 'package:flutter/material.dart';

class RidelPremiumLoader extends StatefulWidget {
  final double size;
  final Color primaryColor;
  final Color secondaryColor;
  final bool isDark;

  const RidelPremiumLoader({
    super.key,
    this.size = 40.0,
    this.primaryColor = const Color(0xFF00E5FF), // Default Cyan for Metro
    this.secondaryColor = const Color(0xFF8B2CF5), // Deep Purple
    this.isDark = true,
  });

  @override
  State<RidelPremiumLoader> createState() => _RidelPremiumLoaderState();
}

class _RidelPremiumLoaderState extends State<RidelPremiumLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final innerColor = widget.isDark ? const Color(0xFF161A25) : Colors.white;

    return RotationTransition(
      turns: _controller,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              widget.primaryColor.withValues(alpha: 0.1),
              widget.primaryColor.withValues(alpha: 0.5),
              widget.secondaryColor,
              widget.primaryColor,
            ],
            stops: const [0.0, 0.5, 0.8, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: widget.primaryColor.withValues(alpha: 0.4),
              blurRadius: 15,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(3.0), // Thickness of the glowing ring
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: innerColor, // Inner mask to make it look like a ring
            ),
          ),
        ),
      ),
    );
  }
}
