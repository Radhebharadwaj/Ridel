import 'package:flutter/material.dart';

class AnimatedSwayingPin extends StatefulWidget {
  const AnimatedSwayingPin({super.key});

  @override
  State<AnimatedSwayingPin> createState() => _AnimatedSwayingPinState();
}

class _AnimatedSwayingPinState extends State<AnimatedSwayingPin>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: -6.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _animation.value),
          child: child,
        );
      },
      child: Image.asset(
        'assets/images/custom_pin.png',
        width: 48,
        height: 48,
        alignment: Alignment.bottomCenter,
      ),
    );
  }
}
