import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import '../services/profile_repository.dart';

class MobileVerificationModal extends StatefulWidget {
  final ProfileRepository repository;
  
  const MobileVerificationModal({super.key, required this.repository});

  @override
  State<MobileVerificationModal> createState() => _MobileVerificationModalState();
}

class _MobileVerificationModalState extends State<MobileVerificationModal> {
  final TextEditingController _phoneCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _handleVerify() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty || phone.length < 10) {
      // ✅ Fix: errorImpact ki jagah heavyImpact use karein
      AppHaptics.heavyImpact(); 
      ToastService.showError(context, "Enter a valid 10-digit number");
      return;
    }

    AppHaptics.mediumImpact();
    setState(() => _isLoading = true);

    // Simulation
    await Future.delayed(const Duration(seconds: 1)); 

    if (mounted) {
      setState(() => _isLoading = false);
      Navigator.pop(context); 
      ToastService.showSuccess(context, "OTP Sent to $phone (Simulation)");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Dynamic Colors
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.grey : Colors.grey.shade600;
    final inputBg = isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100;
    final borderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1);

    return Column(
      mainAxisSize: MainAxisSize.min, // ✅ Card ko content jitna chhota rakhega
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Header
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.cyan.withOpacity(0.2) : Colors.cyan.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.phone_iphone_rounded, size: 32, color: Colors.cyan),
          ),
        ),
        const SizedBox(height: 16),
        
        Center(
          child: Text(
            "Link Mobile Number",
            style: GoogleFonts.inter(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            "We'll send a verification code to this number.",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: subTextColor, fontSize: 13),
          ),
        ),
        const SizedBox(height: 25),

        // 2. Input Field
        Text("MOBILE NUMBER", style: GoogleFonts.inter(color: subTextColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: inputBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            style: GoogleFonts.inter(color: textColor, fontWeight: FontWeight.w600, fontSize: 16),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              hintText: "98765 43210",
              hintStyle: TextStyle(color: subTextColor.withOpacity(0.5)),
              prefixIcon: Icon(Icons.dialpad_rounded, color: subTextColor),
            ),
          ),
        ),

        const SizedBox(height: 30),

        // 3. Action Buttons
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleVerify,
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? Colors.white : Colors.black,
              foregroundColor: isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _isLoading 
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text("Send OTP", style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onTap: () {
              AppHaptics.lightImpact();
              Navigator.pop(context);
            },
            child: Text("Cancel", style: GoogleFonts.inter(color: subTextColor, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}