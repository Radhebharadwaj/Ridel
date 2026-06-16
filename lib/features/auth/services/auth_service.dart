import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:device_info_plus/device_info_plus.dart';

class AuthResult {
  final bool isSuccess;
  final bool isNewUser;
  final String? errorMessage;

  AuthResult({
    required this.isSuccess,
    this.isNewUser = false,
    this.errorMessage,
  });
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  static const String _webClientId =
      '141150485050-tb6is1kksj7j433hfrkho9aq4hh7bo98.apps.googleusercontent.com';

  final List<String> _blockedDomains = [
    'tempmail.com',
    '10minutemail.com',
    'mailinator.com',
    'guerrillamail.com',
    'yopmail.com',
  ];

  bool _isTempMail(String email) {
    final domain = email.split('@').last.toLowerCase();
    return _blockedDomains.contains(domain);
  }

  // ==========================================
  // 🛡️ SECURE PASSWORD RESET & OTP LOGIC
  // ==========================================

  Future<void> sendSecureResetLink(String email, {String? captchaToken}) async {
    debugPrint('Auth Flow: Entered sendSecureResetLink for email: $email');
    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: kIsWeb ? null : 'ridel://reset-password',
        captchaToken: captchaToken,
      );
      debugPrint('Supabase Auth: Reset link sent successfully.');
    } on AuthException catch (e) {
      debugPrint('Supabase Auth Error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Supabase Auth Unexpected Error: $e');
      throw _translatePremiumError(e);
    }
  }

  Future<void> sendOtp(String email, {String? captchaToken}) async {
    debugPrint('Auth Flow: Entered sendOtp for email: $email');
    try {
      await _supabase.auth.signInWithOtp(
        email: email,
        shouldCreateUser: false,
        captchaToken: captchaToken,
      );
      debugPrint('Supabase Auth: OTP email sent successfully.');
    } on AuthException catch (e) {
      debugPrint('Supabase Auth Error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Supabase Auth Unexpected Error: $e');
      throw _translatePremiumError(e);
    }
  }

  Future<AuthResult> verifyOtp(String email, String otp) async {
    try {
      final response = await _supabase.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.magiclink,
      );
      bool isNew = false;
      if (response.user != null) {
        final createdAt = DateTime.parse(response.user!.createdAt);
        final lastSignIn = response.user!.lastSignInAt != null
            ? DateTime.parse(response.user!.lastSignInAt!)
            : DateTime.now();
        isNew = lastSignIn.difference(createdAt).inSeconds < 5;
      }
      return AuthResult(isSuccess: true, isNewUser: isNew);
    } catch (e) {
      return AuthResult(
          isSuccess: false, errorMessage: _translatePremiumError(e));
    }
  }

  Future<void> updateSecurePassword(String newPassword) async {
    try {
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } catch (e) {
      throw _translatePremiumError(e);
    }
  }

  // ==========================================
  // GOOGLE & APPLE SIGN-IN
  // ==========================================
  Future<AuthResult> signInWithGoogle({String? emailHint}) async {
    try {
      if (kIsWeb) {
        // 🚀 PERFECT FIX: Ensure path is exactly matching the wildcard
        // Agar Uri.base.origin 'https://ridel.pages.dev' hai, toh usko exact slash ('/') ke sath append karo, taaki dashboard ke '/* ' wildcard se match kare.
        final String redirectUrl = Uri.base.origin.endsWith('/')
            ? Uri.base.origin
            : '${Uri.base.origin}/';

        // Sirf EK BAAR call karna hai!
        await _supabase.auth
            .signInWithOAuth(OAuthProvider.google, redirectTo: redirectUrl);
        return AuthResult(isSuccess: true);
      } else {
        final googleSignIn = GoogleSignIn.instance;
        await googleSignIn.initialize(serverClientId: _webClientId);

        // 🚀 FIX: Warning hatayi aur exact wahi logic lagaya jo aapka pehle chal raha tha
        final googleUser = await googleSignIn.authenticate();

        if (_isTempMail(googleUser.email)) {
          await googleSignIn.signOut();
          return AuthResult(
              isSuccess: false,
              errorMessage: 'Use your genuine Google account.');
        }

        final GoogleSignInAuthentication googleAuth = googleUser.authentication;
        final String? idToken = googleAuth.idToken;

        final clientAuth = await googleUser.authorizationClient
            .authorizeScopes(['email', 'profile']);
        final String accessToken = clientAuth.accessToken;

        final response = await _supabase.auth.signInWithIdToken(
            provider: OAuthProvider.google,
            idToken: idToken!,
            accessToken: accessToken);

        bool isNew = false;
        if (response.user != null) {
          final createdAt = DateTime.parse(response.user!.createdAt);
          final lastSignIn = response.user!.lastSignInAt != null
              ? DateTime.parse(response.user!.lastSignInAt!)
              : DateTime.now();
          isNew = lastSignIn.difference(createdAt).inSeconds < 5;
        }
        return AuthResult(isSuccess: true, isNewUser: isNew);
      }
    } catch (e) {
      return AuthResult(
          isSuccess: false, errorMessage: _translatePremiumError(e));
    }
  }

  Future<AuthResult> signInWithApple() async {
    try {
      if (kIsWeb || !Platform.isIOS) {
        return AuthResult(isSuccess: false, errorMessage: 'iOS only.');
      }
      final credential = await SignInWithApple.getAppleIDCredential(scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName
      ]);
      final response = await _supabase.auth.signInWithIdToken(
          provider: OAuthProvider.apple, idToken: credential.identityToken!);
      bool isNew = false;
      if (response.user != null) {
        final createdAt = DateTime.parse(response.user!.createdAt);
        final lastSignIn = response.user!.lastSignInAt != null
            ? DateTime.parse(response.user!.lastSignInAt!)
            : DateTime.now();
        isNew = lastSignIn.difference(createdAt).inSeconds < 5;
      }
      return AuthResult(isSuccess: true, isNewUser: isNew);
    } catch (e) {
      return AuthResult(
          isSuccess: false, errorMessage: _translatePremiumError(e));
    }
  }

  Future<AuthResult> signInWithAppleWeb() async {
    try {
      String redirectUrl = Uri.base.origin;
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: redirectUrl,
      );

      await _supabase.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: redirectUrl,
      );

      return AuthResult(isSuccess: true);
    } catch (e) {
      return AuthResult(
          isSuccess: false, errorMessage: _translatePremiumError(e));
    }
  }

  // ==========================================
  // DEVICE TRACKING & LOGOUT
  // ==========================================
  Future<void> setupAndSaveDeviceToken() async {
    final user = _supabase.auth.currentUser;
    if (user == null || kIsWeb) return;
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      String? fcmToken = await messaging.getToken();
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String deviceName = "Device";

      if (Platform.isIOS) {
        deviceName = (await deviceInfo.iosInfo).name;
      } else if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        deviceName = "${info.brand} ${info.model}";
      }

      if (fcmToken != null) {
        await _supabase.from('user_devices').upsert({
          'user_id': user.id,
          'fcm_token': fcmToken,
          'device_type': Platform.isIOS ? 'ios' : 'android',
          'device_name': deviceName,
          'last_seen': DateTime.now().toUtc().toIso8601String()
        }, onConflict: 'fcm_token');
      }
      try {
        await _supabase.from('user_apps_access').insert({
          'user_id': user.id,
          'app_id': 'ridel_app',
          'role': 'user',
          'joined_at': DateTime.now().toUtc().toIso8601String()
        });
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> signOut() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null && !kIsWeb) {
        await GoogleSignIn.instance.disconnect();
        String? token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await _supabase.from('user_devices').delete().eq('fcm_token', token);
        }
      }
      await _supabase.auth.signOut();
    } catch (_) {}
  }

  String _translatePremiumError(dynamic error) {
    String err = error.toString().toLowerCase();
    if (err.contains('network')) return 'Check your internet connection.';
    if (err.contains('rate_limit') || err.contains('too many requests')) {
      return 'Too many attempts. Please wait 1 hour.';
    }
    return 'Authentication error. Please try again.';
  }

  User? get currentUser => _supabase.auth.currentUser;
}
