import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ridel/core/widgets/navigation_menu.dart';
import 'package:ridel/features/auth/screens/login_screen.dart';

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
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const NavigationMenu()));
      } else {
        // Not Logged In -> Login
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Matching Native Splash Background
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo Animation (Optional: Pulse effect)
            TweenAnimationBuilder(
              tween: Tween<double>(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  // Yahan hamne tumhara naya transparent logo lagaya hai
                  child: Image.asset(
                    'assets/icon/logo.png',
                    width: 150, // Size adjust kar sakte ho
                    height: 150,
                  ),
                );
              },
            ),
            const SizedBox(height: 30),
            // Loader color changed to Red/White to match theme
            const CircularProgressIndicator(
              color: Color(0xFF181818), // Red color match
              backgroundColor: Colors.white24,
              strokeWidth: 3,
            ),
          ],
        ),
      ),
    );
  }
}