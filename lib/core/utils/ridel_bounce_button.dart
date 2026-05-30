import 'package:flutter/material.dart';
import 'package:ridel/core/utils/app_haptics.dart';

class RidelBounceButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleFactor;
  final bool isDisabled;
  final bool useHeavyHaptic;

  const RidelBounceButton({
    super.key,
    required this.child,
    required this.onTap,
    this.scaleFactor = 0.96,
    this.isDisabled = false,
    this.useHeavyHaptic = false,
  });

  @override
  State<RidelBounceButton> createState() => _RidelBounceButtonState();
}

class _RidelBounceButtonState extends State<RidelBounceButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 60),
      reverseDuration: const Duration(milliseconds: 200),
    );

    _scaleAnimation =
        Tween<double>(begin: 1.0, end: widget.scaleFactor).animate(
      CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeOutCubic),
    );

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.isDisabled || widget.onTap == null) return;
    if (widget.useHeavyHaptic) {
      AppHaptics.heavyImpact();
    } else {
      AppHaptics.keypadTap();
    }
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.isDisabled || widget.onTap == null) return;
    _controller.reverse().then((_) {
      if (mounted) widget.onTap!();
    });
  }

  void _handleTapCancel() {
    if (widget.isDisabled || widget.onTap == null) return;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      behavior: HitTestBehavior.opaque,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Opacity(
            opacity: widget.isDisabled ? 0.5 : 1.0,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
