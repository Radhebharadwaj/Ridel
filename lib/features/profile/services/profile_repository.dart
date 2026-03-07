import 'dart:io';
import 'package:flutter/foundation.dart'; // Required for ValueNotifier
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart'; 

class ProfileRepository {
  final _supabase = Supabase.instance.client;

  // ✅ GLOBAL CITY STATE (Connects Header & Profile)
  // This static variable holds the state shared across the app
  static final ValueNotifier<String> userCity = ValueNotifier("Locating...");

  String? get userId => _supabase.auth.currentUser?.id;

  // 1. Get Profile
  Future<Map<String, dynamic>?> getProfile() async {
    try {
      // Handle Guest User
      if (userId == null) {
        userCity.value = "Select City";
        return null;
      }

      final data = await _supabase.from('user_profiles').select().eq('id', userId!).single();
      
      // ✅ Update Global State on Fetch
      if (data['current_city'] != null) {
        userCity.value = data['current_city'];
      } else {
        userCity.value = "Select City";
      }
      
      return data;
    } catch (e) {
      debugPrint('❌ Error fetching: $e');
      return null;
    }
  }

  // 2. Update Profile
  Future<Map<String, dynamic>?> updateProfile(Map<String, dynamic> updates) async {
    try {
      if (userId == null) throw "User not logged in";

      // ✅ Update Global State Immediately (Optimistic Update)
      if (updates.containsKey('current_city')) {
        userCity.value = updates['current_city'];
      }

      final currentData = await getProfile() ?? {};
      final mergedData = {...currentData, ...updates};

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

  // 3. Upload Avatar
  Future<String?> uploadAvatar(XFile imageFile) async {
    try {
      if (userId == null) return null;
      
      final fileExt = imageFile.path.split('.').last;
      final fileName = '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      if (kIsWeb) {
        final bytes = await imageFile.readAsBytes();
        await _supabase.storage.from('user_avatars').uploadBinary(
          fileName,
          bytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
        );
      } else {
        await _supabase.storage.from('user_avatars').upload(
          fileName,
          File(imageFile.path),
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
        );
      }

      final imageUrl = _supabase.storage.from('user_avatars').getPublicUrl(fileName);
      await updateProfile({'avatar_url': imageUrl});

      return imageUrl;
    } catch (e) {
      debugPrint('❌ Error uploading avatar: $e');
      return null;
    }
  }
}