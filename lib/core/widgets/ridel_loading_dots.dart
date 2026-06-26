import 'dart:math' as math;
import 'package:flutter/material.dart';

class PremiumDotLoader extends StatefulWidget {
  final Color? color;

  const PremiumDotLoader({super.key, this.color});

  @override
  State<PremiumDotLoader> createState() => _PremiumDotLoaderState();
}

class _PremiumDotLoaderState extends State<PremiumDotLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _anim1;
  late Animation<double> _anim2;
  late Animation<double> _anim3;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _anim1 = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeInOutSine),
      ),
    );
    _anim2 = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.15, 0.75, curve: Curves.easeInOutSine),
      ),
    );
    _anim3 = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.9, curve: Curves.easeInOutSine),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildDot(Animation<double> animation, Color dotColor) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final double sinValue = math.sin(animation.value * math.pi);
        return Transform.translate(
          offset: Offset(0, -6 * sinValue),
          child: Transform.scale(
            scale: 1.0 + (0.3 * sinValue),
            child: child,
          ),
        );
      },
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: dotColor,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color defaultColor =
        brightness == Brightness.dark ? Colors.white : Colors.black87;
    final Color dotColor = widget.color ?? defaultColor;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildDot(_anim1, dotColor),
        const SizedBox(width: 4),
        _buildDot(_anim2, dotColor),
        const SizedBox(width: 4),
        _buildDot(_anim3, dotColor),
      ],
    );
  }
}
