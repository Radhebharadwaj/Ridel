import 'dart:ui'; // For Blur
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart'; // Animation Package
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/features/auth/services/auth_service.dart';
import 'package:ridel/core/widgets/navigation_menu.dart'; // Home Page wrapper

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  final AuthService _authService = AuthService();

  // Function to handle Google Login
  void _handleGoogleLogin() async {
    AppHaptics.heavyImpact();
    setState(() => _isLoading = true);

    if (kIsWeb) {
      // For web, we don't await the response as the browser handles the redirect.
      _authService.signInWithGoogle();
      // We return here to prevent showing a "Login Failed" message, as we won't get a session response immediately.
      return;
    }

    final response = await _authService.signInWithGoogle();

    if (mounted) {
      setState(() => _isLoading = false);
      if (response != null && response.session != null) {
        Navigator.pushReplacement(
          context, 
          MaterialPageRoute(builder: (_) => const NavigationMenu())
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Login Failed. Try again."), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Function to handle Skip action
  void _handleSkip() {
    AppHaptics.lightImpact();
    // Navigate to Home without user session (Guest Mode handling required in Home)
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const NavigationMenu()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Background ko thoda sa light dark grey rakha hai taki black logo shadow dikhe
      backgroundColor: const Color(0xFF121212), 
      body: SafeArea(
        child: Stack(
          children: [
            // --- MAIN CONTENT ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 80),

                    // LOGO (With subtle in-app glow)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.15),
                            blurRadius: 60,
                            spreadRadius: -5,
                          )
                        ],
                      ),
                      child: Image.asset(
                        'assets/icon/logo.png', // Ye wahi glow wali image use karega
                        height: 120,
                        width: 120,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // TYPING ANIMATION TEXT
                    SizedBox(
                      height: 80, // Fixed height to prevent layout jump
                      child: DefaultTextStyle(
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins', // Ensure font is added in pubspec
                          letterSpacing: 1.2,
                        ),
                        child: AnimatedTextKit(
                          animatedTexts: [
                            TypewriterAnimatedText(
                              'Welcome to Ridel',
                              speed: const Duration(milliseconds: 100),
                              cursor: '|',
                            ),
                          ],
                          isRepeatingAnimation: false,
                          displayFullTextOnTap: true,
                        ),
                      ),
                    ),

                    const Text(
                      "The Ultimate Travel Ecosystem",
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Metro • Bus • Tours",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // NEW PROMPT TEXT
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 15),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(15)),
                      child: Text(
                        "Sign up below to unlock the best user experience, personalized routes, and exclusive deals!",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                            height: 1.4),
                      ),
                    ),

                    const SizedBox(height: 60),

                    // GLASS LOGIN BUTTON
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: GestureDetector(
                          onTap: _isLoading ? null : _handleGoogleLogin,
                          child: Container(
                            height: 55,
                            width: double.infinity,
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4))
                                ]),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _isLoading
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                            color: Colors.white, strokeWidth: 2))
                                    : Image.network(
                                        "https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1200px-Google_%22G%22_logo.svg.png",
                                        height: 24),
                                const SizedBox(width: 15),
                                Text(
                                  _isLoading
                                      ? "Signing in..."
                                      : "Continue with Google",
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
            // --- SKIP BUTTON (Top Right) ---
            Positioned(
              top: 10,
              right: 20,
              child: TextButton.icon(
                onPressed: _handleSkip,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.7),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2))
                  )
                ),
                icon: const Icon(Icons.skip_next_rounded, size: 18),
                label: const Text("Skip", style: TextStyle(fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}