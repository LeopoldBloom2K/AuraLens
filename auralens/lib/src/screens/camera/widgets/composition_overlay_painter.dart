// It will make CustomPainter for composition overlay on camera preview (compositionService)
// Using canvas.drawLine, canvas.drawRect, to draw bounding boxes and labels on detected objects's guide.
// lib/src/screens/camera/widgets/composition_overlay_painter.dart

import 'package:flutter/material.dart';
// import 'package:auralens/src/models/detection_result.dart'; // (다음 단계에서 사용)

/// 카메라 오버레이에 구도 가이드를 그리는 CustomPainter
class CompositionOverlayPainter extends CustomPainter {
  final List<DetectionResult> detections;
  final Size cameraPreviewSize; // 카메라 프리뷰의 실제 크기

  CompositionOverlayPainter({
    required this.detections,
    required this.cameraPreviewSize,
  });

  @override
  void paint(Canvas canvas, Size size) {  // size는 CustomPaint 위젯의 크기
    // 3분할 가이드 페인트 설정
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.4) // 반투명 흰색
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5; // 선 굵기

    // --- 3분할 (Rule of Thirds) 가이드 그리기 ---
    final double thirdOfWidth = size.width / 3;
    final double thirdOfHeight = size.height / 3;
// --- 바운딩 박스(Bounding Box) 그리기 ---
    if (detections.isEmpty) return;

    final boxPaint = Paint()
      ..color = Colors.yellowAccent // 감지된 객체 박스 색상
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final textStyle = TextStyle(
      color: Colors.yellowAccent,
      fontSize: 14,
      backgroundColor: Colors.black.withOpacity(0.5),
    );
    
    // 프리뷰와 화면 크기 비율 계산 (좌우 레터박스 대응)
    final double scaleX = size.width / cameraPreviewSize.width;
    final double scaleY = size.height / cameraPreviewSize.height;
    // (이 예제는 프리뷰가 화면에 꽉 찬다고 가정하고 scale을 1로 단순화)
    // (실제로는 AspectRatio에 맞춰 스케일링 필요)

    for (final detection in detections) {
      // 1. TFLite 상대 좌표(0.0~1.0)를 화면 절대 좌표로 변환
      final Rect absoluteBox = Rect.fromLTRB(
        detection.boundingBox.left * size.width,
        detection.boundingBox.top * size.height,
        detection.boundingBox.right * size.width,
        detection.boundingBox.bottom * size.height,
      );

      // 2. 박스 그리기
      canvas.drawRect(absoluteBox, boxPaint);

      // 3. 레이블 및 신뢰도 텍스트 그리기
      final textSpan = TextSpan(
        text: '${detection.label} ${(detection.confidence * 100).toStringAsFixed(0)}%',
        style: textStyle,
      );
      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(absoluteBox.left + 4, absoluteBox.top + 4), // 박스 좌상단에
      );
    }
  }

  @override
  bool shouldRepaint(covariant CompositionOverlayPainter oldDelegate) {
    // Detections 리스트가 변경되었을 때만 다시 그림 (최적화)
    return oldDelegate.detections != detections;
  }
}