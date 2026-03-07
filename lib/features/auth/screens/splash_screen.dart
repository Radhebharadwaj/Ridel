import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ridel/layout/main_layout.dart';
import 'package:ridel/features/auth/screens/login_screen.dart';
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
    // NOTE: Humne artificial 2-second delay hata diya hai taaki app fast load ho.
    // Hum bas 500ms ka buffer rakh rahe hain taaki transition jhatke se na ho.
    await Future.delayed(const Duration(milliseconds: 500));

    final session = Supabase.instance.client.auth.currentSession;

    if (mounted) {
      if (session != null) {
        // Already Logged In -> Home
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainLayout()));
      } else {
        // Not Logged In -> Login
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Pure Black Background
      body: Center(
        child: TweenAnimationBuilder(
          tween: Tween<double>(begin: 0.8, end: 1.0),
          duration: const Duration(milliseconds: 800),
          curve: Curves.elasticOut,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: const RidelLogo(size: 150), // Sirf tumhara Logo
            );
          },
        ),
      ),
    );
  }
}