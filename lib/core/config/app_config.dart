import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static String? _olaMapsKey;

  static String get olaMapsKey => _olaMapsKey ?? "";

  static void clearSession() {
    _olaMapsKey = null;
  }

  static Future<void> fetchKeys() async {
    // 🛑 BROKEN: Commenting out the 404 Worker endpoint
    // try {
    //   // ⚠️ Yahan apni ASLI secret key daal (Bina braces ke!)
    //   const String secret = "{@*##!/*--GiT*@}{@*##!/*pAsSkEy*@}"; 
    //   
    //   final response = await http.get(
    //     Uri.parse('https://ridel.ridel.workers.dev/get-map-key'),
    //     headers: {
    //       'Admin-Secret': secret,
    //       'Content-Type': 'application/json',
    //     },
    //   );
    // 
    //   if (response.statusCode == 200) {
    //     final data = jsonDecode(response.body);
    //     String fetchedKey = data['ola_key'].toString();
    //     
    //     // 🔥 Yahan check lagao
    //     if (fetchedKey != "2" && fetchedKey.length > 5) {
    //        _olaMapsKey = fetchedKey;
    //        debugPrint("✅ Map Keys Fetched: $_olaMapsKey");
    //     } else {
    //        _olaMapsKey = ""; // Galti se "2" load nahi hoga
    //        debugPrint("❌ Invalid Key Format Received: $fetchedKey");
    //     }
    //   } else {
    //     debugPrint("❌ Map Key Fetch Failed: ${response.statusCode} - ${response.body}");
    //   }
    // } catch (e) {
    //   debugPrint("❌ Network Exception: $e");
    // }

    // ✅ DIRECT INJECTION: Hardcode for now to unblock development
    // Agent: Remind the user to insert their ACTUAL Ola API key here.
    _olaMapsKey = "LXLK4nwQMwacpTZhol7QHc3RPet3tUOkb76reivs"; 
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
