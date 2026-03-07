import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// ✅ Platform check karne ke liye zaroori import
import 'dart:io'; 

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // 🚀 UNIVERSAL GOOGLE SIGN-IN
  Future<AuthResponse?> signInWithGoogle() async {
    try {
      // ✅ Dynamic Redirect URL Logic
      String redirectUrl;
      
      if (kIsWeb) {
        redirectUrl = 'http://localhost:5000/';
      } else if (Platform.isAndroid || Platform.isIOS) {
        redirectUrl = 'ridel://login-callback'; // Mobile Deep Link
      } else {
        // 🖥️ Desktop (Linux/Windows) ke liye Localhost Loopback
        // Supabase desktop par deep link nahi, balki localhost server use karta hai
        redirectUrl = 'http://localhost:3000/callback'; 
      }

      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
      );
      
      return null; 
    } catch (e) {
      debugPrint("❌ Google Sign-In Error: $e");
      return null;
    }
  }

  // 🚪 LOGOUT LOGIC
  Future<void> signOut() async {
    await _supabase.auth.signOut(); 
  }

  // 👤 CURRENT USER CHECK
  User? get currentUser => _supabase.auth.currentUser;
}