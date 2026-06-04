// lib/core/services/notification_service.dart


import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

enum NotificationType { system, important, promo, history }

class RidelNotification {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  final DateTime? expiresAt;
  bool isRead;
  bool isSaved;

  RidelNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.expiresAt,
    this.isRead = false,
    this.isSaved = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'isRead': isRead ? 1 : 0,
      'isSaved': isSaved ? 1 : 0,
    };
  }

  factory RidelNotification.fromMap(Map<String, dynamic> map) {
    return RidelNotification(
      id: map['id'],
      title: map['title'],
      message: map['message'],
      type: NotificationType.values.firstWhere((e) => e.name == map['type'],
          orElse: () => NotificationType.system),
      timestamp: DateTime.parse(map['timestamp']),
      expiresAt:
          map['expiresAt'] != null ? DateTime.parse(map['expiresAt']) : null,
      isRead: map['isRead'] == 1,
      isSaved: map['isSaved'] == 1,
    );
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  Database? _db;
  final ValueNotifier<List<RidelNotification>> notificationsNotifier =
      ValueNotifier<List<RidelNotification>>([]);

  Future<void> init() async {
    try {
      if (kIsWeb) {
        _db = await databaseFactoryFfiWeb.openDatabase(
          'ridel_inbox_v4_web.db',
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, version) async {
              await db.execute('''
                CREATE TABLE notifications (
                  id TEXT PRIMARY KEY, title TEXT, message TEXT, type TEXT,
                  timestamp TEXT, expiresAt TEXT, isRead INTEGER DEFAULT 0, isSaved INTEGER DEFAULT 0
                )
              ''');
            },
          ),
        );
      } else {
        final dbPath = await getDatabasesPath();
        final path = join(dbPath, 'ridel_inbox_v4.db');

        _db = await openDatabase(
          path,
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE notifications (
                id TEXT PRIMARY KEY, title TEXT, message TEXT, type TEXT,
                timestamp TEXT, expiresAt TEXT, isRead INTEGER DEFAULT 0, isSaved INTEGER DEFAULT 0
              )
            ''');
          },
        );
      }

      await _autoCleanupExpired();
      await loadNotifications();
    } catch (e) {
      debugPrint('🚨 Notification DB Load Error: $e');
    }
  }

  Future<void> _autoCleanupExpired() async {
    if (_db == null) return;
    final nowStr = DateTime.now().toIso8601String();
    await _db!.delete('notifications',
        where: 'expiresAt IS NOT NULL AND expiresAt < ? AND isSaved = 0',
        whereArgs: [nowStr]);
  }

  Future<void> loadNotifications() async {
    if (_db == null) return;
    final List<Map<String, dynamic>> maps =
        await _db!.query('notifications', orderBy: 'timestamp DESC');

    if (maps.isEmpty) {
      await _saveToInbox(
          title: "Welcome to Ridel 🚀",
          message:
              "Your AI Commute Companion is ready! Explore maps or book a ride.",
          type: NotificationType.system);
    } else {
      notificationsNotifier.value =
          maps.map((map) => RidelNotification.fromMap(map)).toList();
    }
  }

  static Future<void> saveRemotePushToInbox(
      String title, String message, Map<String, dynamic> data) async {
    if (_instance._db == null) await _instance.init();

    NotificationType detectedType = NotificationType.system;
    String lowerTitle = title.toLowerCase();

    if (data['category'] == 'promo' ||
        lowerTitle.contains('off') ||
        lowerTitle.contains('deal') ||
        lowerTitle.contains('discount') ||
        lowerTitle.contains('diwali')) {
      detectedType = NotificationType.promo;
    } else if (data['category'] == 'important' ||
        lowerTitle.contains('alert') ||
        lowerTitle.contains('delay') ||
        lowerTitle.contains('warning') ||
        lowerTitle.contains('urgent')) {
      detectedType = NotificationType.important;
    }

    await _instance._saveToInbox(
        title: title, message: message, type: detectedType);
  }

  Future<void> markAllAsRead() async {
    if (_db == null) return;
    await _db!.update('notifications', {'isRead': 1},
        where: 'isRead = ?', whereArgs: [0]);
    final currentList =
        List<RidelNotification>.from(notificationsNotifier.value);
    bool hasChanges = false;
    for (var n in currentList) {
      if (!n.isRead) {
        n.isRead = true;
        hasChanges = true;
      }
    }
    if (hasChanges) notificationsNotifier.value = currentList;
  }

  Future<void> clearAllNotifications() async {
    if (_db == null) return;
    await _db!.delete('notifications', where: 'isSaved = ?', whereArgs: [0]);
    final currentList =
        List<RidelNotification>.from(notificationsNotifier.value);
    currentList.retainWhere((n) => n.isSaved);
    notificationsNotifier.value = currentList;
  }

  Future<void> deleteNotification(String id) async {
    if (_db != null) {
      await _db!.delete('notifications', where: 'id = ?', whereArgs: [id]);
    }
    final currentList =
        List<RidelNotification>.from(notificationsNotifier.value);
    currentList.removeWhere((n) => n.id == id);
    notificationsNotifier.value = currentList;
  }

  Future<void> toggleSaveNotification(String id, bool currentState) async {
    final newState = !currentState;
    if (_db != null) {
      await _db!.update('notifications', {'isSaved': newState ? 1 : 0},
          where: 'id = ?', whereArgs: [id]);
    }
    final currentList =
        List<RidelNotification>.from(notificationsNotifier.value);
    final index = currentList.indexWhere((n) => n.id == id);
    if (index != -1) {
      currentList[index].isSaved = newState;
      notificationsNotifier.value = currentList;
    }
  }

  bool hasUnreadNotifications() =>
      notificationsNotifier.value.any((n) => !n.isRead);

  // ==========================================================
  // 🟢 FIXED: Removed context param from here to fix main.dart errors
  // ==========================================================
  static Future<void> saveImportant(String title, String msg) async =>
      await _instance._saveToInbox(
          title: title, message: msg, type: NotificationType.important);

  static Future<void> saveHistory(String from, String to) async =>
      await _instance._saveToInbox(
          title: "Journey Completed",
          message: "$from ➔ $to",
          type: NotificationType.history);

  static Future<void> saveSystem(String title, String msg) async =>
      await _instance._saveToInbox(
          title: title, message: msg, type: NotificationType.system);

  static Future<void> savePromo(String title, String msg,
          {DateTime? expiresAt}) async =>
      await _instance._saveToInbox(
          title: title,
          message: msg,
          type: NotificationType.promo,
          expiresAt:
              expiresAt ?? DateTime.now().add(const Duration(hours: 48)));

  Future<void> _saveToInbox(
      {required String title,
      required String message,
      required NotificationType type,
      DateTime? expiresAt}) async {
    final newNotif = RidelNotification(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        message: message,
        type: type,
        timestamp: DateTime.now(),
        expiresAt: expiresAt);

    if (_db != null) {
      await _db!.insert('notifications', newNotif.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    final currentList =
        List<RidelNotification>.from(notificationsNotifier.value);
    currentList.insert(0, newNotif);
    notificationsNotifier.value = currentList;
  }
}
