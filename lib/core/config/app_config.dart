import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class AppConfig {
  static String? _olaMapsKey;

  static String? get olaMapsKey => _olaMapsKey;

  static void clearSession() {
    _olaMapsKey = null;
  }

  static Future<void> fetchKeys() async {
    try {
      final response = await http.get(
        Uri.parse('https://ridel.ridel.workers.dev/get-map-key'),
        headers: {'Admin-Secret': appSecretPasskey},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ola_key'] != null) {
          _olaMapsKey = data['ola_key'];
        } else {
          throw Exception("Missing ola_key in response payload.");
        }
      } else {
        throw Exception("Failed to fetch map keys (Status ${response.statusCode})");
      }
    } catch (e) {
      throw Exception("CRITICAL ERROR: Map keys could not be fetched. $e");
    }
  }

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
