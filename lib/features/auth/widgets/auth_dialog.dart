import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/utils/validators.dart';
import 'package:ridel/core/widgets/ridel_logo.dart';
import 'package:ridel/features/auth/services/auth_service.dart';
import 'package:ridel/core/widgets/adaptive_blur.dart';

Future<void> showRidelAuthDialog(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'AuthDialog',
    barrierColor: Colors.black.withValues(alpha: 0.65),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, anim1, anim2) {
      const content = Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Material(
            color: Colors.transparent,
            child: RidelAuthDialogContent(),
          ),
        ),
      );

      return kIsWeb ? PointerInterceptor(child: content) : content;
    },
    transitionBuilder: (context, anim1, anim2, child) {
      final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
      return ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class RidelAuthDialogContent extends StatefulWidget {
  const RidelAuthDialogContent({super.key});

  @override
  State<RidelAuthDialogContent> createState() => _RidelAuthDialogContentState();
}

class _RidelAuthDialogContentState extends State<RidelAuthDialogContent> {
  final AuthService _authService = AuthService();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _otpCtrl = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _otpFocus = FocusNode();

  bool _isLoading = false;
  bool _otpSent = false;
  int _resendTimer = 0;
  Timer? _countdownTimer;
  StreamSubscription<AuthState>? _authSubscription;

  static const Color cyanAccent = Color(0xFF00E5FF);
  static const Color blueAccent = Color(0xFF007AFF);

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn && mounted) {
        AppHaptics.success();
        ToastService.showSuccess(context, 'Signed in successfully! 🚀');
        Navigator.of(context, rootNavigator: true).pop();
      }
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _emailFocus.dispose();
    _otpFocus.dispose();
    _countdownTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() => _resendTimer = 60);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendTimer <= 0) {
        timer.cancel();
      } else {
        setState(() => _resendTimer--);
      }
    });
  }

  Future<void> _handleSendOtp() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || AppValidators.validateEmail(email) != null) {
      AppHaptics.error();
      ToastService.showError(context, 'Please enter a valid email address');
      return;
    }

    setState(() => _isLoading = true);
    AppHaptics.mediumImpact();

    try {
      await _authService.sendOtp(email);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _otpSent = true;
        });
        _startCountdown();
        ToastService.showSuccess(context, '6-digit code sent to $email');
        _otpFocus.requestFocus();
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ToastService.showError(context, e.message);
        AppHaptics.error();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ToastService.showError(context, e.toString());
        AppHaptics.error();
      }
    }
  }

  Future<void> _handleVerifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length < 6) {
      AppHaptics.error();
      ToastService.showError(context, 'Enter the full 6-digit verification code');
      return;
    }

    setState(() => _isLoading = true);
    AppHaptics.mediumImpact();

    try {
      final res = await _authService.verifyOtp(_emailCtrl.text.trim(), otp);
      if (mounted) {
        setState(() => _isLoading = false);
        if (res.isSuccess) {
          AppHaptics.success();
          ToastService.showSuccess(context, 'Welcome to Ridel!');
          Navigator.of(context, rootNavigator: true).pop();
        } else {
          AppHaptics.error();
          ToastService.showError(context, res.errorMessage ?? 'Invalid code entered');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppHaptics.error();
        ToastService.showError(context, 'Verification failed. Try again.');
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    AppHaptics.mediumImpact();
    try {
      final res = await _authService.signInWithGoogle();
      if (!kIsWeb && mounted) {
        setState(() => _isLoading = false);
        if (res.isSuccess) {
          Navigator.of(context, rootNavigator: true).pop();
        } else if (res.errorMessage != null) {
          ToastService.showError(context, res.errorMessage!);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ToastService.showError(context, 'Google Sign In error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgGrad = isDark
        ? [const Color(0xFF141824).withValues(alpha: 0.94), const Color(0xFF0F121B).withValues(alpha: 0.97)]
        : [Colors.white.withValues(alpha: 0.96), const Color(0xFFF7F9FC).withValues(alpha: 0.98)];

    final border = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    return Container(
      width: 420,
      constraints: const BoxConstraints(maxWidth: 420),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: bgGrad,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: AdaptiveBlur(sigmaX: 30, sigmaY: 30,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header Row with Close button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Glowing logo badge
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [cyanAccent, blueAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: cyanAccent.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const RidelLogo(
                        size: 26,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      splashRadius: 20,
                      icon: Icon(
                        Icons.close_rounded,
                        color: isDark ? Colors.white60 : Colors.black54,
                        size: 22,
                      ),
                      onPressed: () {
                        AppHaptics.selectionClick();
                        Navigator.of(context, rootNavigator: true).pop();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Title & Subtitle
                Text(
                  _otpSent ? 'Enter Verification Code' : 'Welcome to Ridel',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _otpSent
                      ? 'We sent a 6-digit code to ${_emailCtrl.text.trim()}'
                      : 'Sign in to access saved places, smart routing and personalized navigation.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.black54,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),

                if (!_otpSent) ...[
                  // 1. Google One-Click Sign-In
                  SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03),
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.black.withValues(alpha: 0.10),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _isLoading ? null : _handleGoogleSignIn,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Google G Icon
                          Image.network(
                            'https://www.gstatic.com/images/branding/product/2x/googleg_48dp.png',
                            height: 20,
                            width: 20,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.g_mobiledata_rounded,
                              size: 22,
                              color: Color(0xFF4285F4),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Continue with Google',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Divider
                  Row(
                    children: [
                      Expanded(
                        child: Divider(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.1),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or email',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.1),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Email Input Field
                  TextField(
                    controller: _emailCtrl,
                    focusNode: _emailFocus,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _handleSendOtp(),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.04),
                      prefixIcon: Icon(
                        Icons.alternate_email_rounded,
                        size: 18,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                      hintText: 'name@example.com',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 13,
                        color: isDark ? Colors.white30 : Colors.black38,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.1),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.1),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: cyanAccent, width: 1.5),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Continue Button
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cyanAccent,
                        foregroundColor: Colors.black87,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _isLoading ? null : _handleSendOtp,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.black87),
                              ),
                            )
                          : Text(
                              'Continue with Email',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ] else ...[
                  // 2. OTP Code Input
                  TextField(
                    controller: _otpCtrl,
                    focusNode: _otpFocus,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.04),
                      hintText: '000000',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 22,
                        letterSpacing: 8,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.1),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.1),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: cyanAccent, width: 1.5),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Verify Button
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cyanAccent,
                        foregroundColor: Colors.black87,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _isLoading ? null : _handleVerifyOtp,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.black87),
                              ),
                            )
                          : Text(
                              'Verify & Sign In',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Resend & Back Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _otpSent = false;
                            _otpCtrl.clear();
                          });
                        },
                        child: Text(
                          'Change email',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _resendTimer > 0 ? null : _handleSendOtp,
                        child: Text(
                          _resendTimer > 0 ? 'Resend in ${_resendTimer}s' : 'Resend code',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _resendTimer > 0
                                ? (isDark ? Colors.white30 : Colors.black26)
                                : cyanAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),

                // Privacy note
                Text(
                  'By signing in, you agree to Ridel terms & privacy policy.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: isDark ? Colors.white30 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

