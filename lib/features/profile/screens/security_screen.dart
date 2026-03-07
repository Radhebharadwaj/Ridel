import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart'; 
import 'pin_screen.dart';

class SecuritySheetContent extends StatefulWidget {
  const SecuritySheetContent({super.key});

  @override
  State<SecuritySheetContent> createState() => _SecuritySheetContentState();
}

class _SecuritySheetContentState extends State<SecuritySheetContent> {
  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();
  bool _isLoading = true;
  bool _isAppLockEnabled = false;
  bool _isBiometricEnabled = false;
  bool _canCheckBiometrics = false;
  String _autoLockTimeout = 'Immediately';
  final List<String> _timeoutOptions = ['Immediately', '1 Minute', '5 Minutes', '15 Minutes'];

  @override
  void initState() { super.initState(); _loadSettings(); _checkBiometrics(); }

  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      setState(() => _canCheckBiometrics = canCheck && isDeviceSupported);
    } catch (e) { debugPrint('Bio Error: $e'); }
  }

  Future<void> _loadSettings() async {
    final appLock = await _storage.read(key: 'isAppLockEnabled');
    final biometric = await _storage.read(key: 'isBiometricEnabled');
    final timeout = await _storage.read(key: 'autoLockTimeout');
    setState(() { _isAppLockEnabled = appLock == 'true'; _isBiometricEnabled = biometric == 'true'; _autoLockTimeout = timeout ?? 'Immediately'; _isLoading = false; });
  }

  Future<void> _toggleAppLock(bool value) async {
    AppHaptics.mediumImpact();
    if (value) {
      final pin = await _storage.read(key: 'userPin');
      if (pin == null) {
        final result = await RidelSheet.show<bool>(context, title: "Set New PIN", showBackButton: true, child: const PinSheetContent(mode: PinMode.setup));
        if (result == true) { setState(() => _isAppLockEnabled = true); _loadSettings(); }
        return;
      }
    }
    setState(() => _isAppLockEnabled = value);
    await _storage.write(key: 'isAppLockEnabled', value: value.toString());
  }

  Future<void> _toggleBiometrics(bool value) async { AppHaptics.lightImpact(); setState(() => _isBiometricEnabled = value); await _storage.write(key: 'isBiometricEnabled', value: value.toString()); }
  Future<void> _updateTimeout(String? newValue) async { if (newValue == null) return; AppHaptics.lightImpact(); setState(() => _autoLockTimeout = newValue); await _storage.write(key: 'autoLockTimeout', value: newValue); }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator(color: Colors.cyan)));
    
    // ✅ DYNAMIC COLORS
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileColor = isDark ? const Color(0xFF131313) : Colors.grey.shade100;
    final borderColor = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);
    final textColor = isDark ? Colors.white : Colors.black;
    final iconBg = isDark ? Colors.white.withOpacity(0.05) : Colors.white;
    final iconColor = isDark ? Colors.white : Colors.black87;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 90, left: 20, right: 20, bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildHeader("App Security"),
          _buildSwitchTile(title: "App Lock", subtitle: "Require authentication to open app", icon: Icons.lock_outline_rounded, value: _isAppLockEnabled, onChanged: _toggleAppLock, tileColor: tileColor, textColor: textColor, borderColor: borderColor, iconBg: iconBg, iconColor: iconColor),
          if (_isAppLockEnabled) ...[
            const SizedBox(height: 20),
            if (_canCheckBiometrics) _buildSwitchTile(title: "Biometric Unlock", subtitle: "Use FaceID or Fingerprint", icon: Icons.fingerprint_rounded, value: _isBiometricEnabled, onChanged: _toggleBiometrics, tileColor: tileColor, textColor: textColor, borderColor: borderColor, iconBg: iconBg, iconColor: iconColor),
            const SizedBox(height: 10),
            _buildActionTile(title: "Change PIN", icon: Icons.password_rounded, onTap: () { AppHaptics.lightImpact(); RidelSheet.show(context, title: "Enter Current PIN", showBackButton: true, child: const PinSheetContent(mode: PinMode.change)); }, tileColor: tileColor, textColor: textColor, borderColor: borderColor, iconBg: iconBg, iconColor: iconColor),
            const SizedBox(height: 10),
            _buildDropdownTile(tileColor, textColor, borderColor, iconBg, iconColor, isDark),
          ],
          const SizedBox(height: 20),
          _buildActionTile(title: "Manage System Permissions", icon: Icons.settings_applications, onTap: () { AppHaptics.lightImpact(); openAppSettings(); }, tileColor: tileColor, textColor: textColor, borderColor: borderColor, iconBg: iconBg, iconColor: iconColor),
          const SizedBox(height: 50),
      ]),
    );
  }

  Widget _buildHeader(String title) => Padding(padding: const EdgeInsets.only(bottom: 20, left: 5), child: Text(title.toUpperCase(), style: TextStyle(color: Colors.cyan.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5)));
  
  Widget _buildSwitchTile({required String title, required String subtitle, required IconData icon, required bool value, required ValueChanged<bool> onChanged, required Color tileColor, required Color textColor, required Color borderColor, required Color iconBg, required Color iconColor}) {
    return Container(margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: tileColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)), child: SwitchListTile(value: value, onChanged: onChanged, activeColor: Colors.cyan, activeTrackColor: Colors.cyan.withOpacity(0.3), inactiveThumbColor: Colors.grey, inactiveTrackColor: Colors.grey.withOpacity(0.3), secondary: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle), child: Icon(icon, color: iconColor, size: 22)), title: Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 16)), subtitle: Text(subtitle, style: TextStyle(color: Colors.grey, fontSize: 12)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))));
  }

  Widget _buildActionTile({required String title, required IconData icon, required VoidCallback onTap, required Color tileColor, required Color textColor, required Color borderColor, required Color iconBg, required Color iconColor}) {
    return Container(margin: const EdgeInsets.only(bottom: 12), child: Material(color: tileColor, borderRadius: BorderRadius.circular(16), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20), decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(16)), child: Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle), child: Icon(icon, color: iconColor, size: 22)), const SizedBox(width: 16), Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 16)), const Spacer(), const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16)])))));
  }

  Widget _buildDropdownTile(Color tileColor, Color textColor, Color borderColor, Color iconBg, Color iconColor, bool isDark) {
    return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: tileColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)), child: Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle), child: Icon(Icons.timer_rounded, color: iconColor, size: 22)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Auto-Lock Timeout", style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 16)), const SizedBox(height: 2), Text("Lock when app is backgrounded", style: const TextStyle(color: Colors.grey, fontSize: 12))])), DropdownButtonHideUnderline(child: DropdownButton<String>(value: _autoLockTimeout, dropdownColor: isDark ? const Color(0xFF222222) : Colors.white, icon: const Icon(Icons.arrow_drop_down, color: Colors.cyan), style: TextStyle(color: textColor, fontWeight: FontWeight.bold), onChanged: _updateTimeout, items: _timeoutOptions.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList()))]));
  }
}