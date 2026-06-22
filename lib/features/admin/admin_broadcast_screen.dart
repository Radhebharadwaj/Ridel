// lib/features/admin/admin_broadcast_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:ridel/core/config/app_config.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/core/widgets/ridel_glass.dart';
import 'package:ridel/core/widgets/ridel_liquid_button.dart';
import 'package:ridel/core/widgets/branded_loader.dart';

class AdminBroadcastScreen extends StatefulWidget {
  const AdminBroadcastScreen({super.key});

  @override
  State<AdminBroadcastScreen> createState() => _AdminBroadcastScreenState();
}

class _AdminBroadcastScreenState extends State<AdminBroadcastScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();

  bool _isLoading = false;

  Future<void> _sendBroadcast() async {
    final title = _titleController.text.trim();
    final message = _messageController.text.trim();
    final deepLink = _linkController.text.trim();

    if (title.isEmpty || message.isEmpty) {
      if (mounted) ToastService.showError(context, "Title and message are required.");
      return;
    }

    // You can use a specific Admin Secret from config. Here using appSecretPasskey as a fallback.
    final adminSecret = AppConfig.appSecretPasskey; 
    if (adminSecret.isEmpty) {
      if (mounted) ToastService.showError(context, "Admin secret is missing in env configuration.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final url = Uri.parse('https://ridel.ridel.workers.dev/admin/broadcast');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Admin-Secret': adminSecret,
        },
        body: jsonEncode({
          'title': title,
          'body': message,
          'deepLink': deepLink,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        AppHaptics.heavyImpact();
        ToastService.showSuccess(context, "Broadcast sent to all users!");
        _titleController.clear();
        _messageController.clear();
        _linkController.clear();
      } else {
        AppHaptics.warning();
        final errorMsg = jsonDecode(response.body)['error'] ?? 'Unknown Error';
        ToastService.showError(context, "Failed: $errorMsg");
      }
    } catch (e) {
      if (!mounted) return;
      AppHaptics.warning();
      ToastService.showError(context, "Network Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // 🎨 Premium Gradient Background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          const Color(0xFF0F172A),
                          const Color(0xFF0B0E17),
                          const Color(0xFF1E1E1E),
                        ]
                      : [
                          const Color(0xFFE2E8F0),
                          const Color(0xFFF1F5F9),
                          const Color(0xFFFFFFFF),
                        ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _buildHeader(isDark),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildInfoCard(isDark),
                        const SizedBox(height: 24),
                        _buildTextField(
                          controller: _titleController,
                          label: "Notification Title",
                          hint: "e.g. 🚨 Service Disruption Alert",
                          icon: Icons.title_rounded,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _messageController,
                          label: "Message Body",
                          hint: "Details of the broadcast...",
                          icon: Icons.message_rounded,
                          maxLines: 4,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _linkController,
                          label: "Deep Link URL (Optional)",
                          hint: "https://... or app specific link",
                          icon: Icons.link_rounded,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 36),
                        _buildBroadcastButton(isDark),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: isDark ? Colors.white : Colors.black87),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Push Command Center",
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  "Global Broadcast to All Users",
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(bool isDark) {
    return RidelGlass(
      blurSigma: 20,
      baseColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.campaign_rounded, color: Colors.amber, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              "Warning: This will immediately send a push notification to EVERY user subscribed to the 'all_users' topic.",
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.black87,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
        RidelGlass(
          blurSigma: 15,
          baseColor: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(
                color: isDark ? Colors.white30 : Colors.black38,
              ),
              prefixIcon: maxLines == 1
                  ? Icon(icon, color: isDark ? Colors.white54 : Colors.black54, size: 20)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 50),
                      child: Icon(icon, color: isDark ? Colors.white54 : Colors.black54, size: 20),
                    ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBroadcastButton(bool isDark) {
    if (_isLoading) {
      return const Center(
        child: BrandedLoader(isFullScreen: false),
      );
    }

    return RidelLiquidButton(
      height: 56,
      onTap: _sendBroadcast,
      customGradient: const LinearGradient(
        colors: [Color(0xFF0A84FF), Color(0xFF005ECB)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      glassTint: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Text(
            "Send Global Broadcast",
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}
