import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import '../services/profile_repository.dart';

class MobileVerificationModal extends StatefulWidget {
  final ProfileRepository repository;

  const MobileVerificationModal({super.key, required this.repository});

  @override
  State<MobileVerificationModal> createState() =>
      _MobileVerificationModalState();
}

class _MobileVerificationModalState extends State<MobileVerificationModal> {
  final TextEditingController _phoneCtrl = TextEditingController(text: "+91");
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final phone = _phoneCtrl.text.trim();

    // Strict Regex Check
    final phoneRegex = RegExp(r'^\+[1-9][0-9]{0,2}[0-9]{10}$');

    if (!phoneRegex.hasMatch(phone)) {
      AppHaptics.error();
      ToastService.showError(
          context, "Enter valid number with country code (e.g. +919876543210)");
      return;
    }

    AppHaptics.buttonClick();
    setState(() => _isLoading = true);

    try {
      // 🚀 FIX 1: 'phone' ki jagah 'phone_number' use kiya (DB se match karne ke liye)
      await widget.repository.updateProfile({'phone_number': phone});

      // 🚀 FIX 2: Async gap ke baad context use karne se pehle mounted check
      if (!mounted) return;

      AppHaptics.success();
      ToastService.showSuccess(context, "Mobile number saved securely!");
      Navigator.pop(context);
    } catch (e) {
      AppHaptics.error();

      // 🚀 FIX 3: Catch block mein bhi mounted check
      if (!mounted) return;
      ToastService.showError(
          context, "Failed to save. Check format and try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.grey : Colors.grey.shade600;
    final inputBg =
        isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.cyan.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.phone_iphone_rounded,
                size: 32, color: Colors.cyan),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            "Link Mobile Number",
            style: GoogleFonts.inter(
                color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            "Provide a valid 10-digit number with country code.",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: subTextColor, fontSize: 13),
          ),
        ),
        const SizedBox(height: 25),
        Text("MOBILE NUMBER",
            style: GoogleFonts.inter(
                color: subTextColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: inputBg,
            borderRadius: BorderRadius.circular(100), // 💊 Capsule
            border: Border.all(color: borderColor),
          ),
          child: TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            style: GoogleFonts.inter(
                color: textColor, fontWeight: FontWeight.w600, fontSize: 16),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              hintText: "+91 9876543210",
              hintStyle: TextStyle(color: subTextColor.withValues(alpha: 0.5)),
              prefixIcon: Icon(Icons.dialpad_rounded, color: subTextColor),
            ),
          ),
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? Colors.white : Colors.black,
              foregroundColor: isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100)), // 💊 Capsule
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : Text("Save Securely",
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
