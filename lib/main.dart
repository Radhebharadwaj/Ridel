import 'package:ridel/features/auth/screens/auth_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ✅ CORE CONFIG & SERVICES
import 'package:ridel/core/config/supabase_config.dart';
import 'package:ridel/core/services/mic_service.dart';
import 'package:ridel/core/widgets/navigation_menu.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Note: db_mobile/web imports hata diye gaye hain kyunki ab hum Supabase use kar rahe hain.

void main() async {
  // 1. Bindings Initialize
  WidgetsFlutterBinding.ensureInitialized();

  // Self-Healing Logic for App Lock
  const storage = FlutterSecureStorage();
  final appLock = await storage.read(key: 'isAppLockEnabled');
  if (appLock == 'true') {
    final pin = await storage.read(key: 'userPin');
    if (pin == null) {
      await storage.write(key: 'isAppLockEnabled', value: 'false');
    }
  }

  // 2. Supabase Initialize (Tera Backend Engine)
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  // 3. Firebase Initialize (Agar Web/Mobile notification chahiye future mein)
  // (Currently kept as per your previous setup)
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCTiS3sywccJHHF8oAM0SoKeSr-3caFH50",
        authDomain: "delhi-metro-7a93c.firebaseapp.com",
        databaseURL: "https://delhi-metro-7a93c-default-rtdb.firebaseio.com",
        projectId: "delhi-metro-7a93c",
        storageBucket: "delhi-metro-7a93c.firebasestorage.app",
        messagingSenderId: "551048844061",
        appId: "1:551048844061:web:dd559e3c33d2a92d6f47f4",
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  // 4. Status Bar Style (Transparent)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MicService()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, child) {
        return MaterialApp(
          title: 'Ridel',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFF00E5FF),
            scaffoldBackgroundColor: Colors.black,
            useMaterial3: true,
            fontFamily: 'Sans',
          ),

          // ✅ GLOBAL UI STACK (Black BG + Glass Status Bar)
          builder: (context, child) {
            return Stack(
              children: [
                // 1. Solid Black Base (Prevents Glitches)
                Positioned.fill(
                  child: Container(color: Colors.black),
                ),

                // 2. The App Content
                child!,

                // 3. Glass Status Bar Overlay
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.of(context).padding.top + 10,
                  child: IgnorePointer(
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },

          home: const AuthWrapper(),
        );
      },
    );
  }
}
