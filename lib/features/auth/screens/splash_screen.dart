import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ridel/layout/main_layout.dart';
import 'package:ridel/features/auth/screens/login_screen.dart';
import 'package:ridel/features/auth/services/auth_service.dart';

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
    await Future.delayed(
        const Duration(milliseconds: 1000)); // Slightly increased for animation

    final session = Supabase.instance.client.auth.currentSession;

    if (!mounted) return;

    if (session != null) {
      // 🚀 Clean call to unified Token Manager
      AuthService().setupAndSaveDeviceToken();
      Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const MainLayout(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 500),
          ));
    } else {
      Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const LoginScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 500),
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 🚀 PREVENT FLICKER: Set base color
      backgroundColor: const Color(0xFF0B0E17),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // 🚀 PREMIUM WEB GLOW BACKGROUND
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.8,
            colors: [
              const Color(0xFF00E5FF)
                  .withValues(alpha: 0.15), // Subtle Cyan center glow
              const Color(0xFF0B0E17), // Deep Dark Navy edges
            ],
            stops: const [0.0, 1.0],
          ),
        ),
        child: Center(
          child: TweenAnimationBuilder(
            tween: Tween<double>(begin: 0.7, end: 1.0),
            duration: const Duration(milliseconds: 900),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: SizedBox(
                  width: 120,
                  height: 120,
                  child: CustomPaint(
                    painter: RidelLogoPainter(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class RidelLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    
    canvas.save();
    // Add a strict 15% padding on all sides to prevent stroke bleeding
    canvas.translate(w * 0.15, h * 0.15);
    canvas.scale(0.7, 0.7); // Shrink the drawing area to 70%

    final path = Path();
    final backWheel = Offset(w * 0.25, h * 0.7);
    final frontWheel = Offset(w * 0.75, h * 0.7);
    final radius = w * 0.2;

    path.addOval(Rect.fromCircle(center: backWheel, radius: radius));
    path.addOval(Rect.fromCircle(center: frontWheel, radius: radius));
    
    final bracket = Offset(w * 0.45, h * 0.7); 
    final seatNode = Offset(w * 0.35, h * 0.45); 
    final handleNode = Offset(w * 0.65, h * 0.45); 

    path.moveTo(backWheel.dx, backWheel.dy);
    path.lineTo(seatNode.dx, seatNode.dy);
    path.lineTo(bracket.dx, bracket.dy);
    path.lineTo(handleNode.dx, handleNode.dy);
    path.lineTo(seatNode.dx, seatNode.dy); 
    
    path.moveTo(bracket.dx, bracket.dy);
    path.lineTo(backWheel.dx, backWheel.dy); 
    
    path.moveTo(handleNode.dx, handleNode.dy);
    path.lineTo(frontWheel.dx, frontWheel.dy);
    
    path.moveTo(handleNode.dx, handleNode.dy);
    path.lineTo(w * 0.68, h * 0.35);
    path.lineTo(w * 0.78, h * 0.35);

    path.moveTo(w * 0.28, h * 0.45);
    path.lineTo(w * 0.42, h * 0.45);

    final headCenter = Offset(w * 0.45, h * 0.22);
    final headRadius = w * 0.08;

    path.moveTo(headCenter.dx, headCenter.dy + headRadius); 
    path.lineTo(w * 0.35, h * 0.45); 
    
    path.moveTo(w * 0.4, h * 0.35); 
    path.lineTo(w * 0.55, h * 0.35); 
    path.lineTo(w * 0.68, h * 0.35); 
    
    path.moveTo(w * 0.35, h * 0.45); 
    path.lineTo(w * 0.5, h * 0.55); 
    path.lineTo(bracket.dx, bracket.dy); 

    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = w * 0.08 
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, paint);

    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(headCenter, headRadius, fillPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
