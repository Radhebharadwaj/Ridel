import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 🔥 kIsWeb ke liye
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../core/utils/toast_service.dart'; // 🔥 Web message ke liye

class PermissionsCenterSheet extends StatefulWidget {
  const PermissionsCenterSheet({super.key});

  @override
  State<PermissionsCenterSheet> createState() => _PermissionsCenterSheetState();
}

class _PermissionsCenterSheetState extends State<PermissionsCenterSheet>
    with WidgetsBindingObserver {
  Map<Permission, PermissionStatus> _statuses = {};

  // 🔥 Names short kar diye taaki text wrap na ho
  final List<Map<String, dynamic>> _permissionsList = [
    {
      'title': 'Location',
      'permission': Permission.location,
      'icon': CupertinoIcons.location_solid
    },
    {
      'title': 'Notifications',
      'permission': Permission.notification,
      'icon': CupertinoIcons.bell_solid
    },
    {
      'title': 'Camera',
      'permission': Permission.camera,
      'icon': CupertinoIcons.camera_fill
    },
    {
      'title': 'Microphone',
      'permission': Permission.microphone,
      'icon': CupertinoIcons.mic_solid
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAllPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllPermissions();
    }
  }

  Future<void> _checkAllPermissions() async {
    Map<Permission, PermissionStatus> statuses = {};
    for (var item in _permissionsList) {
      final perm = item['permission'] as Permission;
      statuses[perm] = await perm.status;
    }
    if (mounted) setState(() => _statuses = statuses);
  }

  Future<void> _handlePermissionToggle(Permission permission) async {
    AppHaptics.selectionClick();

    // 🌐 WEB HANDLING: Web browser direct settings open allow nahi karte
    if (kIsWeb) {
      ToastService.showInfo(context,
          "Tap the Lock (🔒) icon in your browser's address bar to change permissions.");
      return;
    }

    var status = await permission.status;

    // 📱 MOBILE HANDLING
    // Rule: Agar allow ho chuki hai, toh app code se deny NAHI kar sakta.
    // Isliye unhe OS Settings bhejte hain.
    if (status.isGranted || status.isPermanentlyDenied) {
      openAppSettings();
    } else {
      var newStatus = await permission.request();
      setState(() {
        _statuses[permission] = newStatus;
      });
      if (newStatus.isPermanentlyDenied) {
        openAppSettings();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final textColor = isLightMode ? Colors.black87 : Colors.white;
    final subColor = isLightMode ? Colors.black54 : Colors.white54;
    const activeColor = CupertinoColors.systemBlue; // Premium System Blue

    return Material(
      color: isLightMode ? Colors.white : const Color(0xFF16181D),
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔹 Premium Minimal Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Permissions",
                    style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        letterSpacing: -0.5)),
                GestureDetector(
                  onTap: () {
                    AppHaptics.lightImpact();
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isLightMode ? Colors.black12 : Colors.white12,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close, color: textColor, size: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 🔹 Ultra-Sleek Glassmorphic List Container
            Container(
              decoration: BoxDecoration(
                color: isLightMode ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                // 🔥 Hairline border for that crisp glass edge
                border: Border.all(
                  color: isLightMode
                      ? Colors.black.withValues(alpha: 0.05)
                      : Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: Column(
                children: _permissionsList.asMap().entries.map((entry) {
                  int idx = entry.key;
                  var item = entry.value;
                  final perm = item['permission'] as Permission;
                  final status = _statuses[perm] ?? PermissionStatus.denied;
                  final isGranted = status.isGranted;
                  final isLast = idx == _permissionsList.length - 1;

                  return Column(
                    children: [
                      InkWell(
                        onTap: () => _handlePermissionToggle(perm),
                        borderRadius: BorderRadius.circular(isLast ? 20 : 0),
                        highlightColor: isLightMode
                            ? Colors.black.withValues(alpha: 0.02)
                            : Colors.white.withValues(alpha: 0.03),
                        splashColor: isLightMode
                            ? Colors.black.withValues(alpha: 0.02)
                            : Colors.white.withValues(alpha: 0.03),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              // 💎 Sleek Icon Box (Smaller & cleaner)
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: isGranted
                                      ? activeColor.withValues(alpha: 0.12)
                                      : (isLightMode
                                          ? Colors.black.withValues(alpha: 0.04)
                                          : Colors.white.withValues(alpha: 0.05)),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(item['icon'],
                                    color: isGranted
                                        ? activeColor
                                        : textColor.withValues(alpha: 0.7),
                                    size: 16),
                              ),
                              const SizedBox(width: 12),

                              // 💎 Text (maxLines 1 added to prevent wrapping)
                              Expanded(
                                child: Text(item['title'],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                        color: textColor,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14)),
                              ),

                              // 💎 Micro Status Badge (Pill shaped, elegant)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                    color: isGranted
                                        ? CupertinoColors.systemGreen
                                            .withValues(alpha: 0.15)
                                        : (isLightMode
                                            ? Colors.black
                                                .withValues(alpha: 0.05)
                                            : Colors.white.withValues(alpha: 0.1)),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: isGranted
                                            ? CupertinoColors.systemGreen
                                                .withValues(alpha: 0.2)
                                            : Colors.transparent,
                                        width: 0.5)),
                                child: Text(
                                  isGranted ? "Allowed" : "Denied",
                                  style: GoogleFonts.inter(
                                    color:
                                        isGranted ? CupertinoColors.systemGreen : subColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),

                              const SizedBox(width: 10),
                              Icon(Icons.arrow_forward_ios_rounded,
                                  color: subColor.withValues(alpha: 0.4),
                                  size: 12),
                            ],
                          ),
                        ),
                      ),
                      if (!isLast)
                        Divider(
                            color: subColor.withValues(alpha: 0.1),
                            height: 1,
                            indent: 55,
                            endIndent: 15),
                    ],
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 15),

            // 🔹 Footer Info (Web vs Mobile dynamic text)
            Text(
              kIsWeb
                  ? "Use your browser's address bar (🔒) to manage site permissions."
                  : "For security, some permissions must be managed in your device settings.",
              style:
                  GoogleFonts.inter(color: subColor, fontSize: 11, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
