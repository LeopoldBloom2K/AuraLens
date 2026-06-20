// permission_handler package is used to handle permissions
// lib/src/utils/permissions.dart

import 'package:permission_handler/permission_handler.dart';

/// 권한 요청 로직 클래스
class Permissions {
  /// 카메라 및 저장소 권한을 요청합니다.
  /// 갤러리 저장을 위해 `Permission.storage` (Android) 또는 `Permission.photos` (iOS)가 필요합니다.
  static Future<bool> requestCameraAndStoragePermissions() async {
    // 세 권한을 한 번에 요청합니다.
    // Permission.photos  → Android 13+ (READ_MEDIA_IMAGES) / iOS
    // Permission.storage → Android 12 이하 (READ_EXTERNAL_STORAGE)
    // 두 저장소 권한 중 하나라도 허용되면 갤러리 저장 가능합니다.
    final statuses = await [
      Permission.camera,
      Permission.photos,
      Permission.storage,
    ].request();

    final cameraOk  = statuses[Permission.camera]?.isGranted  ?? false;
    final photosOk  = statuses[Permission.photos]?.isGranted  ?? false;
    final storageOk = statuses[Permission.storage]?.isGranted ?? false;

    return cameraOk && (photosOk || storageOk);
  }
}