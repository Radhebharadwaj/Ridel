import 'package:flutter/foundation.dart'; // kIsWeb ke liye
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart'; // Provider Package
import 'package:supabase_flutter/supabase_flutter.dart';

// ✅ Database Imports (Web Support)
import 'package:sqflite/sqflite.dart'; 
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

// ✅ Project Imports
import 'core/config/supabase_config.dart';
import 'core/map/map_provider.dart'; 
import 'core/services/theme_service.dart';
import 'core/theme/app_theme.dart';
import 'features/commute/metro/services/metro_service.dart';
import 'features/commute/metro/map/metro_data_provider.dart'; 

import 'layout/main_layout.dart'; 

import 'core/services/global_location_service.dart';
import 'package:ridel/core/providers/app_navigation_provider.dart';

// 🚀 NAYA IMPORT: Humari Local Notification Service
import 'core/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🌍 1. WEB DATABASE INIT (CRITICAL FIX FOR SQL WARNINGS)
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
    print("🌍 Web Database Factory Initialized!");
  }

  // 🚀 2. SUPABASE INITIALIZATION
  try {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
    print("✅ Supabase Initialized Successfully");
  } catch (e) {
    print("❌ Supabase Init Error: $e");
  }

  // 🚇 3. METRO DATABASE (Background Load)
  MetroService().initialize();

  // 🔔 4. NOTIFICATION DATABASE (Load Old Notifications & Auto-Clean Expired)
  await NotificationService().init();
  print("✅ Local Notification Database Initialized");

  // 🎨 5. UI SETTINGS (Premium Edge-to-Edge)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent, 
      systemNavigationBarColor: Colors.transparent, 
      statusBarIconBrightness: Brightness.dark, 
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(
    MultiProvider(
      providers: [
        // 🔥 GLOBAL MAP PROVIDER 
        ChangeNotifierProvider(create: (_) => MapProvider()),

        // 🔥 METRO DATA PROVIDER 
        ChangeNotifierProvider(create: (_) => MetroDataProvider()),

        // 🚀 THE NEW BRAIN: GLOBAL LOCATION PROVIDER
        ChangeNotifierProvider(
          create: (_) => GlobalLocationService()..initializeEcoLocation(),
        ),

        // 🚀 NAVIGATION PROVIDER
        ChangeNotifierProvider(create: (_) => AppNavigationProvider()),
      ],
      child: const RidelApp(),
    ),
  );
}

class RidelApp extends StatelessWidget {
  const RidelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([ThemeService.themeNotifier, ThemeService.fontNotifier]),
      builder: (context, _) {
        final currentMode = ThemeService.themeNotifier.value;
        final currentFont = ThemeService.fontNotifier.value;

        return MaterialApp(
          title: 'Ridel',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.getLightTheme(currentFont),
          darkTheme: AppTheme.getDarkTheme(currentFont),
          themeMode: currentMode,
          
          home: const MainLayout(), 
        );
      },
    );
  }
}