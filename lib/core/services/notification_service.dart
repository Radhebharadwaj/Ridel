import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

enum NotificationType { info, success, error, promo, system }

class RidelNotification {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  final DateTime? expiresAt;
  bool isRead;

  RidelNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.expiresAt,
    this.isRead = false,
  });

  // 📦 DB me save karne ke liye Map me convert karna
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'type': type.name, // Enum to String
      'timestamp': timestamp.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'isRead': isRead ? 1 : 0, // SQLite boolean ko 0/1 me samajhta hai
    };
  }

  // 📥 DB se wapas Object banane ke liye
  factory RidelNotification.fromMap(Map<String, dynamic> map) {
    return RidelNotification(
      id: map['id'],
      title: map['title'],
      message: map['message'],
      type: NotificationType.values.firstWhere((e) => e.name == map['type'], orElse: () => NotificationType.info),
      timestamp: DateTime.parse(map['timestamp']),
      expiresAt: map['expiresAt'] != null ? DateTime.parse(map['expiresAt']) : null,
      isRead: map['isRead'] == 1,
    );
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  Database? _db;
  final ValueNotifier<List<RidelNotification>> notificationsNotifier = ValueNotifier<List<RidelNotification>>([]);

  // 🚀 1. INITIALIZE DATABASE & LOAD DATA
  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'ridel_notifications.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE notifications (
            id TEXT PRIMARY KEY,
            title TEXT,
            message TEXT,
            type TEXT,
            timestamp TEXT,
            expiresAt TEXT,
            isRead INTEGER
          )
        ''');
      },
    );

    await _autoCleanupExpired(); // Pehle kachra saaf karo
    await loadNotifications();   // Phir DB se load karo
  }

  // 🧹 2. AUTO-CLEANUP (Jo offers expire ho gaye unhe DB se uda do)
  Future<void> _autoCleanupExpired() async {
    if (_db == null) return;
    final nowStr = DateTime.now().toIso8601String();
    await _db!.delete(
      'notifications',
      where: 'expiresAt IS NOT NULL AND expiresAt < ?',
      whereArgs: [nowStr],
    );
  }

  // 📥 3. LOAD FROM LOCAL DB
  Future<void> loadNotifications() async {
    if (_db == null) return;
    
    // Naye wale upar dikhenge (ORDER BY timestamp DESC)
    final List<Map<String, dynamic>> maps = await _db!.query('notifications', orderBy: 'timestamp DESC');
    
    final List<RidelNotification> loadedList = maps.map((map) => RidelNotification.fromMap(map)).toList();
    notificationsNotifier.value = loadedList;
    
    // Agar DB empty hai toh ek default welcome message daal dete hain (Sirf first time)
    if (loadedList.isEmpty) {
      showSystem("Welcome to Ridel 🚀", "Your AI Commute Companion is ready! Turn on location to get started.");
    }
  }

  // ➕ 4. ADD NOTIFICATION (Saves to DB + Updates UI instantly)
  Future<void> addNotification({
    required String title, 
    required String message, 
    required NotificationType type,
    DateTime? expiresAt,
  }) async {
    final newNotif = RidelNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      message: message,
      type: type,
      timestamp: DateTime.now(),
      expiresAt: expiresAt,
    );
    
    // Save to Database
    if (_db != null) {
      await _db!.insert('notifications', newNotif.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // Update UI instantly
    final currentList = List<RidelNotification>.from(notificationsNotifier.value);
    currentList.insert(0, newNotif);
    notificationsNotifier.value = currentList;
  }

  // ✔️ 5. MARK ALL AS READ
  Future<void> markAllAsRead() async {
    if (_db == null) return;

    // Update in Database
    await _db!.update(
      'notifications',
      {'isRead': 1},
      where: 'isRead = ?',
      whereArgs: [0],
    );

    // Update in UI Memory
    final currentList = List<RidelNotification>.from(notificationsNotifier.value);
    bool hasChanges = false;
    for (var n in currentList) {
      if (!n.isRead) {
        n.isRead = true;
        hasChanges = true;
      }
    }
    if (hasChanges) {
      notificationsNotifier.value = currentList; 
    }
  }

  // 🔴 6. CHECK UNREAD FOR RED DOT
  bool hasUnreadNotifications() {
    return notificationsNotifier.value.any((n) => !n.isRead);
  }

  // ==========================================
  // ⚡ QUICK AUTOMATION HELPERS FOR THE APP
  // ==========================================
  
  static void showInfo(String msg) => _instance.addNotification(title: "Info", message: msg, type: NotificationType.info);
  static void showSuccess(String msg) => _instance.addNotification(title: "Success", message: msg, type: NotificationType.success);
  static void showError(String msg) => _instance.addNotification(title: "Error", message: msg, type: NotificationType.error);
  
  // 🎟️ PROMOS (Automated Expiry: Default 24 hours)
  static void showPromo(String title, String msg, {DateTime? expiresAt}) {
    _instance.addNotification(
      title: title, 
      message: msg, 
      type: NotificationType.promo, 
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(hours: 24))
    );
  }

  // 📱 SYSTEM/APP UPDATES
  static void showSystem(String title, String msg) {
    _instance.addNotification(title: title, message: msg, type: NotificationType.system);
  }
}