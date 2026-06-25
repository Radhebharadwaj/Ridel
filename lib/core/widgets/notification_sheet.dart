import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/notification_service.dart';
import '../utils/app_haptics.dart';

class NotificationSheetContent extends StatefulWidget {
  const NotificationSheetContent({super.key});

  @override
  State<NotificationSheetContent> createState() =>
      _NotificationSheetContentState();
}

class _NotificationSheetContentState extends State<NotificationSheetContent> {
  int _selectedFilter = 0;
  bool _showFilters = true; // 🚀 Dynamic Scroll Hide/Show state

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16.0),
          // 🚀 DYNAMIC FILTERS: Scroll par gayab honge, rukne par aayenge
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _showFilters
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      clipBehavior: Clip.none,
                      child: Row(
                        children: [
                          _buildFilterChip(
                              "All", 0, Icons.all_inbox_rounded, isDark),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                              "Saved", 4, Icons.bookmark_rounded, isDark),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                              "Important", 1, Icons.bolt_rounded, isDark),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                              "Offers", 2, Icons.local_offer_rounded, isDark),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                              "History", 3, Icons.history_rounded, isDark),
                        ],
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),

          // 🚀 NOTIFICATIONS LIST WITH SCROLL LISTENER
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is UserScrollNotification) {
                  if (notification.direction == ScrollDirection.reverse) {
                    if (_showFilters) setState(() => _showFilters = false);
                  } else if (notification.direction ==
                      ScrollDirection.forward) {
                    if (!_showFilters) setState(() => _showFilters = true);
                  }
                } else if (notification is ScrollEndNotification) {
                  // Jaise hi scroll rukega, filters wapas aa jayenge
                  if (!_showFilters) setState(() => _showFilters = true);
                }
                return false;
              },
              child: ValueListenableBuilder<List<RidelNotification>>(
                valueListenable: NotificationService().notificationsNotifier,
                builder: (context, allNotifications, child) {
                  List<RidelNotification> displayList;

                  if (_selectedFilter == 1) {
                    displayList = allNotifications
                        .where((n) =>
                            n.type == NotificationType.important ||
                            n.type == NotificationType.system)
                        .toList();
                  } else if (_selectedFilter == 2) {
                    displayList = allNotifications
                        .where((n) => n.type == NotificationType.promo)
                        .toList();
                  } else if (_selectedFilter == 3) {
                    displayList = allNotifications
                        .where((n) => n.type == NotificationType.history)
                        .toList();
                  } else if (_selectedFilter == 4) {
                    displayList =
                        allNotifications.where((n) => n.isSaved).toList();
                  } else {
                    displayList = allNotifications;
                  }

                  final now = DateTime.now();
                  displayList = displayList
                      .where((n) =>
                          n.expiresAt == null || now.isBefore(n.expiresAt!))
                      .toList();

                  if (displayList.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                              _selectedFilter == 4
                                  ? Icons.bookmark_border_rounded
                                  : Icons.notifications_off_outlined,
                              size: 50,
                              color: subTextColor.withValues(alpha: 0.3)),
                          const SizedBox(height: 10),
                          Text(
                            _selectedFilter == 4
                                ? "No saved notifications"
                                : "Nothing to see here yet",
                            style: GoogleFonts.inter(
                                color: subTextColor,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(
                        left: 20, right: 20, top: 4, bottom: 40),
                    physics: const BouncingScrollPhysics(),
                    itemCount: displayList.length,
                    itemBuilder: (context, index) {
                      final notif = displayList[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Dismissible(
                          key: Key(notif.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(100)),
                            child: const Icon(Icons.delete_outline_rounded,
                                color: Colors.redAccent),
                          ),
                          onDismissed: (direction) {
                            AppHaptics.heavyImpact(); // Delete feeling
                            NotificationService().deleteNotification(notif.id);
                          },
                          // 🚀 NEW EXPANDABLE PILL WIDGET
                          child: _ExpandableNotificationPill(
                            notif: notif,
                            isDark: isDark,
                            textColor: textColor,
                            subColor: subTextColor,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFilterChip(String label, int index, IconData icon, bool isDark) {
    final isSelected = _selectedFilter == index;
    const activeColor = CupertinoColors.systemBlue;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.selectionClick();
        setState(() {
          _selectedFilter = index;
          _showFilters = true; // Make sure it stays visible on tap
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.12)
              : (isDark ? const Color(0xFF1E2129) : Colors.white),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSelected
                ? activeColor.withValues(alpha: 0.5)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05)),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 14,
                color: isSelected
                    ? activeColor
                    : (isDark ? Colors.white54 : Colors.black54)),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? activeColor
                    : (isDark ? Colors.white : Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================================
// 🚀 DYNAMIC EXPANDABLE PILL WIDGET (Matte Design)
// ==========================================================
class _ExpandableNotificationPill extends StatefulWidget {
  final RidelNotification notif;
  final bool isDark;
  final Color textColor;
  final Color subColor;

  const _ExpandableNotificationPill({
    required this.notif,
    required this.isDark,
    required this.textColor,
    required this.subColor,
  });

  @override
  State<_ExpandableNotificationPill> createState() =>
      _ExpandableNotificationPillState();
}

class _ExpandableNotificationPillState
    extends State<_ExpandableNotificationPill> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color iconColor;

    switch (widget.notif.type) {
      case NotificationType.important:
        icon = Icons.error_outline_rounded;
        iconColor = Colors.redAccent;
        break;
      case NotificationType.history:
        icon = Icons.route_rounded;
        iconColor = Colors.greenAccent;
        break;
      case NotificationType.promo:
        icon = Icons.local_offer_outlined;
        iconColor = Colors.orangeAccent;
        break;
      case NotificationType.system:
        icon = Icons.info_outline_rounded;
        iconColor = CupertinoColors.systemBlue;
        break;
    }

    return GestureDetector(
      onTap: () {
        AppHaptics.selectionClick(); // Smooth tick on expand/collapse
        setState(() => _isExpanded = !_isExpanded);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: widget.isDark ? 0.2 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: 10, sigmaY: 10), // Glass blur intensity
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                // Dynamic color: Light mode gets light frost, Dark mode gets deep charcoal frost
                color: Theme.of(context).brightness == Brightness.light
                    ? Colors.white.withValues(alpha: 0.6)
                    : Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color:
                      Colors.white.withValues(alpha: 0.2), // Subtle glass edge
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🚀 TOP HEADER ROW (Always visible)
                  LayoutBuilder(builder: (context, constraints) {
                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth < 240
                              ? 240
                              : constraints.maxWidth,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: widget.isDark
                                    ? const Color(0xFF121419)
                                    : iconColor.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: widget.isDark
                                      ? Colors.white.withValues(alpha: 0.03)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Icon(icon, color: iconColor, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Row(
                                children: [
                                  if (!widget.notif.isRead) ...[
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: CupertinoColors.systemBlue,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: CupertinoColors.systemBlue
                                                .withValues(alpha: 0.5),
                                            blurRadius: 6,
                                          )
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: Text(
                                      widget.notif.title,
                                      style: GoogleFonts.inter(
                                        color: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.color ??
                                            widget.textColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1, // Hamesha 1 line pill me
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatTime(widget.notif.timestamp),
                              style: GoogleFonts.inter(
                                color: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color
                                        ?.withValues(alpha: 0.6) ??
                                    widget.subColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  // 🚀 EXPANDED MESSAGE CONTENT
                  AnimatedSize(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _isExpanded
                        ? Padding(
                            padding: const EdgeInsets.only(
                                top: 16.0, left: 4, right: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.notif.message,
                                    style: GoogleFonts.inter(
                                      color: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.color
                                              ?.withValues(alpha: 0.8) ??
                                          widget.subColor,
                                      fontSize: 13,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    AppHaptics
                                        .lightImpact(); // Save krte hi light impact
                                    NotificationService()
                                        .toggleSaveNotification(widget.notif.id,
                                            widget.notif.isSaved);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 16.0),
                                    child: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      child: Icon(
                                        widget.notif.isSaved
                                            ? Icons.bookmark_rounded
                                            : Icons.bookmark_border_rounded,
                                        key: ValueKey(widget.notif.isSaved),
                                        size: 24,
                                        color: widget.notif.isSaved
                                            ? CupertinoColors.systemBlue
                                            : widget.subColor
                                                .withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox(width: double.infinity, height: 0),
                  ),
                ],
              ),
            ),
          ),
        ),
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
