// It will make CustomPainter for composition overlay on camera preview (compositionService)
// Using canvas.drawLine, canvas.drawRect, to draw bounding boxes and labels on detected objects's guide.
// lib/src/screens/camera/widgets/composition_overlay_painter.dart

import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

class CompositionOverlayPainter extends CustomPainter {
  final List<DetectedObject> detections;
  final Size? imageSize; // 카메라 이미지 원본 크기
  final Size widgetSize; // UI 위젯(LayoutBuilder) 크기
  final Offset? compositionTarget;
  final bool isCompositionCorrect;
  // New fields for grid and AI assist
  final bool isGridEnabled;
  final bool isAiAssistEnabled;

  CompositionOverlayPainter({
    required this.detections,
    required this.imageSize,
    required this.widgetSize,
    this.compositionTarget,
    required this.isCompositionCorrect,
    required this.isGridEnabled, // [신규]
    required this.isAiAssistEnabled, // [신규]
  });

  @override
  void paint(Canvas canvas, Size size) {
    // size == widgetSize

    // --- 3분할 그리드 ---
    final gridPaint = Paint()
      ..color = Colors.white.withAlpha(182)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    // ... (3분할 선 그리기 로직 동일) ...
    final double thirdOfWidth = size.width / 3;
    final double thirdOfHeight = size.height / 3;
    canvas.drawLine(
      Offset(thirdOfWidth, 0),
      Offset(thirdOfWidth, size.height),
      gridPaint,
    );
    canvas.drawLine(
      Offset(thirdOfWidth * 2, 0),
      Offset(thirdOfWidth * 2, size.height),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, thirdOfHeight),
      Offset(size.width, thirdOfHeight),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, thirdOfHeight * 2),
      Offset(size.width, thirdOfHeight * 2),
      gridPaint,
    );

    if (imageSize == null || detections.isEmpty) return;

    // --- 바운딩 박스 & 레이블 ---
    final boxPaint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    final textStyle = TextStyle(color: Colors.yellowAccent, fontSize: 14);

    for (final detection in detections) {
      // ML Kit 좌표(이미지 기준) -> UI 좌표(위젯 기준)로 스케일링
      final Rect absoluteBox = _scaleRect(
        rect: detection.boundingBox,
        imageSize: imageSize!,
        widgetSize: widgetSize,
      );

      canvas.drawRect(absoluteBox, boxPaint);

      final textSpan = TextSpan(
        text:
            '${detection.labels.first.text} ${(detection.labels.first.confidence * 100).toStringAsFixed(0)}%',
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
        Offset(absoluteBox.left + 4, absoluteBox.top + 4),
      );
    }

    // --- 동적 구도 타겟 & 시각적 피드백 ---
    // (ViewModel이 이미 UI 스케일 기준으로 계산했으므로 로직 동일)
    if (compositionTarget != null) {
      final Color targetColor = isCompositionCorrect
          ? Colors.greenAccent
          : Colors.white;
      final targetPaint = Paint()
        ..color = targetColor.withAlpha(204)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      const double targetRadius = 20.0;
      canvas.drawLine(
        Offset(compositionTarget!.dx - targetRadius, compositionTarget!.dy),
        Offset(compositionTarget!.dx + targetRadius, compositionTarget!.dy),
        targetPaint,
      );
      canvas.drawLine(
        Offset(compositionTarget!.dx, compositionTarget!.dy - targetRadius),
        Offset(compositionTarget!.dx, compositionTarget!.dy + targetRadius),
        targetPaint,
      );
    }
  }

  /// ML Kit 좌표계(이미지)를 Flutter UI 좌표계(위젯)로 변환 (중요)
  Rect _scaleRect({
    required Rect rect,
    required Size imageSize,
    required Size widgetSize,
  }) {
    // CameraPreview는 기본적으로 'AspectRatio' 모드(contain)가 아니라
    // 'cover' 모드(화면을 꽉 채움)로 작동하려는 경향이 있습니다.
    // 여기서는 'AspectRatio' 위젯으로 'contain'을 강제했다고 가정합니다.

    final double scaleX = widgetSize.width / imageSize.width;
    final double scaleY = widgetSize.height / imageSize.height;

    // AspectRatio(contain) 모드를 가정하여, 더 작은 스케일 팩터를 사용 (레터박스 대응)
    final double scale = scaleX < scaleY ? scaleX : scaleY;

    final double offsetX = (widgetSize.width - imageSize.width * scale) / 2.0;
    final double offsetY = (widgetSize.height - imageSize.height * scale) / 2.0;

    return Rect.fromLTRB(
      rect.left * scale + offsetX,
      rect.top * scale + offsetY,
      rect.right * scale + offsetX,
      rect.bottom * scale + offsetY,
    );
  }

  @override
  bool shouldRepaint(covariant CompositionOverlayPainter oldDelegate) {
    // 상태가 변경되었을때만 다시 그리도록 최적화
    return oldDelegate.detections != detections ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.widgetSize != widgetSize ||
        oldDelegate.compositionTarget != compositionTarget ||
        oldDelegate.isCompositionCorrect != isCompositionCorrect ||
        oldDelegate.isGridEnabled != isGridEnabled || // [신규]
        oldDelegate.isAiAssistEnabled != isAiAssistEnabled; // [신규]
  }
}
