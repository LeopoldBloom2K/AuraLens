// lib/src/models/camera_settings.dart

// 카메라 해상도를 나타내는 Enum
enum CameraResolution {
  low('저해상도 (빠른 처리)', 'low'),
  medium('중간 해상도', 'medium'),
  high('고해상도 (고품질)', 'high');

  final String name;
  final String value;
  const CameraResolution(this.name, this.value);
}