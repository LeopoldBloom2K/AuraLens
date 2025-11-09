// lib/src/utils/coordinate_scaler.dart
import 'dart:ui'; // Rect, Size, Offset

/// ML Kit 좌표계(이미지)를 Flutter UI 좌표계(위젯)로 변환합니다.
/// 'Contain' 모드(레터박스)를 정확히 계산합니다.
Rect scaleRect({
  required Rect rect,
  required Size imageSize,
  required Size widgetSize,
}) {
  final double scaleX = widgetSize.width / imageSize.width;
  final double scaleY = widgetSize.height / imageSize.height;
  final double scale = scaleX < scaleY ? scaleX : scaleY; // 'Contain' 모드
  final double offsetX = (widgetSize.width - imageSize.width * scale) / 2.0;
  final double offsetY = (widgetSize.height - imageSize.height * scale) / 2.0;

  return Rect.fromLTRB(
    rect.left * scale + offsetX,
    rect.top * scale + offsetY,
    rect.right * scale + offsetX,
    rect.bottom * scale + offsetY,
  );
}