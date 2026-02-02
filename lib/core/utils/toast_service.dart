import 'package:flutter/material.dart';

class ToastService {
  static void showSuccess(BuildContext context, String message) {
    _showToast(context, message, Colors.greenAccent, Icons.check_circle_rounded);
  }

  static void showError(BuildContext context, String message) {
    _showToast(context, message, Colors.redAccent, Icons.error_outline_rounded);
  }

  static void showInfo(BuildContext context, String message) {
    _showToast(context, message, Colors.cyanAccent, Icons.info_outline_rounded);
  }

  static void showWarning(BuildContext context, String message) {
    _showToast(context, message, Colors.orangeAccent, Icons.warning_amber_rounded);
  }

  static void _showToast(BuildContext context, String message, Color color, IconData icon) {
    // Purane snackbars hatao taaki overlap na ho
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF151515).withOpacity(0.95), // Dark Glass
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.5), width: 1),
            boxShadow: [
              // Premium Neon Glow Effect
              BoxShadow(
                color: color.withOpacity(0.15),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}