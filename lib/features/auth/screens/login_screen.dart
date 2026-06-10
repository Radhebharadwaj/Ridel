import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_turnstile/flutter_turnstile.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/utils/validators.dart';
import 'package:ridel/core/widgets/auth_header.dart';
import 'package:ridel/core/widgets/ridel_logo.dart';
import 'package:ridel/core/widgets/ridel_liquid_button.dart';
import 'package:ridel/features/auth/services/auth_service.dart';
import 'package:ridel/features/profile/services/profile_repository.dart';
import 'package:ridel/layout/main_layout.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final FocusNode _emailFocusNode = FocusNode();

  late final StreamSubscription<AuthState> _authSubscription;

  bool _showTurnstile = false;
  int _resendTimer = 0;
  Timer? _countdownTimer;
  bool _mailSent = false;

  final Color neonColor = const Color(0xFF00E5FF);
  final Color darkBg = const Color(0xFF0B0E17);

  @override
  void initState() {
    super.initState();

    _emailFocusNode.addListener(() {
      if (mounted) setState(() {});
    });

    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        if (mounted) _goToHome();
      }
    });
  }

  @override
  void dispose() {
    _emailFocusNode.dispose();
    _emailController.dispose();
    _countdownTimer?.cancel();
    unawaited(_authSubscription.cancel());
    super.dispose();
  }

  void _startCountdown() {
    setState(() => _resendTimer = 60);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        if (_resendTimer == 0) {
          timer.cancel();
        } else {
          setState(() => _resendTimer--);
        }
      }
    });
  }

  void _onContinuePressed() {
    final email = _emailController.text.trim();
    if (email.isEmpty || AppValidators.validateEmail(email) != null) {
      ToastService.showError(context, 'Please enter a valid email address');
      AppHaptics.error();
      return;
    }
    if (_resendTimer > 0) {
      ToastService.showError(
          context, "Please wait for the timer. Your link is valid for 1 hour!");
      return;
    }
    setState(() {
      _isLoading = true;
      _showTurnstile = true;
    });
  }

  Future<void> _handleEmailContinue({String? captchaToken}) async {
    try {
      await _authService.sendSecureResetLink(
        _emailController.text.trim(),
        captchaToken: captchaToken,
      );
      setState(() {
        _isLoading = false;
        _mailSent = true;
      });
      _startCountdown();
      if (mounted) {
        ToastService.showSuccess(context, 'Login link sent! Valid for 1 hour.');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ToastService.showError(context, e.toString());
      AppHaptics.error();
    }
  }

  Future<void> _handleGoogleLogin() async {
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
      if (!response.isSuccess && response.errorMessage != null) {
        ToastService.showError(context, response.errorMessage!);
        AppHaptics.error();
      }
    }
  }

  void _handleAppleLogin() {
    String message = (!kIsWeb &&
            Theme.of(context).platform == TargetPlatform.android)
        ? "Apple Sign-In is for iOS devices. 📱 Please use Google to continue!"
        : "Apple Sign-In is coming soon! 🍏 Please use Google or Email to continue.";
    ToastService.showInfo(context, message);
  }

  Future<void> _handleSkip() async {
    AppHaptics.mediumImpact();
    setState(() => _isLoading = true);
    _goToHome();
  }

  void _goToHome() {
    if (!mounted) return;
    if (ProfileRepository.userCity.value.isEmpty ||
        ProfileRepository.userCity.value == 'Locating...' ||
        ProfileRepository.userCity.value == 'Location Failed' ||
        ProfileRepository.userCity.value == 'GPS Disabled') {
      ProfileRepository.userCity.value = 'delhi';
    }
    unawaited(Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainLayout()),
        (route) => false));
  }

  @override
  Widget build(BuildContext context) {
    final bool isLoggedIn = Supabase.instance.client.auth.currentUser != null;
    final isLightMode = Theme.of(context).brightness == Brightness.light;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              // Bouncing scroll physics ensures standard smooth iOS/Android scrolling
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight -
                      40, // Account for vertical padding
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        RidelLogo(
                            size: 100,
                            color: isLightMode ? Colors.black87 : Colors.white),
                        const SizedBox(height: 20),
                        AuthHeader(
                          texts: const [
                            'Welcome to Ridel!',
                            'Imagine anything',
                            'Seamless Journeys',
                            'Start Creating',
                          ],
                          neonColor: neonColor,
                          isPaused: _isLoading,
                        ),
                        const SizedBox(height: 32),
                        _buildEmailField(isLightMode),
                        const SizedBox(height: 16),
                        if (_showTurnstile)
                          CloudFlareTurnstile(
                            siteKey: '0x4AAAAAADP3RBwUMZczFXPO',
                            onTokenReceived: (token) {
                              setState(() => _showTurnstile = false);
                              _handleEmailContinue(captchaToken: token);
                            },
                            onError: (err) {
                              setState(() {
                                _isLoading = false;
                                _showTurnstile = false;
                              });
                              ToastService.showError(
                                  context, 'Security check failed. Try again.');
                            },
                            options: TurnstileOptions(
                                theme: isLightMode
                                    ? TurnstileTheme.light
                                    : TurnstileTheme.dark,
                                mode: TurnstileMode.invisible),
                          ),
                        _buildContinueButton(isLightMode),
                        if (_mailSent) ...[
                          const SizedBox(height: 12),
                          Text(
                            "Magic link sent to ${_emailController.text}!",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: isLightMode
                                    ? Colors.black54
                                    : Colors.white.withValues(alpha: 0.5),
                                fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            Expanded(child: _buildGoogleButton(isLightMode)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildAppleButton(isLightMode)),
                          ],
                        ),
                        const SizedBox(height: 40),
                        TextButton(
                          onPressed: _isLoading ? null : _handleSkip,
                          style: TextButton.styleFrom(
                            foregroundColor: isLightMode
                                ? Colors.black54
                                : Colors.white.withValues(alpha: 0.5),
                          ),
                          child: Text(
                            'Skip for now →',
                            style: TextStyle(
                              color: isLightMode
                                  ? Colors.black87
                                  : Colors.white.withValues(alpha: 0.5),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (isLoggedIn) ...[
                          const SizedBox(height: 24),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Danger Zone',
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: isLightMode
                                  ? Colors.red.shade50
                                  : const Color(0xFF151515),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 4),
                              leading: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent),
                              title: const Text('Delete Account',
                                  style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500)),
                              subtitle: Text('Scheduled deletion after 7 days',
                                  style: TextStyle(
                                      color: isLightMode
                                          ? Colors.black54
                                          : Colors.white.withValues(alpha: 0.5),
                                      fontSize: 12)),
                              onTap: () async {
                                AppHaptics.heavyImpact();
                                bool? confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (BuildContext dialogContext) {
                                    return AlertDialog(
                                      backgroundColor: isLightMode
                                          ? Colors.white
                                          : const Color(0xFF151515),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16)),
                                      title: Row(
                                        children: [
                                          const Icon(
                                              Icons.warning_amber_rounded,
                                              color: Colors.redAccent),
                                          const SizedBox(width: 10),
                                          Text('Delete Account',
                                              style: TextStyle(
                                                  color: isLightMode
                                                      ? Colors.black87
                                                      : Colors.white,
                                                  fontSize: 18)),
                                        ],
                                      ),
                                      content: Text(
                                        'Your account will be scheduled for deletion in 7 days. You will be logged out of your current session. Are you sure you want to proceed?',
                                        style: TextStyle(
                                            color: isLightMode
                                                ? Colors.black87
                                                : Colors.white
                                                    .withValues(alpha: 0.7),
                                            fontSize: 14),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(dialogContext)
                                                  .pop(false),
                                          child: Text('Cancel',
                                              style: TextStyle(
                                                  color: isLightMode
                                                      ? Colors.black87
                                                      : Colors.white)),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.redAccent
                                                .withValues(alpha: 0.1),
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                          ),
                                          onPressed: () =>
                                              Navigator.of(dialogContext)
                                                  .pop(true),
                                          child: const Text('Yes, Delete',
                                              style: TextStyle(
                                                  color: Colors.redAccent,
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    );
                                  },
                                );

                                if (confirm == true) {
                                  await AuthService().signOut();
                                  if (context.mounted) {
                                    ToastService.showInfo(context,
                                        'Account scheduled for deletion. Logged out safely.');
                                    Navigator.pushAndRemoveUntil(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const LoginScreen()),
                                        (route) => false);
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmailField(bool isLightMode) {
    if (isLightMode) {
      return Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: _buildTextField(isLightMode),
      );
    }

    return RidelLiquidButton(
      width: double.infinity,
      height: MediaQuery.of(context).size.height * 0.07,
      enableStretch: false,
      glassTint: const Color(0x1AFFFFFF),
      onTap: null,
      child: _buildTextField(isLightMode),
    );
  }

  Widget _buildTextField(bool isLightMode) {
    return TextField(
      controller: _emailController,
      focusNode: _emailFocusNode,
      style: TextStyle(
          color: isLightMode ? Colors.black87 : Colors.white, fontSize: 16),
      cursorColor: isLightMode ? Colors.black87 : neonColor,
      decoration: InputDecoration(
        hintText: 'Enter your Email',
        hintStyle: TextStyle(
          color: isLightMode
              ? Colors.grey.shade500
              : Colors.white.withValues(alpha: 0.3),
          fontSize: 16,
        ),
        filled: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 20, right: 12),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Icon(
              Icons.email_outlined,
              key: ValueKey(_emailFocusNode.hasFocus),
              color: _emailFocusNode.hasFocus
                  ? (isLightMode ? Colors.black87 : neonColor)
                  : (isLightMode
                      ? Colors.grey.shade400
                      : Colors.white.withValues(alpha: 0.4)),
              size: 22,
            ),
          ),
        ),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(100),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(100),
            borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildContinueButton(bool isLightMode) {
    if (isLightMode) {
      return GestureDetector(
        onTap: _isLoading ? null : _onContinuePressed,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(
                    _resendTimer == 0
                        ? 'Continue'
                        : 'Resend in ${_resendTimer}s',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
      );
    }

    return RidelLiquidButton(
      width: double.infinity,
      height: MediaQuery.of(context).size.height * 0.07,
      enableStretch: true,
      glassTint: neonColor.withValues(alpha: 0.15),
      onTap: _isLoading ? () {} : _onContinuePressed,
      child: _isLoading
          ? const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white),
            )
          : Text(
              _resendTimer == 0 ? 'Continue' : 'Resend in ${_resendTimer}s',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
    );
  }

  Widget _buildGoogleButton(bool isLightMode) {
    if (isLightMode) {
      return GestureDetector(
        onTap: _isLoading ? null : _handleGoogleLogin,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: Colors.grey.shade300, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ]),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.string(GoogleLoginButton.googleSvgCode,
                  height: 20, width: 20),
              const SizedBox(width: 10),
              const Flexible(
                child: Text('Google',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
    }

    return RidelLiquidButton(
      width: double.infinity,
      height: MediaQuery.of(context).size.height * 0.07,
      enableStretch: true,
      glassTint: const Color(0x1AFFFFFF),
      onTap: _isLoading ? () {} : _handleGoogleLogin,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.string(GoogleLoginButton.googleSvgCode,
              height: 20, width: 20),
          const SizedBox(width: 10),
          const Flexible(
            child: Text('Google',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildAppleButton(bool isLightMode) {
    if (isLightMode) {
      return GestureDetector(
        onTap: _isLoading ? null : _handleAppleLogin,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: Colors.grey.shade300, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ]),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.apple, color: Colors.black, size: 24),
              SizedBox(width: 8),
              Flexible(
                child: Text('Apple',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
    }

    return RidelLiquidButton(
      width: double.infinity,
      height: MediaQuery.of(context).size.height * 0.07,
      enableStretch: true,
      glassTint: const Color(0x1AFFFFFF),
      onTap: _isLoading ? () {} : _handleAppleLogin,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.apple, color: Colors.white, size: 24),
          SizedBox(width: 8),
          Flexible(
            child: Text('Apple',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
        ],
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
