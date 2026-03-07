import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../utils/app_haptics.dart';
import '../services/notification_service.dart'; 

class NotificationSheetContent extends StatefulWidget {
  const NotificationSheetContent({super.key});

  @override
  State<NotificationSheetContent> createState() => _NotificationSheetContentState();
}

class _NotificationSheetContentState extends State<NotificationSheetContent> {
  int _selectedFilter = 0; 

  @override
  void initState() {
    super.initState();
    // Sheet open hote hi red dot hatane ke liye sabko Read mark kar do
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().markAllAsRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;

    return Padding(
      // RidelSheet header se safe distance
      padding: const EdgeInsets.only(top: 80.0), 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 💊 1. PREMIUM CAPSULE FILTERS
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildFilterChip("All", 0, isDark),
                  const SizedBox(width: 10),
                  _buildFilterChip("Important", 1, isDark),
                  const SizedBox(width: 10),
                  _buildFilterChip("Offers", 2, isDark),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),

          // 📜 2. FADING NOTIFICATIONS LIST
          Expanded(
            child: ValueListenableBuilder<List<RidelNotification>>(
              valueListenable: NotificationService().notificationsNotifier,
              builder: (context, allNotifications, _) {
                
                // Filtering & Cleaning Expired
                final now = DateTime.now();
                final filteredList = allNotifications.where((n) {
                  if (n.expiresAt != null && now.isAfter(n.expiresAt!)) return false;
                  if (_selectedFilter == 0) return true;
                  if (_selectedFilter == 1) return n.type != NotificationType.promo;
                  if (_selectedFilter == 2) return n.type == NotificationType.promo;
                  return true;
                }).toList();

                if (filteredList.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_off_outlined, size: 50, color: subTextColor.withOpacity(0.3)),
                        const SizedBox(height: 10),
                        Text("No notifications here", style: GoogleFonts.inter(color: subTextColor)),
                      ],
                    ),
                  );
                }

                // 🔥 MAGIC HAPENS HERE: ShaderMask fades the list naturally without any background boxes
                return ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.white,
                        Colors.white,
                        Colors.transparent
                      ],
                      stops: [0.0, 0.05, 0.95, 1.0], // Fade top 5% & bottom 5%
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(left: 20, right: 20, top: 5, bottom: 20),
                    physics: const BouncingScrollPhysics(),
                    itemCount: filteredList.length,
                    separatorBuilder: (_, __) => Divider(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05), height: 1),
                    itemBuilder: (context, index) {
                      final notif = filteredList[index];
                      return _buildNotificationItem(notif, isDark, textColor, subTextColor);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 🔹 PREMIUM CAPSULE WIDGET
  Widget _buildFilterChip(String label, int index, bool isDark) {
    final isSelected = _selectedFilter == index;
    final activeColor = const Color(0xFF00E5FF);
    
    return GestureDetector(
      onTap: () {
        AppHaptics.selectionClick();
        setState(() => _selectedFilter = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected 
              ? activeColor.withOpacity(0.12) 
              : (isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03)),
          borderRadius: BorderRadius.circular(25), // Pill shape
          border: Border.all(
            color: isSelected 
                ? activeColor.withOpacity(0.5) 
                : (isDark ? Colors.white12 : Colors.black12),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? activeColor : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  // 🔹 NOTIFICATION ITEM
  Widget _buildNotificationItem(RidelNotification notif, bool isDark, Color textColor, Color subColor) {
    IconData icon;
    Color iconColor;

    switch (notif.type) {
      case NotificationType.error:
        icon = Icons.error_outline_rounded;
        iconColor = Colors.redAccent;
        break;
      case NotificationType.success:
        icon = Icons.check_circle_outline_rounded;
        iconColor = Colors.greenAccent;
        break;
      case NotificationType.promo:
        icon = Icons.local_offer_outlined;
        iconColor = Colors.orangeAccent;
        break;
      case NotificationType.info:
      default:
        icon = Icons.info_outline_rounded;
        iconColor = const Color(0xFF00E5FF);
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        notif.title,
                        style: GoogleFonts.inter(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      _formatTime(notif.timestamp),
                      style: GoogleFonts.inter(color: subColor, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  notif.message,
                  style: GoogleFonts.inter(color: subColor, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) return "Just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    return DateFormat('MMM d').format(time);
  }
}