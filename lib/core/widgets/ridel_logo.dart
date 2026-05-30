import 'package:flutter/material.dart';

class RidelLogo extends StatelessWidget {
  final double size;
  final Color? color; // Make nullable to use theme default

  const RidelLogo({
    super.key,
    this.size = 120,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ Logic: Agar color diya hai to wo use karo, warna Theme se uthao
    final defaultColor = Theme.of(context).iconTheme.color;
    
    return Icon(
      Icons.directions_bike_rounded, 
      size: size,
      color: color ?? defaultColor, // Uses theme color in Light mode (Black)
    );
  }
}