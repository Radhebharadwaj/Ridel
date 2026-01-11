import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:math';
import 'package:ridel/core/utils/app_haptics.dart';

enum PinMode { setup, change, unlock }

class PinScreen extends StatefulWidget {
  final PinMode mode;
  final String? oldPin; // Passed when changing PIN to prevent reuse
  const PinScreen({super.key, required this.mode, this.oldPin});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> with SingleTickerProviderStateMixin {
  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();
  
  String _currentPin = "";
  String _tempPin = ""; // For Setup/Change confirm step
  bool _isConfirming = false;
  String _headerText = "";
  
  // Animation
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  
  // Unlock Logic
  int _wrongAttempts = 0;
  bool _isBiometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _initShakeAnimation();
    _checkBiometrics();
    _setHeaderText();
    
    if (widget.mode == PinMode.unlock) {
      _triggerBiometric();
    }
  }

  void _initShakeAnimation() {
    _shakeController = AnimationController(duration: const Duration(milliseconds: 500), vsync: this);
    _shakeAnimation = Tween<double>(begin: 0.0, end: 24.0).chain(CurveTween(curve: Curves.elasticIn)).animate(_shakeController)
      ..addStatusListener((status) {
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
      setState(() {
        _isBiometricAvailable = canCheck && isDeviceSupported && isEnabled;
      });
    }
  }

  void _setHeaderText() {
    setState(() {
      switch (widget.mode) {
        case PinMode.unlock:
          _headerText = "Welcome Back";
          break;
        case PinMode.setup:
          _headerText = "Set New PIN";
          break;
        case PinMode.change:
          _headerText = "Enter Current PIN";
          break;
      }
    });
  }

  Future<void> _triggerBiometric() async {
    if (!_isBiometricAvailable) return;
    try {
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access Ridel',
        options: const AuthenticationOptions(stickyAuth: true, sensitiveTransaction: true),
      );
      if (didAuthenticate) {
        _onSuccess();
      }
    } catch (e) {
      debugPrint("Biometric Error: $e");
    }
  }

  void _handleKeyPress(String value) {
    if (_currentPin.length < 4) {
      AppHaptics.lightImpact();
      setState(() {
        _currentPin += value;
      });
      if (_currentPin.length == 4) {
        _handlePinComplete();
      }
    }
  }

  void _handleDelete() {
    if (_currentPin.isNotEmpty) {
      AppHaptics.lightImpact();
      setState(() {
        _currentPin = _currentPin.substring(0, _currentPin.length - 1);
      });
    }
  }

  Future<void> _handlePinComplete() async {
    switch (widget.mode) {
      case PinMode.unlock:
        final storedPin = await _storage.read(key: 'userPin');
        if (_currentPin == storedPin) {
          _onSuccess();
        } else {
          _onFail();
        }
        break;
        
      case PinMode.setup:
        if (_isConfirming) {
          if (_currentPin == _tempPin) {
            // Save PIN
            await _storage.write(key: 'userPin', value: _currentPin);
            // Also enable App Lock if coming from toggle
            await _storage.write(key: 'isAppLockEnabled', value: 'true');
            if (mounted) {
              Navigator.pop(context, true); // Return success
            }
          } else {
             _triggerShake();
             setState(() {
               _headerText = "PINs do not match. Try again.";
               _currentPin = "";
               _tempPin = "";
               _isConfirming = false;
             });
          }
        } else {
          // First Step Done: New PIN Entered
          // Check for Same PIN constraint
          if (widget.oldPin != null && _currentPin == widget.oldPin) {
             _triggerShake();
             setState(() {
               _headerText = "New PIN cannot be the same.";
               _currentPin = "";
             });
             return;
          }

          setState(() {
            _tempPin = _currentPin;
            _currentPin = "";
            _isConfirming = true;
            _headerText = "Confirm New PIN";
          });
        }
        break;
        
      case PinMode.change:
        final storedPin = await _storage.read(key: 'userPin');
        if (storedPin == null) {
             // No old pin? Switch to setup
             if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const PinScreen(mode: PinMode.setup)));
             return; 
        }

        if (_currentPin == storedPin) {
            // Verified old PIN, now setup new one
             if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => PinScreen(mode: PinMode.setup, oldPin: storedPin)));
        } else {
           _onFail();
        }
        break;
    }
  }
  
  void _onSuccess() {
    AppHaptics.heavyImpact();
    Navigator.pop(context, true); 
  }

  void _onFail() {
    HapticFeedback.vibrate(); 
    _triggerShake();
    setState(() {
      _currentPin = "";
      _wrongAttempts++;
    });
    
    if (_wrongAttempts >= 5) {
       showDialog(
         context: context, 
         barrierDismissible: false,
         builder: (c) => AlertDialog(
           backgroundColor: const Color(0xFF222222),
           title: const Text("Too many attempts", style: TextStyle(color: Colors.white)),
           content: const Text("Please wait 30 seconds.", style: TextStyle(color: Colors.white70)),
           actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK", style: TextStyle(color: Colors.cyan)))],
         )
       );
    }
  }
  
  void _triggerShake() {
     _shakeController.forward();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: (widget.mode == PinMode.unlock) ? null : AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _shakeController,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(sin(_shakeController.value * pi * 4) * 10, 0),
              child: child,
            );
          },
          child: Column(
            children: [
              const SizedBox(height: 40),
              Text(
                _headerText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),
              
              // DOTS
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  bool filled = index < _currentPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 16, height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? Colors.cyanAccent : const Color(0xFF222222),
                      border: Border.all(color: filled ? Colors.cyanAccent : Colors.grey.shade800),
                      boxShadow: filled ? [const BoxShadow(color: Colors.cyanAccent, blurRadius: 10)] : []
                    ),
                  );
                }),
              ),
              
              const Spacer(),
              
              // KEYPAD
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    _buildRow(['1', '2', '3']),
                    const SizedBox(height: 20),
                    _buildRow(['4', '5', '6']),
                    const SizedBox(height: 20),
                    _buildRow(['7', '8', '9']),
                    const SizedBox(height: 20),
                    _buildBottomRow(),
                  ],
                ),
              ),
              
              const SizedBox(height: 40),
              
              if (widget.mode == PinMode.unlock)
                TextButton(
                  onPressed: () {}, 
                  child: Text("Forgot PIN?", style: TextStyle(color: Colors.white.withOpacity(0.5)))
                ),
                
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: keys.map((k) => _buildKey(k)).toList(),
    );
  }
  
  Widget _buildBottomRow() {
     return Row(
       mainAxisAlignment: MainAxisAlignment.spaceBetween,
       children: [
         // Biometric or Empty
         (widget.mode == PinMode.unlock && _isBiometricAvailable)
           ? IconButton(
               icon: const Icon(Icons.fingerprint, color: Colors.cyanAccent, size: 32),
               onPressed: _triggerBiometric,
             )
           : const SizedBox(width: 48), // Spacer
           
         _buildKey('0'),
         
         IconButton(
           icon: const Icon(Icons.backspace_rounded, color: Colors.white, size: 28),
           onPressed: _handleDelete,
         ),
       ],
     );
  }

  Widget _buildKey(String value) {
    return GestureDetector(
      onTap: () => _handleKeyPress(value),
      child: Container(
        width: 70, height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.05),
        ),
        child: Center(
          child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
