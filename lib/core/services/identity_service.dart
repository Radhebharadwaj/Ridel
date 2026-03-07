import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';

class IdentityService {
  
  // 🚀 Sirf Device Info ka function bacha hai. 
  // Location ka saara logic GlobalLocationService me shift ho chuka hai (Phase 1 rule).

  Future<Map<String, String?>> getDeviceInfo() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      if (kIsWeb) {
        WebBrowserInfo webInfo = await deviceInfo.webBrowserInfo;
        return {
          'last_device_id': 'Web_${webInfo.browserName.name}',
          'last_device_name': '${webInfo.browserName.name} Browser',
        };
      } else if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        return {
          'last_device_id': androidInfo.id,
          'last_device_name': '${androidInfo.brand} ${androidInfo.model}',
        };
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        return {
          'last_device_id': iosInfo.identifierForVendor,
          'last_device_name': iosInfo.name,
        };
      }
    } catch (e) {
      debugPrint("⚠️ Device Info Error: $e");
    }
    return {'last_device_id': 'Unknown', 'last_device_name': 'Unknown Device'};
  }
}