import 'package:flutter/material.dart';

// 🔔 Notification ki Categories
enum NotificationCategory { info, success, offer, important }

// 📦 Notification ka Data Structure
class AppNotification {
  final String id;
  final String title;
  final String message;
  final NotificationCategory category;
  final DateTime timestamp;
  bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.category,
    required this.timestamp,
    this.isRead = false,
  });
}

class NotificationProvider extends ChangeNotifier {
  // 📝 Dummy Data (Tumhare screenshot jaisa)
  final List<AppNotification> _notifications = [
    AppNotification(
      id: '1',
      title: 'Welcome to Ridel!',
      message: 'Your AI travel companion is ready. Start exploring now.',
      category: NotificationCategory.info,
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
    ),
    AppNotification(
      id: '2',
      title: 'Profile Updated',
      message: 'Your profile details have been saved successfully.',
      category: NotificationCategory.success,
      timestamp: DateTime.now().subtract(const Duration(days: 1)),
    ),
    AppNotification(
      id: '3',
      title: '30% Off on Metro Cards',
      message: 'Get discount on your first smart card recharge.',
      category: NotificationCategory.offer,
      timestamp: DateTime.now().subtract(const Duration(days: 2)),
    ),
  ];

  // 🔍 Getters for Tabs
  List<AppNotification> get allNotifications => _notifications;
  
  List<AppNotification> get importantNotifications => 
      _notifications.where((n) => n.category == NotificationCategory.important || n.category == NotificationCategory.info).toList();
      
  List<AppNotification> get offerNotifications => 
      _notifications.where((n) => n.category == NotificationCategory.offer).toList();

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  // 🚀 Naya Notification add karne ka function (Kahin se bhi call kar sakte ho)
  void addNotification({
    required String title,
    required String message,
    required NotificationCategory category,
  }) {
    final newNotif = AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      message: message,
      category: category,
      timestamp: DateTime.now(),
    );
    _notifications.insert(0, newNotif); // Sabse upar add hoga
    notifyListeners();
  }

  // 👀 Jab user panel khole toh sabko "Read" mark kar do
  void markAllAsRead() {
    for (var n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  // 🗑️ Delete Notification
  void removeNotification(String id) {
    _notifications.removeWhere((n) => n.id == id);
    notifyListeners();
  }
}