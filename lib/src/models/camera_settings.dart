// lib/src/models/camera_settings.dart

// 1. 카메라 해상도
enum CameraResolution {
  low('저해상도 (빠른 처리)', 'low'),
  medium('중간 해상도', 'medium'),
  high('고해상도 (고품질)', 'high'),
  max('원본 최대 해상도', 'max');

  final String name;
  final String value;
  const CameraResolution(this.name, this.value);
}

// 2. AI 상황 카테고리
enum SceneCategory { unknown, food, person, scenery }

// 3. 카메라 화면 비율
enum CameraRatio {
  ratio1_1(1.0, '1:1'),
  ratio4_3(3.0 / 4.0, '4:3'),
  ratio16_9(9.0 / 16.0, '16:9');

  final double value;
  final String label;

  const CameraRatio(this.value, this.label);
}