import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ridel/layout/main_layout.dart';
import 'package:ridel/features/auth/screens/login_screen.dart';
import 'package:ridel/features/auth/services/auth_service.dart';
import 'package:ridel/core/widgets/ridel_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Smooth transition buffer
    await Future.delayed(const Duration(milliseconds: 800));

    final session = Supabase.instance.client.auth.currentSession;

    if (!mounted) return;

    if (session != null) {
      // 🚀 Clean call to unified Token Manager
      AuthService().setupAndSaveDeviceToken();
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const MainLayout()));
    } else {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E17), // Matched with app theme
      body: Center(
        child: TweenAnimationBuilder(
          tween: Tween<double>(begin: 0.8, end: 1.0),
          duration: const Duration(milliseconds: 800),
          curve: Curves.elasticOut,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: const RidelLogo(size: 220),
            );
          },
        ),
      ),
    );
  }
}
