import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pin_screen.dart';
import 'package:flutter/foundation.dart';

class SecuritySheetContent extends StatefulWidget {
  const SecuritySheetContent({super.key});

  @override
  State<SecuritySheetContent> createState() => _SecuritySheetContentState();
}

class _SecuritySheetContentState extends State<SecuritySheetContent> {
  final _storage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isAppLockEnabled = false;
  bool _isBiometricEnabled = false;
  bool _canCheckBiometrics = false;
  bool _is2FAEnabled = false; // Global Account Lock
  bool _hasPasskey = false; // Passkey Status
  List<Map<String, dynamic>> _activeDevices = [];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _loadSettings(),
      _checkBiometrics(),
      _fetchActiveDevices(),
      _fetch2FASettings(),
    ]);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetch2FASettings() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final data = await _supabase
          .from('global_profiles')
          .select('requires_2fa')
          .eq('id', user.id)
          .maybeSingle();
      if (data != null && mounted) {
        setState(() => _is2FAEnabled = data['requires_2fa'] ?? false);
      }

      // Check Passkey Status (Mocking for now)
      final pkStatus = await _storage.read(key: 'hasPasskey');
      if (mounted) {
        setState(() => _hasPasskey = pkStatus == 'true');
      }
    } catch (e) {
      debugPrint('2FA Fetch Error: $e');
    }
  }

  Future<void> _fetchActiveDevices() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final data = await _supabase
          .from('user_devices')
          .select()
          .eq('user_id', user.id)
          .order('last_seen', ascending: false);
      if (mounted) {
        setState(() => _activeDevices = List<Map<String, dynamic>>.from(data));
      }
    } catch (e) {
      debugPrint('Device Fetch Error: $e');
    }
  }

  Future<void> _logoutFromDevice(String fcmToken) async {
    AppHaptics.warning();
    try {
      await _supabase.from('user_devices').delete().eq('fcm_token', fcmToken);
      AppHaptics.success();
      _fetchActiveDevices();
    } catch (e) {
      AppHaptics.error();
    }
  }

  Future<void> _toggle2FA(bool value) async {
    AppHaptics.switchToggle();
    setState(() => _is2FAEnabled = value);
    try {
      await _supabase.from('global_profiles').update(
          {'requires_2fa': value}).eq('id', _supabase.auth.currentUser!.id);
    } catch (e) {
      if (mounted) {
        setState(() => _is2FAEnabled = !value);
      }
      AppHaptics.error();
      if (mounted) {
        ToastService.showError(context, "Failed to update Account Lock.");
      }
    }
  }

  Future<void> _setupPasskey() async {
    AppHaptics.lightImpact();
    setState(() => _isLoading = true);
    await Future.delayed(
        const Duration(seconds: 1)); // Simulating FIDO2 Handshake

    await _storage.write(key: 'hasPasskey', value: 'true');
    if (mounted) {
      setState(() {
        _hasPasskey = true;
        _isLoading = false;
      });
      AppHaptics.success();
      ToastService.showSuccess(
          context, "Passkey configured! This device is now your Master Key.");
    }
  }

  Future<void> _checkBiometrics() async {
    if (kIsWeb) {
      return; // 🚀 FIX: Linter ko khush karne ke liye curly braces add kiye
    }

    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      if (mounted) {
        setState(() => _canCheckBiometrics = canCheck && isDeviceSupported);
      }
    } catch (e) {
      debugPrint('Bio Error: $e');
    }
  }

  Future<void> _loadSettings() async {
    final appLock = await _storage.read(key: 'isAppLockEnabled');
    final biometric = await _storage.read(key: 'isBiometricEnabled');
    if (mounted) {
      setState(() {
        _isAppLockEnabled = appLock == 'true';
        _isBiometricEnabled = biometric == 'true';
      });
    }
  }

  Future<void> _toggleAppLock(bool value) async {
    AppHaptics.switchToggle();
    if (value) {
      final pin = await _storage.read(key: 'userPin');
      if (pin == null) {
        if (!mounted) return;
        final result = await RidelSheet.show<bool>(context,
            title: "Set New PIN",
            showBackButton: true,
            child: const PinSheetContent(mode: PinMode.setup));
        if (result == true && mounted) {
          setState(() => _isAppLockEnabled = true);
          _loadSettings();
        }
        return;
      }
    }
    setState(() => _isAppLockEnabled = value);
    await _storage.write(key: 'isAppLockEnabled', value: value.toString());
  }

  Future<void> _toggleBiometrics(bool value) async {
    AppHaptics.switchToggle();
    setState(() => _isBiometricEnabled = value);
    await _storage.write(key: 'isBiometricEnabled', value: value.toString());
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
          height: 300,
          child: Center(child: CircularProgressIndicator(color: Colors.cyan)));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
        isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.grey : Colors.grey.shade600;
    final iconColor = isDark ? Colors.white : Colors.black;
    final dividerColor =
        isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black12;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 90, left: 20, right: 20, bottom: 50),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ==========================================
        // 🌍 GLOBAL ACCOUNT SECURITY
        // ==========================================
        _section("Global Account Security"),
        _card(
            cardColor,
            isDark,
            Column(
              children: [
                _switchTile(
                    Icons.cloud_done_rounded, // 🚀 Universal Icon
                    "Account Lock (2FA)",
                    "Require approval on new logins",
                    _is2FAEnabled,
                    _toggle2FA,
                    iconColor,
                    textColor,
                    subTextColor),
                Divider(height: 1, color: dividerColor),
                _actionTile(
                  Icons.key_rounded, // 🚀 Universal Icon
                  "Passkey Setup",
                  _hasPasskey
                      ? "Master Key Active"
                      : "Use device for passwordless recovery",
                  _hasPasskey ? Colors.cyan : iconColor,
                  textColor, subTextColor,
                  _hasPasskey ? null : _setupPasskey,
                ),
              ],
            )),
        const SizedBox(height: 24),

        // ==========================================
        // 📱 THIS DEVICE SECURITY (LOCAL)
        // ==========================================
        _section("This Device Security"),
        _card(
            cardColor,
            isDark,
            Column(
              children: [
                _switchTile(
                    Icons.lock_outline_rounded,
                    "Local App Lock",
                    "Lock Ridel on this phone only",
                    _isAppLockEnabled,
                    _toggleAppLock,
                    iconColor,
                    textColor,
                    subTextColor),
                if (_isAppLockEnabled) ...[
                  Divider(height: 1, color: dividerColor),
                  if (_canCheckBiometrics) ...[
                    _switchTile(
                        Icons.fingerprint_rounded,
                        "Biometric Unlock",
                        "Use FaceID or Fingerprint",
                        _isBiometricEnabled,
                        _toggleBiometrics,
                        iconColor,
                        textColor,
                        subTextColor),
                    Divider(height: 1, color: dividerColor),
                  ],
                  _actionTile(
                      Icons.password_rounded,
                      "Change PIN",
                      "Update local device PIN",
                      iconColor,
                      textColor,
                      subTextColor, () {
                    AppHaptics.lightImpact();
                    RidelSheet.show(context,
                        title: "Enter Current PIN",
                        showBackButton: true,
                        child: const PinSheetContent(mode: PinMode.change));
                  }),
                ]
              ],
            )),
        const SizedBox(height: 24),

        // ==========================================
        // 💻 CONNECTED DEVICES
        // ==========================================
        _section("Connected Devices"),
        if (_activeDevices.isEmpty)
          _card(
              cardColor,
              isDark,
              const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                      child: Text("No other active sessions",
                          style: TextStyle(color: Colors.grey, fontSize: 13)))))
        else
          _card(
            cardColor,
            isDark,
            ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _activeDevices.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: dividerColor),
              itemBuilder: (context, index) {
                final device = _activeDevices[index];
                final isIOS = device['device_type'] == 'ios';
                return ListTile(
                  leading: Icon(isIOS ? Icons.apple : Icons.android,
                      color: iconColor),
                  title: Text(device['device_name'] ?? 'Unknown Device',
                      style: GoogleFonts.inter(
                          color: textColor,
                          fontWeight: FontWeight.w500,
                          fontSize: 15)),
                  subtitle: Text(
                      "Last seen: ${device['last_seen']?.toString().split('T')[0] ?? 'N/A'}",
                      style:
                          GoogleFonts.inter(color: subTextColor, fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.logout_rounded,
                        color: Colors.redAccent, size: 20),
                    onPressed: () {
                      AppHaptics.buttonClick();
                      _logoutFromDevice(device['fcm_token']);
                    },
                  ),
                );
              },
            ),
          ),
      ]),
    );
  }

  // =========================================================
  // 🎨 EXACT PROFILE SCREEN UI MATCHERS (Using GoogleFonts)
  // =========================================================

  Widget _section(String title) => Align(
      alignment: Alignment.centerLeft,
      child: Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 8),
          child: Text(title.toUpperCase(),
              style: GoogleFonts.inter(
                  color: Colors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2))));

  Widget _card(Color bgColor, bool isDark, Widget child) => Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(30),
      clipBehavior: Clip.antiAlias,
      child: Container(
          decoration: BoxDecoration(
              border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05))),
          child: child));

  Widget _switchTile(
      IconData icon,
      String title,
      String sub,
      bool value,
      ValueChanged<bool> onChanged,
      Color iconColor,
      Color textColor,
      Color subColor) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.cyan,
      activeTrackColor: Colors.cyan.withValues(alpha: 0.3),
      inactiveThumbColor: Colors.grey,
      inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
      secondary: Icon(icon, color: iconColor),
      title: Text(title,
          style: GoogleFonts.inter(
              color: textColor, fontWeight: FontWeight.w500, fontSize: 15)),
      subtitle:
          Text(sub, style: GoogleFonts.inter(color: subColor, fontSize: 12)),
    );
  }

  Widget _actionTile(IconData icon, String title, String sub, Color iconColor,
      Color textColor, Color subColor, VoidCallback? onTap) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title,
          style: GoogleFonts.inter(
              color: textColor, fontWeight: FontWeight.w500, fontSize: 15)),
      subtitle: Text(sub,
          style: GoogleFonts.inter(
              color: onTap == null ? Colors.cyan : subColor, fontSize: 12)),
      trailing: onTap != null
          ? Icon(Icons.chevron_right, color: subColor, size: 18)
          : const Icon(Icons.check_circle_rounded,
              color: Colors.cyan, size: 18),
      onTap: onTap,
    );
  }
}
