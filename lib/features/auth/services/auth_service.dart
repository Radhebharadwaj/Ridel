import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Google Sign In Logic
  Future<AuthResponse?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Web-specific OAuth flow
        await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: 'http://localhost:5000/',
        );
        return null; // signInWithOAuth will handle the redirect
      } else {
        // Mobile-specific flow
        const webClientId =
            '141150485050-tb6is1kksj7j433hfrkho9aq4hh7bo98.apps.googleusercontent.com';

        final GoogleSignIn googleSignIn = GoogleSignIn(
          clientId: kIsWeb ? webClientId : null,
        );

        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) return null;

        final googleAuth = await googleUser.authentication;
        final accessToken = googleAuth.accessToken;
        final idToken = googleAuth.idToken;

        if (accessToken == null || idToken == null) {
          throw 'Missing Google Auth Token';
        }

        return await _supabase.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: accessToken,
        );
      }
    } catch (e) {
      debugPrint("❌ Google Sign-In Error: $e");
      return null;
    }
  }

  // Logout Logic
  Future<void> signOut() async {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    await googleSignIn.signOut(); // Google se logout
    await _supabase.auth.signOut(); // Supabase se logout
  }

  // Current User Check
  User? get currentUser => _supabase.auth.currentUser;
}