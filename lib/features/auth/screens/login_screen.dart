import 'dart:ui';
import 'dart:io' show Platform; 
import 'dart:async'; 
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; 
import 'package:provider/provider.dart';

import 'package:ridel/core/services/global_location_service.dart';
import 'package:ridel/core/services/place_service.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/features/auth/services/auth_service.dart';
import 'package:ridel/layout/main_layout.dart';
import 'package:ridel/core/widgets/ridel_logo.dart'; 

// ✅ Pixy wale perfect animated text widget ka import 
import 'package:ridel/core/widgets/auth_header.dart'; 

// Logic Services
import 'package:ridel/core/services/identity_service.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import 'package:ridel/core/widgets/city_selector_sheet.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  final AuthService _authService = AuthService();
  final IdentityService _identityService = IdentityService();
  final TextEditingController _emailController = TextEditingController();

  late final StreamSubscription<AuthState> _authSubscription;

  // --- Theme Colors ---
  final Color neonColor = const Color(0xFF00E5FF);
  final Color darkBg = const Color(0xFF050505);
  final Color fieldBg = const Color(0xFF151515);

  @override
  void initState() {
    super.initState();
    
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        if (mounted) {
          _goToHome();
        }
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _authSubscription.cancel();
    super.dispose();
  }

  // --- 1. GOOGLE LOGIN ---
  void _handleGoogleLogin() async {
    AppHaptics.heavyImpact();
    
    if (kDebugMode && !kIsWeb && Platform.isLinux) {
      _goToHome();
      return;
    }

    setState(() => _isLoading = true);

    if (kIsWeb) {
      _authService.signInWithGoogle();
      return;
    }

    final response = await _authService.signInWithGoogle();

    if (mounted) {
      setState(() => _isLoading = false);
      if (response != null) {
        ToastService.showError(context, "Login Failed: $response");
      }
    }
  }

  // --- 2. SMART SKIP LOGIC ---
  Future<void> _handleSkip() async {
    AppHaptics.mediumImpact();
    
    if (kDebugMode && !kIsWeb && Platform.isLinux) {
      _goToHome();
      return;
    }

    setState(() => _isLoading = true);

    var status = await Permission.location.request();

    if (status.isGranted) {
      try {
        String? userCity;
        try {
          final locationService = Provider.of<GlobalLocationService>(context, listen: false);
          await locationService.initializeEcoLocation();
          final pos = locationService.currentPosition;
          if (pos != null && !pos.isMocked) {
            userCity = await PlaceService.getCityFromCoordinates(pos.latitude, pos.longitude);
          }
        } catch (e) {
          debugPrint("Login Location Error: $e");
        }
        _goToHome(); 
      } catch (e) {
        _openCitySelector(); 
      }
    } else {
      if (mounted) _openCitySelector();
    }
  }

  void _openCitySelector() {
    setState(() => _isLoading = false);
    
    RidelSheet.show(
      context,
      title: "Select Your City",
      showBackButton: false, 
      child: const CitySelectorSheet(),
    );
  }

  void _goToHome() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MainLayout()),
      (route) => false 
    );
  }

  void _handleEmailContinue() {
    ToastService.showError(context, "Email sign-in is coming soon. Please try Google!");
  }

  void _handleAppleLogin() {
    ToastService.showError(context, "Apple Sign-In is device-specific. We recommend using Google.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBg, 
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                
                // 1. App Logo
                const RidelLogo(size: 100), 
                const SizedBox(height: 20), // 🔥 Reduced from 30 to 20 for perfect grouping

                // 2. AuthHeader Text Animation
                AuthHeader(
                  texts: const [
                    "Welcome to Ridel!",
                    "Imagine anything",
                    "Seamless Journeys",
                    "Start Creating",
                  ], 
                  neonColor: neonColor
                ),
                
                const SizedBox(height: 32), // 🔥 Reduced from 50 to 32 for a breathable, cohesive look

                // 3. Email Input Field
                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Enter your Email",
                    hintStyle: TextStyle(color: neonColor.withOpacity(0.5), fontSize: 16),
                    filled: true,
                    fillColor: fieldBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12), 
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.1))
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12), 
                      borderSide: BorderSide(color: neonColor, width: 1.5)
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // 4. Continue Button (Email)
                GestureDetector(
                  onTap: _isLoading ? null : _handleEmailContinue,
                  child: Container(
                    width: double.infinity, 
                    height: 56,
                    decoration: BoxDecoration(
                      color: neonColor, 
                      borderRadius: BorderRadius.circular(12), 
                      boxShadow: [
                        BoxShadow(color: neonColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 4))
                      ]
                    ),
                    child: const Center(
                      child: Text(
                        "Continue", 
                        style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)
                      )
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // 5. Social Logins (Google & Apple)
                Row(
                  children: [
                    Expanded(child: _buildGoogleButton()), 
                    const SizedBox(width: 16),
                    Expanded(child: _buildAppleButton()), 
                  ],
                ),

                const SizedBox(height: 40),

                // 6. Skip Button
                TextButton(
                  onPressed: _isLoading ? null : _handleSkip,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withOpacity(0.5),
                  ),
                  child: Text(
                    "Skip for now →", 
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5), 
                      fontSize: 14, 
                      fontWeight: FontWeight.w400
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : _handleGoogleLogin,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoading) 
                SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: neonColor))
              else ...[
                SvgPicture.string(GoogleLoginButton.googleSvgCode, height: 20, width: 20),
                const SizedBox(width: 10),
                const Text("Google", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppleButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : _handleAppleLogin,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.apple, color: Colors.white, size: 24),
              SizedBox(width: 8),
              Text("Apple", style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class GoogleLoginButton {
  static const String googleSvgCode = '''
    <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
      <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/>
      <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
      <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
      <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
    </svg>
  ''';
}