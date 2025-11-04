// DetectionResult model to hold the results of object detection
// lib/src/models/detection_result.dart

import 'dart:ui';

/// TFLite 추론 결과를 표현하는 데이터 모델
class DetectionResult {
  /// 감지된 객체의 신뢰도 (0.0 ~ 1.0)
  final double confidence;

  /// 감지된 객체의 레이블 (예: "person", "cat")
  final String label;

  /// 감지된 객체의 바운딩 박스 (화면 좌표 기준)
  final Rect boundingBox;

  DetectionResult({
    required this.confidence,
    required this.label,
    required this.boundingBox,
  });

  @override
  String toString() {
    return 'DetectionResult(label: $label, confidence: $confidence, box: $boundingBox)';
  }
}