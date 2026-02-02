import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'pin_screen.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();
  
  bool _isLoading = true;
  bool _isAppLockEnabled = false;
  bool _isBiometricEnabled = false;
  bool _canCheckBiometrics = false;
  
  String _autoLockTimeout = 'Immediately';
  final List<String> _timeoutOptions = ['Immediately', '1 Minute', '5 Minutes', '15 Minutes'];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      setState(() {
        _canCheckBiometrics = canCheck && isDeviceSupported;
      });
    } catch (e) {
      debugPrint('Biometric check failed: $e');
    }
  }

  Future<void> _loadSettings() async {
    final appLock = await _storage.read(key: 'isAppLockEnabled');
    final biometric = await _storage.read(key: 'isBiometricEnabled');
    final timeout = await _storage.read(key: 'autoLockTimeout');

    setState(() {
      _isAppLockEnabled = appLock == 'true';
      _isBiometricEnabled = biometric == 'true';
      _autoLockTimeout = timeout ?? 'Immediately';
      _isLoading = false;
    });
  }

  Future<void> _toggleAppLock(bool value) async {
    AppHaptics.mediumImpact();
    
    if (value) {
      // Enabling: Check if PIN exists
      final pin = await _storage.read(key: 'userPin');
      if (pin == null) {
        // No PIN, go to setup
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const PinScreen(mode: PinMode.setup))
        );
        
        if (result == true) {
           // Success from setup, update state
           setState(() => _isAppLockEnabled = true);
           // Storage is updated in PinScreen logic usually, but we ensure state reflects it
           // Also note PinScreen setup logic writes isAppLockEnabled=true too.
           _loadSettings(); // Reload to be safe
        }
        return;
      }
    }
    
    setState(() => _isAppLockEnabled = value);
    await _storage.write(key: 'isAppLockEnabled', value: value.toString());
  }

  Future<void> _toggleBiometrics(bool value) async {
    AppHaptics.lightImpact();
    setState(() => _isBiometricEnabled = value);
    await _storage.write(key: 'isBiometricEnabled', value: value.toString());
  }

  Future<void> _updateTimeout(String? newValue) async {
    if (newValue == null) return;
    AppHaptics.lightImpact();
    setState(() => _autoLockTimeout = newValue);
    await _storage.write(key: 'autoLockTimeout', value: newValue);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Security & Privacy", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.cyan))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader("App Security"),
                
                // --- Master Switch ---
                _buildSwitchTile(
                  title: "App Lock",
                  subtitle: "Require authentication to open app",
                  icon: Icons.lock_outline_rounded,
                  value: _isAppLockEnabled,
                  onChanged: _toggleAppLock,
                ),

                if (_isAppLockEnabled) ...[
                  const SizedBox(height: 20),
                  
                  // --- Biometrics ---
                  if (_canCheckBiometrics)
                    _buildSwitchTile(
                      title: "Biometric Unlock",
                      subtitle: "Use FaceID or Fingerprint",
                      icon: Icons.fingerprint_rounded,
                      value: _isBiometricEnabled,
                      onChanged: _toggleBiometrics,
                    ),

                  const SizedBox(height: 10),

                  // --- PIN Settings ---
                  _buildActionTile(
                    title: "Change PIN",
                    icon: Icons.password_rounded,
                    onTap: () {
                      AppHaptics.lightImpact();
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const PinScreen(mode: PinMode.change)));
                    },
                  ),

                  const SizedBox(height: 10),

                  // --- Auto Lock Timeout ---
                  _buildDropdownTile(),
                ],

                const SizedBox(height: 20),

                // --- Permissions ---
                _buildActionTile(
                  title: "Manage System Permissions",
                  icon: Icons.settings_applications,
                  onTap: () {
                    AppHaptics.lightImpact();
                    openAppSettings();
                  },
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, left: 5),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(color: Colors.cyanAccent.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF131313),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeColor: Colors.cyanAccent,
        activeTrackColor: Colors.cyan.withOpacity(0.3),
        inactiveThumbColor: Colors.grey,
        inactiveTrackColor: Colors.grey.shade900,
        secondary: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF131313),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 16),
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                const Spacer(),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownTile() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF131313),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.timer_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Auto-Lock Timeout", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 2),
                Text("Lock when app is backgrounded", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ],
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _autoLockTimeout,
              dropdownColor: const Color(0xFF222222),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.cyanAccent),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              onChanged: _updateTimeout,
              items: _timeoutOptions.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
