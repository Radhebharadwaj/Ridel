import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static String get olaMapsKey => dotenv.env['OLA_MAPS_API_KEY'] ?? '';
  static String get esriKey => dotenv.env['ESRI_SATELLITE_KEY'] ?? '';

  // ☁️ BACKEND & SVELTEKIT
  static String get backendUrl =>
      dotenv.env['SVELTEKIT_BASE_URL'] ?? 'http://localhost:5000/api';
  static String get cronSecret => dotenv.env['CRON_SECRET_KEY'] ?? '';

// 🟢 SUPABASE
  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL'] ?? 'https://oysalcuewxfxbgeiqcpr.supabase.co';
  static String get supabaseAnonKey =>
      dotenv.env['SUPABASE_ANON_KEY'] ??
      'sb_publishable_tE78qGhZ8qOx8tHrLmhXUw_4RNGzC2L';

  // 🔐 DATA & SECURITY (No Hardcoded URLs in Database Helper!)
  static String get dbDownloadUrl =>
      dotenv.env['DB_DOWNLOAD_URL'] ??
      'https://pixra.pages.dev/api/storage/download';
  static String get keyApiUrl =>
      dotenv.env['DB_KEY_API_URL'] ??
      'https://pixra.pages.dev/api/security/get-key';
  static String get webDataApiUrl =>
      dotenv.env['WEB_DATA_API_URL'] ?? 'https://pixra.pages.dev/api/data/';
  static String get storageBucket =>
      dotenv.env['STORAGE_BUCKET'] ?? 'ridel-storage-master';

  static String get appSecretPasskey {
    // Agar app Localhost (Debug mode) mein run ho rahi hai, toh direct key bhej do
    if (kDebugMode) {
      return "{@*##!/*--GiT*@}{@*##!/*pAsSkEy*@}";
    }
    // Agar app live (Production/Pages.dev) par hai, toh .env use karo
    return dotenv.env['APP_SECRET_PASSKEY'] ??
        "{@*##!/*--GiT*@}{@*##!/*pAsSkEy*@}";
  }
}
