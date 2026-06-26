import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_turnstile/flutter_turnstile.dart';
import 'package:pinput/pinput.dart';
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
import 'package:ridel/core/widgets/branded_loader.dart';

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
  bool _isRequestPending = false;
  int _resendTimer = 0;
  Timer? _countdownTimer;
  bool _mailSent = false;

  final Color neonColor = CupertinoColors.systemBlue;

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
    setState(() => _resendTimer = 300);
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
    debugPrint('Auth Flow: _onContinuePressed triggered');
    FocusManager.instance.primaryFocus?.unfocus();
    if (_isLoading) return;

    final email = _emailController.text.trim();
    if (email.isEmpty || AppValidators.validateEmail(email) != null) {
      ToastService.showError(context, 'Please enter a valid email address');
      AppHaptics.error();
      return;
    }

    if (_resendTimer > 0) {
      ToastService.showError(
          context, "Please wait for the timer to resend the code.");
      return;
    }
    setState(() {
      _isLoading = true;
      _showTurnstile = true;
      _isRequestPending = true;
    });

    Future.delayed(const Duration(seconds: 20), () {
      if (mounted && _isRequestPending) {
        debugPrint('Turnstile: Timeout after 20 seconds. Aborting request.');
        debugPrint('Turnstile Timed Out');
        setState(() {
          _isLoading = false;
          _showTurnstile = false;
          _isRequestPending = false;
        });
        ToastService.showError(
            context, 'Security check timed out. Please try again.');
      }
    });
  }

  Future<void> _handleEmailContinue({String? captchaToken}) async {
    debugPrint('Auth Flow: _handleEmailContinue triggered with token: $captchaToken');
    try {
      await _authService.sendOtp(
        _emailController.text.trim(),
        captchaToken: captchaToken,
      );
      setState(() {
        _isLoading = false;
        _mailSent = true;
      });
      _startCountdown();
      if (mounted) {
        ToastService.showSuccess(context, 'OTP sent! Valid for 5 minutes.');
      }
    } on AuthException catch (e) {
      debugPrint('AuthException in _handleEmailContinue: ${e.message}');
      setState(() {
        _isLoading = false;
        _showTurnstile = false;
      });
      if (mounted) ToastService.showError(context, e.message);
      AppHaptics.error();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _showTurnstile = false;
      });
      if (mounted) ToastService.showError(context, e.toString());
      AppHaptics.error();
    }
  }

  Future<void> _resendOtp() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();
    if (email.isEmpty || AppValidators.validateEmail(email) != null) {
      ToastService.showError(context, 'Please enter a valid email address');
      AppHaptics.error();
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.sendOtp(_emailController.text.trim());
      setState(() => _isLoading = false);
      _startCountdown();
      if (mounted) {
        ToastService.showSuccess(context, 'New code sent! Please note: any previous codes are now invalid.');
        AppHaptics.mediumImpact();
      }
    } on AuthException catch (e) {
      debugPrint('AuthException in _resendOtp: ${e.message}');
      setState(() => _isLoading = false);
      if (mounted) ToastService.showError(context, e.message);
      AppHaptics.error();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ToastService.showError(context, e.toString());
      AppHaptics.error();
    }
  }

  Future<void> _verifyOtp(String otp) async {
    setState(() => _isLoading = true);
    try {
      final result =
          await _authService.verifyOtp(_emailController.text.trim(), otp);
      if (mounted) {
        setState(() => _isLoading = false);
        if (result.isSuccess) {
          _goToHome();
        } else {
          final isInvalid =
              result.errorMessage?.toLowerCase().contains('invalid') ?? false;
          final isTokenError =
              result.errorMessage?.toLowerCase().contains('token') ?? false;
          if (isInvalid || isTokenError) {
            ToastService.showError(context,
                'Invalid code entered. Please check your latest email and try again.');
          } else {
            ToastService.showError(
                context, result.errorMessage ?? 'Invalid OTP');
          }
          AppHaptics.error();
        }
      }
    } on AuthException catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        ToastService.showError(context,
            'Invalid code entered. Please check your latest email and try again.');
        AppHaptics.error();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        ToastService.showError(context,
            'Invalid code entered. Please check your latest email and try again.');
        AppHaptics.error();
      }
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
      backgroundColor: isLightMode ? Colors.white : const Color(0xFF0B0E17),
      body: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 40,
                ),
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        const Spacer(),
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
                        SizedBox(
                          height: 260,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 400),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: _mailSent
                                  ? _buildOtpView(isLightMode)
                                  : _buildEmailForm(isLightMode),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24.0),
                          child: TextButton(
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
                        ),
                        if (_showTurnstile) ...[
                          const SizedBox(height: 24),
                          CloudFlareTurnstile(
                            siteKey: '0x4AAAAAADP3RBwUMZczFXPO',
                            onTokenReceived: (token) {
                              debugPrint('Turnstile: Token received successfully.');
                              if (!_isRequestPending) {
                                debugPrint('Turnstile: Ignored token because request timed out or was already processed.');
                                return;
                              }
                              setState(() {
                                _showTurnstile = false;
                                _isRequestPending = false;
                              });
                              _handleEmailContinue(captchaToken: token);
                            },
                            onError: (err) {
                              debugPrint('Turnstile: Error $err');
                              setState(() {
                                _isLoading = false;
                                _showTurnstile = false;
                                _isRequestPending = false;
                              });
                              ToastService.showError(context,
                                  'Turnstile Error: Captcha failed to load.');
                            },
                            options: TurnstileOptions(
                                theme: isLightMode
                                    ? TurnstileTheme.light
                                    : TurnstileTheme.dark,
                                mode: TurnstileMode.managed),
                          ),
                        ],

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
            ),
          );
        },
      ),
    ),
  ],
),
);
  }

  Widget _buildEmailForm(bool isLightMode) {
    return Column(
      key: const ValueKey('email_form'),
      children: [
        _buildEmailField(isLightMode),
        const SizedBox(height: 16),
        _buildContinueButton(isLightMode,
            onTap: _isLoading ? null : _onContinuePressed),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildGoogleButton(isLightMode,
                  onTap: _isLoading ? null : _handleGoogleLogin),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildAppleButton(isLightMode,
                  onTap: _isLoading ? null : _handleAppleLogin),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOtpView(bool isLightMode) {
    final defaultPinTheme = PinTheme(
      width: 50,
      height: 50,
      textStyle: TextStyle(
        fontSize: 22,
        color: isLightMode ? Colors.black87 : Colors.white,
        fontWeight: FontWeight.w600,
      ),
      decoration: BoxDecoration(
        color: isLightMode
            ? Colors.black.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.transparent),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyWith(
      width: 54,
      height: 54,
      decoration: defaultPinTheme.decoration?.copyWith(
        border: Border.all(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
            blurRadius: 8,
            spreadRadius: 1,
          )
        ],
      ),
    );

    final submittedPinTheme = defaultPinTheme.copyWith(
      width: 50,
      height: 50,
      decoration: defaultPinTheme.decoration?.copyWith(
        color: isLightMode
            ? Colors.black.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.1),
        border: Border.all(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.3), width: 1),
      ),
    );

    return Column(
      key: const ValueKey('otp_form'),
      children: [
        Text(
          'Enter the 6-digit code sent to\n${_emailController.text}',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isLightMode ? Colors.black54 : Colors.white70,
            fontSize: 15,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        Pinput(
          length: 6,
          defaultPinTheme: defaultPinTheme,
          focusedPinTheme: focusedPinTheme,
          submittedPinTheme: submittedPinTheme,
          showCursor: true,
          autofocus: true,
          onCompleted: (pin) => _verifyOtp(pin),
        ),
        const SizedBox(height: 32),
        if (_isLoading)
          const BrandedLoader(isFullScreen: false)
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    _mailSent = false;
                    _resendTimer = 0;
                    _countdownTimer?.cancel();
                  });
                },
                child: Text('Edit Email',
                    style: TextStyle(
                        color: isLightMode ? Colors.black54 : Colors.white54)),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: _resendTimer == 0 ? _resendOtp : null,
                child: Text(
                  _resendTimer == 0
                      ? 'Resend Code'
                      : 'Resend in ${(_resendTimer ~/ 60).toString().padLeft(2, '0')}:${(_resendTimer % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: _resendTimer == 0
                        ? const Color(0xFF00BFA5)
                        : (isLightMode ? Colors.grey : Colors.white38),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildEmailField(bool isLightMode) {
    if (isLightMode) {
      return Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
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

    return Container(
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(100),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: SizedBox(
            height: 56,
            child: _buildTextField(isLightMode),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(bool isLightMode) {
    return TextField(
      controller: _emailController,
      focusNode: _emailFocusNode,
      maxLength: 254,
      keyboardType: TextInputType.emailAddress,
      inputFormatters: [
        FilteringTextInputFormatter.deny(RegExp(r'\s')),
      ],
      style: TextStyle(
          color: isLightMode ? Colors.black87 : Colors.white, fontSize: 16),
      cursorColor: isLightMode ? Colors.black87 : neonColor,
      decoration: InputDecoration(
        counterText: "",
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

  Widget _buildContinueButton(bool isLightMode, {VoidCallback? onTap}) {
    if (isLightMode) {
      return SizedBox(
        height: 56,
        width: double.infinity,
        child: _ScaleButton(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeInOutCubic,
                switchOutCurve: Curves.easeInOutCubic,
                child: _isLoading
                    ? const SizedBox(
                        key: ValueKey('loading'),
                        height: 24,
                        width: 24,
                        child: BrandedLoader(isFullScreen: false),
                      )
                    : const Text(
                        'Continue',
                        key: ValueKey('text'),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 56,
      width: double.infinity,
      child: RidelLiquidButton(
        width: double.infinity,
        height: 56,
        enableStretch: false,
        glassTint: neonColor.withValues(alpha: 0.15),
        onTap: onTap,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeInOutCubic,
            switchOutCurve: Curves.easeInOutCubic,
            child: _isLoading
                ? const SizedBox(
                    key: ValueKey('loading'),
                    height: 24,
                    width: 24,
                    child: BrandedLoader(isFullScreen: false),
                  )
                : const Text(
                    'Continue',
                    key: ValueKey('text'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleButton(bool isLightMode, {VoidCallback? onTap}) {
    if (isLightMode) {
      return _ScaleButton(
        onTap: onTap,
        child: Container(
          height: 56,
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

    return _ScaleButton(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(100),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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
          ),
        ),
      ),
    );
  }

  Widget _buildAppleButton(bool isLightMode, {VoidCallback? onTap}) {
    if (isLightMode) {
      return _ScaleButton(
        onTap: onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
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

    return _ScaleButton(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(100),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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
          ),
        ),
      ),
    );
  }
}

class _ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _ScaleButton({required this.child, this.onTap});

  @override
  State<_ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<_ScaleButton> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap == null) return;
    AppHaptics.lightImpact();
    setState(() => _isPressed = true);
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.onTap == null) return;
    setState(() => _isPressed = false);
  }

  void _handleTapCancel() {
    if (widget.onTap == null) return;
    setState(() => _isPressed = false);
  }

  void _handleTap() {
    if (widget.onTap == null) return;
    AppHaptics.mediumImpact();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        child: widget.child,
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
