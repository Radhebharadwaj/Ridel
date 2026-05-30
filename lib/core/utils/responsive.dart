import 'package:flutter/material.dart';

class Responsive extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  const Responsive({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  // 🚀 Har file me check karne ke liye shortcuts
  static bool isMobile(BuildContext context) => MediaQuery.of(context).size.width < 650;
  static bool isTablet(BuildContext context) => MediaQuery.of(context).size.width >= 650 && MediaQuery.of(context).size.width < 1024;
  static bool isDesktop(BuildContext context) => MediaQuery.of(context).size.width >= 1024;

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    
    // Agar Desktop hai
    if (size.width >= 1024) {
      return desktop;
    }
    // Agar Tablet hai aur humne tablet widget diya hai
    else if (size.width >= 650 && tablet != null) {
      return tablet!;
    }
    // Baaki sab cases me Mobile
    else {
      return mobile;
    }
  }
}