import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/widgets/ridel_liquid_button.dart'; // 🌟 Added Premium Button Engine

class LoginApprovalSheet extends StatefulWidget {
  final Map<String, dynamic> requestData;

  const LoginApprovalSheet({super.key, required this.requestData});

  @override
  State<LoginApprovalSheet> createState() => _LoginApprovalSheetState();
}

class _LoginApprovalSheetState extends State<LoginApprovalSheet> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isProcessing = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _setupTimeout();
  }

  void _setupTimeout() {
    final requestTimeStr = widget.requestData['time'];
    if (requestTimeStr == null) return;

    try {
      final requestTime = DateTime.parse(requestTimeStr);
      final expiryTime = requestTime.add(const Duration(minutes: 5));
      final timeUntilExpiry = expiryTime.difference(DateTime.now());

      if (timeUntilExpiry.isNegative) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.pop(context, false);
            ToastService.showError(context, "Request has expired.");
          }
        });
      } else {
        _timeoutTimer = Timer(timeUntilExpiry, () {
          if (mounted) {
            Navigator.pop(context, false);
            ToastService.showError(context, "Request expired due to timeout.");
          }
        });
      }
    } catch (e) {
      debugPrint("Time parse error: $e");
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleApproval(bool isApproved) async {
    // AppHaptics is handled directly by RidelLiquidButton now

    if (isApproved) {
      try {
        bool canCheck = await _localAuth.canCheckBiometrics;
        if (!mounted) return;

        bool isSupported = await _localAuth.isDeviceSupported();
        if (!mounted) return;

        if (canCheck && isSupported) {
          bool didAuthenticate = await _localAuth.authenticate(
            localizedReason: 'Please authenticate to approve this login',
          );

          if (!mounted) return;

          if (!didAuthenticate) {
            AppHaptics.error();
            ToastService.showError(context, "Authentication failed.");
            return;
          }
        }
      } catch (e) {
        debugPrint("Biometric Error: $e");
        if (!mounted) return;
        AppHaptics.error();
        ToastService.showError(context, "Biometric check failed.");
        return;
      }
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await Future.delayed(const Duration(seconds: 1)); // Mocking backend

      if (!mounted) return;

      AppHaptics.success();
      Navigator.pop(context, isApproved);
      ToastService.showSuccess(
          context, isApproved ? "Login Approved" : "Login Rejected");
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      setState(() {
        _isProcessing = false;
      });
      ToastService.showError(context, "Failed to process request.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.grey : Colors.grey.shade600;

    final deviceName = widget.requestData['device_name'] ?? 'Unknown Device';
    final location = widget.requestData['location'] ?? 'Current Location';
    final time = widget.requestData['time'] ?? 'Just now';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      // Subtle transparent background for the sheet itself
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0B0E17).withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.cyan.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.security_rounded,
                color: Colors.cyan, size: 40),
          ),
          const SizedBox(height: 20),
          Text(
            "New Login Attempt",
            style: GoogleFonts.inter(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Someone is trying to sign in to your account. Please review the details below.",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: subTextColor,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),

          // Details Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                _buildDetailRow(Icons.devices_rounded, "Device", deviceName,
                    textColor, subTextColor),
                const SizedBox(height: 12),
                _buildDetailRow(Icons.location_on_rounded, "Location", location,
                    textColor, subTextColor),
                const SizedBox(height: 12),
                _buildDetailRow(Icons.access_time_rounded, "Time", time,
                    textColor, subTextColor),
              ],
            ),
          ),

          const SizedBox(height: 30),

          if (_isProcessing)
            Column(
              children: [
                const CircularProgressIndicator(color: Colors.cyan),
                const SizedBox(height: 16),
                Text("Processing...",
                    style: GoogleFonts.inter(color: subTextColor)),
              ],
            )
          else
            Row(
              children: [
                // 🌟 Premium Liquid Reject Button
                Expanded(
                  child: RidelLiquidButton(
                    width: double.infinity,
                    height: 56,
                    enableStretch: true,
                    glassTint: Colors.redAccent
                        .withValues(alpha: 0.15), // Red tinted glass
                    onTap: () => _handleApproval(false),
                    child: Text(
                      "Reject",
                      style: GoogleFonts.inter(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // 🌟 Premium Liquid Approve Button
                Expanded(
                  child: RidelLiquidButton(
                    width: double.infinity,
                    height: 56,
                    enableStretch: true,
                    glassTint: Colors.cyan
                        .withValues(alpha: 0.25), // Cyan tinted glass
                    onTap: () => _handleApproval(true),
                    child: Text(
                      "Approve",
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String title, String value,
      Color textColor, Color subTextColor) {
    return Row(
      children: [
        Icon(icon, color: Colors.cyan, size: 20),
        const SizedBox(width: 12),
        Text(title,
            style: GoogleFonts.inter(color: subTextColor, fontSize: 14)),
        const Spacer(),
        Text(value,
            style: GoogleFonts.inter(
                color: textColor, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}
