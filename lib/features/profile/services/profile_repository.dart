import 'dart:io';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart'; // Required for XFile

class ProfileRepository {
  final _supabase = Supabase.instance.client;

  String? get userId => _supabase.auth.currentUser?.id;

  // 1. Get Profile
  Future<Map<String, dynamic>?> getProfile() async {
    try {
      if (userId == null) return null;
      return await _supabase.from('user_profiles').select().eq('id', userId!).single();
    } catch (e) {
      debugPrint('❌ Error fetching: $e');
      return null;
    }
  }

  // 2. Update Profile (Accepts Map & Returns Updated Data)
  Future<Map<String, dynamic>?> updateProfile(Map<String, dynamic> updates) async {
    try {
      if (userId == null) throw "User not logged in";

      // Fetch current data to merge
      final currentData = await getProfile() ?? {};
      final mergedData = {...currentData, ...updates};

      // Validation Logic
      bool isCompleted = false;
      String name = mergedData['full_name'] ?? '';
      String phone = mergedData['phone_primary'] ?? '';

      if (name.trim().length > 3 && phone.trim().length >= 10) {
        isCompleted = true;
      }

      final finalUpdates = {
        ...updates,
        'updated_at': DateTime.now().toIso8601String(),
        'is_profile_completed': isCompleted,
      };

      // Perform update and return the modified row immediately
      final updatedRow = await _supabase
          .from('user_profiles')
          .update(finalUpdates)
          .eq('id', userId!)
          .select()
          .single();

      return updatedRow; 
    } catch (e) {
      debugPrint('❌ Error updating: $e');
      return null;
    }
  }

  // 3. Upload Avatar (Web & Mobile Compatible)
  Future<String?> uploadAvatar(XFile imageFile) async {
    try {
      if (userId == null) return null;
      
      final fileExt = imageFile.path.split('.').last;
      // Unique filename using timestamp
      final fileName = '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      if (kIsWeb) {
        // ✅ WEB LOGIC: Upload Binary
        final bytes = await imageFile.readAsBytes();
        await _supabase.storage.from('user_avatars').uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
        );
      } else {
        // ✅ MOBILE LOGIC: Upload File Path
        await _supabase.storage.from('user_avatars').upload(
          fileName,
          File(imageFile.path),
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
        );
      }

      // Get Public URL
      final imageUrl = _supabase.storage.from('user_avatars').getPublicUrl(fileName);
      
      // Update DB with new URL so profile is in sync
      await updateProfile({'avatar_url': imageUrl});

      return imageUrl;
    } catch (e) {
      debugPrint('❌ Error uploading avatar: $e');
      return null;
    }
  }
}