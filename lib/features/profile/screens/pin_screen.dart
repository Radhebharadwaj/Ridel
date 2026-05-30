import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:math';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';

enum PinMode { setup, change, unlock }

class PinSheetContent extends StatefulWidget {
  final PinMode mode;
  final String? oldPin;
  const PinSheetContent({super.key, required this.mode, this.oldPin});
  @override
  State<PinSheetContent> createState() => _PinSheetContentState();
}

class _PinSheetContentState extends State<PinSheetContent>
    with SingleTickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();
  String _currentPin = "";
  String _tempPin = "";
  bool _isConfirming = false;
  String _subHeaderText = "";
  late AnimationController _shakeController;

  // 🚀 FIXED: Removed unused _shakeAnimation and _wrongAttempts
  bool _isBiometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _initShakeAnimation();
    _checkBiometrics();
    _setSubHeaderText();
    if (widget.mode == PinMode.unlock) {
      _triggerBiometric();
    }
  }

  void _initShakeAnimation() {
    _shakeController = AnimationController(
        duration: const Duration(milliseconds: 500), vsync: this);
    // 🚀 FIXED: Removed tween assignment as sin-based shake is used in build
    _shakeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _shakeController.reset();
      }
    });
  }

  Future<void> _checkBiometrics() async {
    final canCheck = await _localAuth.canCheckBiometrics;
    final isDeviceSupported = await _localAuth.isDeviceSupported();
    final isEnabled = await _storage.read(key: 'isBiometricEnabled') == 'true';
    if (mounted) {
      setState(() =>
          _isBiometricAvailable = canCheck && isDeviceSupported && isEnabled);
    }
  }

  void _setSubHeaderText() {
    setState(() => _subHeaderText = widget.mode == PinMode.unlock
        ? "Enter your 4-digit PIN"
        : "Choose a 4-digit PIN");
  }

  Future<void> _triggerBiometric() async {
    if (!_isBiometricAvailable) return;
    try {
      final auth = await _localAuth.authenticate(
          localizedReason: 'Authenticate to access Ridel');
      if (auth) {
        _onSuccess();
      }
    } catch (e) {
      debugPrint("Bio Error: $e");
    }
  }

  void _handleKeyPress(String value) {
    if (_currentPin.length < 4) {
      AppHaptics.keypadTap(); // 🚀 UPDATED
      setState(() => _currentPin += value);
      if (_currentPin.length == 4) {
        _handlePinComplete();
      }
    }
  }

  void _handleDelete() {
    if (_currentPin.isNotEmpty) {
      AppHaptics.backspaceTap(); // 🚀 UPDATED
      setState(
          () => _currentPin = _currentPin.substring(0, _currentPin.length - 1));
    }
  }

  Future<void> _handlePinComplete() async {
    switch (widget.mode) {
      case PinMode.unlock:
        final storedPin = await _storage.read(key: 'userPin');
        _currentPin == storedPin ? _onSuccess() : _onFail();
        break;
      case PinMode.setup:
        if (_isConfirming) {
          if (_currentPin == _tempPin) {
            await _storage.write(key: 'userPin', value: _currentPin);
            await _storage.write(key: 'isAppLockEnabled', value: 'true');
            if (mounted) {
              Navigator.pop(context, true);
            }
          } else {
            _triggerShake();
            setState(() {
              _subHeaderText = "PINs do not match. Try again.";
              _currentPin = "";
              _tempPin = "";
              _isConfirming = false;
            });
          }
        } else {
          if (widget.oldPin != null && _currentPin == widget.oldPin) {
            _triggerShake();
            setState(() {
              _subHeaderText = "New PIN cannot be the same.";
              _currentPin = "";
            });
            return;
          }
          setState(() {
            _tempPin = _currentPin;
            _currentPin = "";
            _isConfirming = true;
            _subHeaderText = "Confirm New PIN";
          });
        }
        break;
      case PinMode.change:
        final storedPin = await _storage.read(key: 'userPin');
        if (storedPin == null) {
          if (mounted) {
            RidelSheet.show(context,
                title: "Set New PIN",
                showBackButton: true,
                child: const PinSheetContent(mode: PinMode.setup));
          }
          return;
        }
        if (_currentPin == storedPin) {
          if (mounted) {
            RidelSheet.show(context,
                title: "Set New PIN",
                showBackButton: true,
                child: PinSheetContent(mode: PinMode.setup, oldPin: storedPin));
          }
        } else {
          _onFail();
        }
        break;
    }
  }

  void _onSuccess() {
    AppHaptics.success(); // 🚀 UPDATED from heavyImpact
    Navigator.pop(context, true);
  }

  // Double-heavy buzz matching the shake animation perfectly
  void _onFail() {
    AppHaptics.error(); // 🚀 UPDATED from cheap vibrate()
    _triggerShake();
    setState(() {
      _currentPin = "";
    });
  }

  void _triggerShake() => _shakeController.forward();

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;
    final dotColorEmpty =
        isDark ? const Color(0xFF222222) : Colors.grey.shade300;
    final dotBorderEmpty = isDark ? Colors.grey.shade800 : Colors.grey.shade400;
    final keyBg = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.05);

    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) => Transform.translate(
          offset: Offset(sin(_shakeController.value * pi * 4) * 10, 0),
          child: child),
      child: Column(children: [
        const SizedBox(height: 20),
        Text(_subHeaderText,
            style: TextStyle(color: subTextColor, fontSize: 16)),
        const SizedBox(height: 40),
        Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              bool filled = index < _currentPin.length;
              return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? Colors.cyanAccent : dotColorEmpty,
                      border: Border.all(
                          color: filled ? Colors.cyanAccent : dotBorderEmpty),
                      boxShadow: filled
                          ? [
                              const BoxShadow(
                                  color: Colors.cyanAccent, blurRadius: 10)
                            ]
                          : []));
            })),
        const Spacer(),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(children: [
              _buildRow(['1', '2', '3'], textColor, keyBg),
              const SizedBox(height: 20),
              _buildRow(['4', '5', '6'], textColor, keyBg),
              const SizedBox(height: 20),
              _buildRow(['7', '8', '9'], textColor, keyBg),
              const SizedBox(height: 20),
              _buildBottomRow(textColor, keyBg),
            ])),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _buildRow(List<String> keys, Color textColor, Color bg) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: keys.map((k) => _buildKey(k, textColor, bg)).toList());
  Widget _buildBottomRow(Color textColor, Color bg) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        (widget.mode == PinMode.unlock && _isBiometricAvailable)
            ? IconButton(
                icon: const Icon(Icons.fingerprint,
                    color: Colors.cyanAccent, size: 32),
                onPressed: _triggerBiometric)
            : const SizedBox(width: 48),
        _buildKey('0', textColor, bg),
        IconButton(
            icon: Icon(Icons.backspace_rounded, color: textColor, size: 28),
            onPressed: _handleDelete)
      ]);
  Widget _buildKey(String value, Color textColor, Color bg) => GestureDetector(
      onTap: () => _handleKeyPress(value),
      child: Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
          child: Center(
              child: Text(value,
                  style: TextStyle(
                      color: textColor,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)))));
}
