import 'dart:async';
import 'dart:convert';
import 'dart:ui';

// Firebase & Notifications
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
// Project imports
import 'package:ridel/core/config/app_config.dart';
import 'package:ridel/core/providers/app_navigation_provider.dart';
import 'package:ridel/core/utils/toast_service.dart';
import 'package:ridel/features/auth/screens/splash_screen.dart';
import 'package:ridel/core/widgets/app_gate_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:url_launcher/url_launcher.dart';

import 'core/map/map_provider.dart';
import 'core/providers/notification_provider.dart';
import 'core/services/global_location_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/theme_service.dart';
import 'core/theme/app_theme.dart';
import 'features/commute/metro/map/metro_data_provider.dart';
import 'features/commute/metro/services/metro_service.dart';
import 'features/commute/shared/services/database_helper.dart';
import 'package:ridel/core/utils/app_haptics.dart';
import 'package:ridel/core/widgets/ridel_sheet.dart';
import 'package:ridel/features/auth/widgets/login_approval_sheet.dart';
import 'package:ridel/features/auth/services/auth_service.dart';


// ======================================================================
// 🚀 GLOBAL APP STATES
// ======================================================================

final ValueNotifier<int> globalTransportMode = ValueNotifier<int>(0);
final ValueNotifier<bool> globalSidebarOpen = ValueNotifier<bool>(true);
final ValueNotifier<bool> globalSearchSheetOpen = ValueNotifier<bool>(true);
final ValueNotifier<bool> globalIsHome = ValueNotifier<bool>(true);

// globalNavigatorKey is imported from toast_service.dart

// ----------------------------------------------------------------------
// 🔔 BACKGROUND HANDLER (Mobile Only)
// ----------------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) {
    return;
  }

  await Firebase.initializeApp();
  final prefs = await SharedPreferences.getInstance();
  String? userName = prefs.getString('user_first_name');

  String rawTitle = message.notification?.title ?? 'Ridel Alert';
  String rawBody = message.notification?.body ?? '';

  String finalTitle = NotificationParser.format(rawTitle, userName);
  String finalBody = NotificationParser.format(rawBody, userName);

  await NotificationService.saveRemotePushToInbox(
      finalTitle, finalBody, message.data);

  dynamic flutterPlugin = FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings iosInit = DarwinInitializationSettings();
  const InitializationSettings initSettings =
      InitializationSettings(android: androidInit, iOS: iosInit);

  await flutterPlugin.initialize(initSettings);

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'ridel_high_priority',
    'Ridel Journey Alerts',
    importance: Importance.max,
    priority: Priority.high,
  );

  await flutterPlugin.show(
    message.hashCode,
    finalTitle,
    finalBody,
    const NotificationDetails(android: androidDetails),
    payload: jsonEncode(message.data),
  );
}

// ----------------------------------------------------------------------
// 🚀 MAIN FUNCTION
// ----------------------------------------------------------------------
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('⚠️ FLUTTER UI ERROR: ${details.exception}');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('🔥 PLATFORM ERROR: $error');
      return true; 
    };

    ThemeService.init();
    MetroService().initialize(); // Sync init early

    // 1. Parallel Independent Initializations
    await Future.wait([
      AppHaptics.init(),
      dotenv.load(fileName: ".env").catchError((e) {
        debugPrint("❌ Env Error: $e");
        return null;
      }),
    ]);

    // 2. Parallel Dependent Initializations
    await Future.wait([
      () async {
        try {
          if (kIsWeb) {
            await Firebase.initializeApp(
              options: const FirebaseOptions(
                apiKey: "AIzaSyCylXea35MHpJ4SlcODDAgB5wj6h5SgnzY",
                authDomain: "pixra-ridel.firebaseapp.com",
                projectId: "pixra-ridel",
                storageBucket: "pixra-ridel.firebasestorage.app",
                messagingSenderId: "20390923828",
                appId: "1:20390923828:web:8206196e9cfd1b16790461",
                measurementId: "G-NK274DS7S2",
              ),
            );
          } else {
            await Firebase.initializeApp();
            FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
          }
          debugPrint("🔥 Firebase Ready!");
        } catch (e) {
          debugPrint("❌ Firebase Error: $e");
        }
        await NotificationService().init();
      }(),
      () async {
        try {
          await Supabase.initialize(
            url: AppConfig.supabaseUrl,
            anonKey: AppConfig.supabaseAnonKey,
          );

          final supabaseClient = Supabase.instance.client;
          if (supabaseClient.auth.currentSession != null) {
            DatabaseHelper.instance.initBackgroundSync();
            AuthService().setupAndSaveDeviceToken();
          }
        } catch (e) {
          debugPrint("❌ Supabase Error: $e");
        }
      }(),
    ]);

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MapProvider()),
          ChangeNotifierProvider(create: (_) => MetroDataProvider()),
          ChangeNotifierProvider(
              create: (_) => GlobalLocationService()..initializeEcoLocation()),
          ChangeNotifierProvider(create: (_) => AppNavigationProvider()),
          ChangeNotifierProvider(
              create: (_) => NotificationProvider(), lazy: false),
        ],
        child: const RidelApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('⚡ ASYNC ZONE ERROR: $error');
  });
}

// ----------------------------------------------------------------------
// 📱 APP WIDGET
// ----------------------------------------------------------------------
class RidelApp extends StatefulWidget {
  const RidelApp({super.key});
  @override
  State<RidelApp> createState() => _RidelAppState();
}

class _RidelAppState extends State<RidelApp> {
  @override
  void initState() {
    super.initState();
    _setupInteractedMessage();
  }

  Future<void> _setupInteractedMessage() async {
    // 2FA & Notification Listeners
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      // 🚀 Security Alert Trigger
      if (message.data['type'] == '2fa_request') {
        if (ToastService.navigatorKey.currentContext != null) {
          AppHaptics.heavyImpact();
          RidelSheet.show(
            ToastService.navigatorKey.currentContext!,
            title: "Security Alert",
            showBackButton: false,
            child: LoginApprovalSheet(requestData: message.data),
          );
        }
        return;
      }

      // Regular Notification Logic
      final prefs = await SharedPreferences.getInstance();
      String? userName = prefs.getString('user_first_name');
      String finalTitle = NotificationParser.format(
          message.notification?.title ?? 'Ridel Alert', userName);
      String finalBody =
          NotificationParser.format(message.notification?.body ?? '', userName);

      await NotificationService.saveRemotePushToInbox(
          finalTitle, finalBody, message.data);

      if (mounted) {
        ToastService.showInfo(context, finalTitle,
            onTap: () => _handleNotificationClick(message.data));
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationClick(message.data);
    });
  }

  void _handleNotificationClick(Map<String, dynamic> data) {
    Future.delayed(const Duration(milliseconds: 500), () async {
      if (data['type'] == '2fa_request') {
        if (ToastService.navigatorKey.currentContext != null) {
          RidelSheet.show(
            ToastService.navigatorKey.currentContext!,
            title: "Security Alert",
            showBackButton: false,
            child: LoginApprovalSheet(requestData: data),
          );
        }
      } else if (data['type'] == 'external_link' && data['url'] != null) {
        final url = Uri.parse(data['url']);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      } else if (data['type'] == 'internal_screen' && data['screen'] != null) {
        final screen = data['screen'];
        ToastService.navigatorKey.currentState
            ?.pushNamed('/${screen.toString().toLowerCase()}', arguments: data);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
          [ThemeService.themeNotifier, ThemeService.fontNotifier]),
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: ToastService.navigatorKey,
          title: 'Ridel',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.getLightTheme(ThemeService.fontNotifier.value),
          darkTheme: AppTheme.getDarkTheme(ThemeService.fontNotifier.value),
          themeMode: ThemeService.themeNotifier.value,
          themeAnimationDuration: const Duration(milliseconds: 850),
          themeAnimationCurve: Curves.easeInOutQuart,
          scrollBehavior: const _AppScrollBehavior(),
          home: const AppGateOverlay(child: SplashScreen()),
        );
      },
    );
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.mouse,
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
      };
}
