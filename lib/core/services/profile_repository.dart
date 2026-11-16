import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image/image.dart' as img; // 🚀 Malware protection & compression

class ProfileRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Live UI sync ke liye
  static final ValueNotifier<String> userCity =
      ValueNotifier<String>("Locating...");

  String? get userId => _supabase.auth.currentUser?.id;

  // ==========================================
  // 🛡️ ULTRA-OPTIMIZED SECURE UPLOAD (With Size Limit & JPG Compression)
  // ==========================================
  Future<String?> uploadAvatar(XFile imageFile) async {
    if (userId == null) return null;

    try {
      // 🚀 SMART BARRIER: File Size Limit Check (Max 5 MB)
      // 5 MB = 5 * 1024 * 1024 Bytes
      final int fileSize = await imageFile.length();
      if (fileSize > 5 * 1024 * 1024) {
        // Yeh Exception UI catch karega aur Toast dikhayega
        throw Exception("File is too large! Please upload an image under 5MB.");
      }

      // Agar limit pass ho gayi, tabhi file ko RAM mein read karenge
      final Uint8List rawBytes = await imageFile.readAsBytes();

      // 🛡️ FIREWALL: Decode karke malware destroy karo
      img.Image? decodedImage = img.decodeImage(rawBytes);
      if (decodedImage == null) throw Exception("Invalid image format.");

      // 🗜️ SUPER COMPRESSION: Avatar ke liye 400px width
      img.Image resizedImage = decodedImage;
      if (decodedImage.width > 400) {
        resizedImage = img.copyResize(decodedImage, width: 400);
      }

      // 🚀 FIXED: WebP error hatane ke liye wapas JPG use kiya.
      // 400px par 75 quality ke sath size lagbhag 15-30 KB hi aayega!
      final Uint8List safeBytes = img.encodeJpg(resizedImage, quality: 75);

      final filePath = '$userId/profile.jpg';

      await _supabase.storage.from('avatars').uploadBinary(
            filePath,
            safeBytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      final String publicUrl =
          _supabase.storage.from('avatars').getPublicUrl(filePath);
      return '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('Avatar Upload Error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getProfile() async {
    if (userId == null) return null;
    try {
      return await _supabase
          .from('global_profiles')
          .select()
          .eq('id', userId!)
          .maybeSingle();
    } catch (e) {
      debugPrint('Get Profile Error: $e');
      return null;
    }
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    if (userId == null) return;
    try {
      final safeData = Map<String, dynamic>.from(data);
      safeData.remove('id');
      safeData['updated_at'] = DateTime.now().toUtc().toIso8601String();

      await _supabase
          .from('global_profiles')
          .update(safeData)
          .eq('id', userId!);

      if (safeData.containsKey('city')) {
        userCity.value = safeData['city'];
      } else if (safeData.containsKey('current_city')) {
        userCity.value = safeData['current_city'];
      }
    } catch (e) {
      debugPrint('Update Profile Error: $e');
      rethrow;
    }
  }

  Future<bool> isHandleAvailable(String handle, String currentUserId) async {
    if (handle.isEmpty) return false;
    try {
      final data = await _supabase
          .from('global_profiles')
          .select('id')
          .eq('custom_user_id', handle)
          .maybeSingle();
      if (data == null || data['id'] == currentUserId) return true;
      return false;
    } catch (e) {
      return false;
    }
  }
}
