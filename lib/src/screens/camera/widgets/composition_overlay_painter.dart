// lib/src/screens/camera/widgets/composition_overlay_painter.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:auralens/src/models/camera_settings.dart';

class CompositionOverlayPainter extends CustomPainter {
  final Size? imageSize;
  final Size widgetSize;
  final bool isGridEnabled;
  final bool isAiAssistEnabled;
  final SceneCategory currentScene;
  final Rect? detectedBoundingBox;
  final Offset? compositionTarget;
  final bool isCompositionCorrect;
  final Animation<double>? glowAnimation;

  CompositionOverlayPainter({
    this.imageSize,
    required this.widgetSize,
    required this.isGridEnabled,
    required this.isAiAssistEnabled,
    required this.currentScene,
    this.detectedBoundingBox,
    this.compositionTarget,
    this.isCompositionCorrect = false,
    this.glowAnimation,
  }) : super(repaint: glowAnimation);

  // 황금비 φ
  static const double _phi = 1.618033988749895;

  // 씬별 강조 색상
  Color get _sceneColor {
    switch (currentScene) {
      case SceneCategory.person:  return const Color(0xFF80D8FF); // light blue
      case SceneCategory.food:    return const Color(0xFFFFD740); // amber
      case SceneCategory.scenery: return Colors.white;
      case SceneCategory.unknown: return Colors.white;
    }
  }

  // 피보나치 반지름: width / φ³  ≈  width × 0.236
  double _fibRadius(Size size) => size.width / (_phi * _phi * _phi);

  // ML Kit 미감지 시 씬별 기본 main point
  Offset _defaultMainPoint(Size size) {
    switch (currentScene) {
      case SceneCategory.scenery:
        // 풍경: 화면 중앙 (수평선·주요 피사체 위치)
        return Offset(size.width / 2, size.height / 2);
      case SceneCategory.person:
        // 인물: 좌상단 파워포인트
        return Offset(size.width / 3, size.height / 3);
      case SceneCategory.food:
        // 음식: 중앙
        return Offset(size.width / 2, size.height / 2);
      case SceneCategory.unknown:
        return Offset(size.width / 2, size.height / 2);
    }
  }

  // ── 메인 paint ────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    if (isGridEnabled) _drawGrid(canvas, size);
    if (!isAiAssistEnabled || currentScene == SceneCategory.unknown) return;

    final mainPoint = compositionTarget ?? _defaultMainPoint(size);
    final radius    = _fibRadius(size);
    final color     = _sceneColor;
    final pulse     = glowAnimation?.value ?? 0.0;

    // 1. Line points: 하단 양 모서리 → main point 시선 유도선
    _drawLeadingLines(canvas, size, mainPoint, color, pulse);

    // 2. Main point: 황금비 점선 원 + 글로우
    _drawMainCircle(canvas, mainPoint, radius, color, pulse);

    // 3. 현재 피사체 위치 표시 (구도 불일치 상태에서만)
    if (detectedBoundingBox != null && !isCompositionCorrect) {
      _drawSubjectMarker(canvas, detectedBoundingBox!.center, color);
    }
  }

  // ── 3분할 그리드 ──────────────────────────────────────────────────────────

  void _drawGrid(Canvas canvas, Size size) {
    final outlinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.30)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final mainPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.42)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final xs = [size.width / 3, size.width * 2 / 3];
    final ys = [size.height / 3, size.height * 2 / 3];

    for (final x in xs) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), outlinePaint);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), mainPaint);
    }
    for (final y in ys) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), outlinePaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), mainPaint);
    }
  }

  // ── Line points: 하단 모서리 → main point 수렴 점선 ───────────────────────

  void _drawLeadingLines(Canvas canvas, Size size, Offset mainPoint, Color color, double pulse) {
    final isCorrect  = isCompositionCorrect;
    final dashAlpha  = isCorrect ? (0.80 + 0.15 * pulse) : 0.55;
    final blurRadius = isCorrect ? (5.0 + 3.0 * pulse) : 3.5;

    final corners = [
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];

    for (final corner in corners) {
      // 글로우 패스
      canvas.drawLine(
        corner, mainPoint,
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..strokeWidth = 7.0
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius),
      );

      // 점선 본선
      final path = Path()
        ..moveTo(corner.dx, corner.dy)
        ..lineTo(mainPoint.dx, mainPoint.dy);
      canvas.drawPath(
        _createDashedPath(path, 7.0, 6.0),
        Paint()
          ..color = color.withValues(alpha: dashAlpha)
          ..strokeWidth = 1.3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  // ── Main point: 황금비 점선 원 + 글로우 ──────────────────────────────────

  void _drawMainCircle(Canvas canvas, Offset center, double radius, Color color, double pulse) {
    final isCorrect  = isCompositionCorrect;
    final glowAlpha  = isCorrect ? (0.38 + 0.28 * pulse) : 0.22;
    final outerBlur  = isCorrect ? (10.0 + 5.0 * pulse) : 8.0;

    // 외곽 글로우
    canvas.drawCircle(
      center, radius,
      Paint()
        ..color = color.withValues(alpha: glowAlpha)
        ..strokeWidth = 5.0
        ..style = PaintingStyle.stroke
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, outerBlur),
    );

    // 내곽 글로우
    canvas.drawCircle(
      center, radius,
      Paint()
        ..color = color.withValues(alpha: glowAlpha * 1.6)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, outerBlur * 0.35),
    );

    // 원 본선 (구도 불일치 → 점선 / 일치 → 실선)
    final mainPaint = Paint()
      ..color = color.withValues(alpha: 0.93)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    if (isCorrect) {
      canvas.drawCircle(center, radius, mainPaint);
    } else {
      final path = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
      canvas.drawPath(_createDashedPath(path, 9.0, 5.0), mainPaint);
    }

    // 중심 점 (글로우 + 실점)
    canvas.drawCircle(
      center, 5.0,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0),
    );
    canvas.drawCircle(
      center, 2.2,
      Paint()
        ..color = color.withValues(alpha: 0.95)
        ..style = PaintingStyle.fill,
    );
  }

  // ── 현재 피사체 위치 마커 (십자 + 점) ────────────────────────────────────

  void _drawSubjectMarker(Canvas canvas, Offset center, Color color) {
    const arm = 9.0;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.60)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(center.dx - arm, center.dy), Offset(center.dx + arm, center.dy), paint);
    canvas.drawLine(Offset(center.dx, center.dy - arm), Offset(center.dx, center.dy + arm), paint);
    canvas.drawCircle(
      center, 2.5,
      Paint()..color = color.withValues(alpha: 0.75)..style = PaintingStyle.fill,
    );
  }

  // ── 점선 유틸리티 ─────────────────────────────────────────────────────────

  Path _createDashedPath(Path source, double dashLen, double gapLen) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0.0;
      bool draw = true;
      while (distance < metric.length) {
        final segLen = draw ? dashLen : gapLen;
        if (draw) {
          result.addPath(metric.extractPath(distance, distance + segLen), Offset.zero);
        }
        distance += segLen;
        draw = !draw;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant CompositionOverlayPainter oldDelegate) {
    return oldDelegate.currentScene      != currentScene      ||
           oldDelegate.isGridEnabled     != isGridEnabled     ||
           oldDelegate.isAiAssistEnabled != isAiAssistEnabled ||
           oldDelegate.widgetSize        != widgetSize        ||
           oldDelegate.detectedBoundingBox != detectedBoundingBox ||
           oldDelegate.compositionTarget != compositionTarget ||
           oldDelegate.isCompositionCorrect != isCompositionCorrect;
  }
}
