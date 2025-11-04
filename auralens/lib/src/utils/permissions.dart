// permission_handler package is used to handle permissions
// lib/src/utils/permissions.dart

import 'package:permission_handler/permission_handler.dart';

/// 권한 요청 로직 클래스
class Permissions {
  /// 카메라 및 저장소 권한을 요청합니다.
  /// 갤러리 저장을 위해 `Permission.storage` (Android) 또는 `Permission.photos` (iOS)가 필요합니다.
  static Future<bool> requestCameraAndStoragePermissions() async {
    // 카메라 권한 요청
    var cameraStatus = await Permission.camera.request();

    // 갤러리 접근(저장) 권한 요청
    // Android 13 이상에서는 photos, 그 이하는 storage
    // iOS에서는 photos
    Permission storagePermission = Permission.photos;
    if (await Permission.storage.isDenied) {
       storagePermission = Permission.storage;
    }
    
    var storageStatus = await storagePermission.request();

    if (cameraStatus.isGranted && storageStatus.isGranted) {
      return true;
    } else {
      // 권한이 하나라도 거부된 경우
      // 사용자가 직접 설정에서 켜도록 유도할 수 있습니다.
      // openAppSettings(); 
      return false;
    }
  }
}