import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// 🚀 NAYE IMPORTS TIME SCHEDULING KE LIYE
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:ridel/core/utils/toast_service.dart' show ToastService;
import '../services/notification_service.dart';

// ==========================================
// 🧠 SMART PARSER ENGINE
// ==========================================
class NotificationParser {
  static String format(String text, String? userName) {
    if (!text.contains('{{name_logic}}')) return text;

    bool isValidName = userName != null &&
        userName.trim().isNotEmpty &&
        !RegExp(r'^[0-9]+$').hasMatch(userName);

    if (isValidName) {
      String name = userName.trim();
      name = name[0].toUpperCase() + name.substring(1).toLowerCase();
      return text.replaceAll('{{name_logic}}', 'dear $name');
    } else {
      return text.replaceAll(RegExp(r'\s*\{\{name_logic\}\}\s*'), ' ').trim();
    }
  }
}

class NotificationProvider extends ChangeNotifier {
  final NotificationService _dbService = NotificationService();
  final _supabase = Supabase.instance.client;

  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  List<RidelNotification> _allNotifications = [];
  bool _isLoading = true;

  List<RidelNotification> get allNotifications => _allNotifications;
  bool get isLoading => _isLoading;
  int get unreadCount => _allNotifications.where((n) => !n.isRead).length;

  NotificationProvider() {
    _initLocalNotifications();
    _loadFromDatabase();
    _listenToPersonalCloud();
  }

  // ==========================================
  // 🚀 SYSTEM NOTIFICATION SETUP & DEEP LINKING
  // ==========================================
  Future<void> _initLocalNotifications() async {
    if (kIsWeb) {
      debugPrint("📱 Web Mode: Skipping native local notifications setup.");
      return;
    }

    // 🕒 Initialize TimeZones for Offline Scheduling
    tz.initializeTimeZones();
    try {
      dynamic tzResult = await FlutterTimezone.getLocalTimezone();
      // 🚀 Handles both older (String) and newer (Object) versions of the package
      String timeZoneName = tzResult is String ? tzResult : tzResult.name;
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      debugPrint("Could not set local timezone: $e");
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    dynamic plugin = _localNotificationsPlugin;

    await plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint(
            "🚨 LOCAL NOTIFICATION TAPPED! Payload: ${response.payload}");

        if (response.payload != null && response.payload!.isNotEmpty) {
          try {
            final data = jsonDecode(response.payload!);
            if (data['screen'] != null) {
              ToastService.navigatorKey.currentState
                  ?.pushNamed('/${data['screen']}', arguments: data);
            }
          } catch (e) {
            debugPrint("Payload format error: $e");
          }
        }
      },
    );
  }

  Future<void> _loadFromDatabase() async {
    _isLoading = true;
    notifyListeners();

    _allNotifications = List.from(_dbService.notificationsNotifier.value);

    _dbService.notificationsNotifier.addListener(() {
      _allNotifications = List.from(_dbService.notificationsNotifier.value);
      notifyListeners();
    });

    _isLoading = false;
    notifyListeners();
  }

  void _listenToPersonalCloud() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _supabase
        .channel('public:notification_history:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notification_history',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: user.id),
          callback: (payload) {
            final data = payload.newRecord;
            NotificationType nType = NotificationType.system;
            if (data['type'] == 'promo') nType = NotificationType.promo;
            if (data['type'] == 'history') nType = NotificationType.history;
            if (data['type'] == 'important') nType = NotificationType.important;

            String stringPayload = '';
            if (data['payload'] != null) {
              stringPayload = data['payload'] is String
                  ? data['payload']
                  : jsonEncode(data['payload']);
            }

            pushLocalNotification(
              title: data['title'] ?? 'Alert',
              message: data['message'] ?? '',
              type: nType,
              buzzPhone: data['priority'] == 'high',
              payload: stringPayload,
            );
          },
        )
        .subscribe();
  }

  // ==========================================
  // 1️⃣ THE INSTANT TRIGGER (Old Function)
  // ==========================================
  Future<void> pushLocalNotification({
    required String title,
    required String message,
    required NotificationType type,
    DateTime? expiresAt,
    bool buzzPhone = false,
    String? payload,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    String? userName = prefs.getString('user_first_name') ??
        _supabase.auth.currentUser?.userMetadata?['first_name'];

    String finalTitle = NotificationParser.format(title, userName);
    String finalMessage = NotificationParser.format(message, userName);

    if (type == NotificationType.history) {
      NotificationService.saveHistory(finalTitle, finalMessage);
    } else if (type == NotificationType.promo) {
      NotificationService.savePromo(finalTitle, finalMessage,
          expiresAt: expiresAt);
    } else if (type == NotificationType.important) {
      NotificationService.saveImportant(finalTitle, finalMessage);
    } else {
      NotificationService.saveSystem(finalTitle, finalMessage);
    }

    if (buzzPhone) {
      await _triggerSystemPopup(finalTitle, finalMessage, payload: payload);
    }
  }

  // ==========================================
  // 2️⃣ THE TIME TRIGGER (App Band hone par bhi chalega)
  // ==========================================
  Future<void> scheduleTimeNotification({
    required int id,
    required String title,
    required String message,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    if (kIsWeb) return;

    final prefs = await SharedPreferences.getInstance();
    String? userName = prefs.getString('user_first_name') ??
        _supabase.auth.currentUser?.userMetadata?['first_name'];

    String finalTitle = NotificationParser.format(title, userName);
    String finalMessage = NotificationParser.format(message, userName);

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'ridel_offline_alerts',
      'Ridel Offline Alerts',
      channelDescription: 'Reminders that work offline',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    dynamic plugin = _localNotificationsPlugin;

    await plugin.zonedSchedule(
      id,
      finalTitle,
      finalMessage,
      tz.TZDateTime.from(scheduledTime, tz.local),
      platformDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );

    debugPrint(
        "⏰ OS Level Contract Signed: Notification set for $scheduledTime");
  }

  // ==========================================
  // 3️⃣ THE LOCATION TRIGGER (Geofence Prep)
  // ==========================================
  Future<void> registerLocationTrigger({
    required String destinationId,
    required double lat,
    required double lng,
    required String title,
    required String message,
    double radiusInMeters = 500,
  }) async {
    // 🚧 GEOFENCE LOGIC GOES HERE 🚧
    // Jab hum Maps aur Background Location set karenge,
    // toh yahan OS ko (lat, lng, radius) de denge.
    // OS automatically track karega aur app band hone par bhi
    // instant notification fire kar dega.
    debugPrint(
        "📍 Geofence Prep: Registering destination $lat, $lng with $radiusInMeters m radius.");
  }

  // ==========================================
  // 🔔 INTERNAL POPUP LOGIC
  // ==========================================
  Future<void> _triggerSystemPopup(String title, String message,
      {String? payload}) async {
    if (kIsWeb) return;

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'ridel_high_priority',
      'Ridel Journey Alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    dynamic plugin = _localNotificationsPlugin;
    await plugin.show(
        DateTime.now().millisecond, title, message, platformDetails,
        payload: payload);
  }

  Future<void> markAllAsRead() async {
    if (unreadCount > 0) await _dbService.markAllAsRead();
  }

  List<RidelNotification> getImportant() => _allNotifications
      .where((n) =>
          n.type == NotificationType.important ||
          n.type == NotificationType.system)
      .toList();
  List<RidelNotification> getOffers() =>
      _allNotifications.where((n) => n.type == NotificationType.promo).toList();
  List<RidelNotification> getHistory() => _allNotifications
      .where((n) => n.type == NotificationType.history)
      .toList();
}
