// lib/src/screens/camera/widgets/composition_overlay_painter.dart

import 'package:flutter/material.dart';
import 'package:auralens/src/models/camera_settings.dart'; 

class CompositionOverlayPainter extends CustomPainter {
  final Size? imageSize;
  final Size widgetSize;
  final bool isGridEnabled;
  final bool isAiAssistEnabled;
  final SceneCategory currentScene;

  CompositionOverlayPainter({
    this.imageSize,
    required this.widgetSize,
    required this.isGridEnabled,
    required this.isAiAssistEnabled,
    required this.currentScene,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (isGridEnabled) {
      _drawGrid(canvas, size);
    }

    if (isAiAssistEnabled) {
      switch (currentScene) {
        case SceneCategory.food:
          _drawFoodGuide(canvas, size);
          break;
        case SceneCategory.person:
          _drawPersonGuide(canvas, size);
          break;
        case SceneCategory.scenery:
          _drawSceneryGuide(canvas, size);
          break;
        case SceneCategory.unknown:
          break; 
      }
    }
  }

  // 🚀 외곽선(그림자)을 그려주는 헬퍼 함수들
  void _drawLineWithOutline(Canvas canvas, Offset p1, Offset p2, Paint outline, Paint main) {
    canvas.drawLine(p1, p2, outline); // 까만 선 먼저
    canvas.drawLine(p1, p2, main);    // 그 위에 컬러 선
  }

  void _drawCircleWithOutline(Canvas canvas, Offset center, double radius, Paint outline, Paint main) {
    canvas.drawCircle(center, radius, outline);
    canvas.drawCircle(center, radius, main);
  }

  // 📐 3분할 그리드 (가시성 극대화)
  void _drawGrid(Canvas canvas, Size size) {
    // 까만색 두꺼운 외곽선
    final outlinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6) 
      ..strokeWidth = 2.5;
    // 하얀색 얇은 메인 선
    final mainPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 1.0;

    final x1 = size.width / 3;
    final x2 = size.width * 2 / 3;
    final y1 = size.height / 3;
    final y2 = size.height * 2 / 3;

    _drawLineWithOutline(canvas, Offset(x1, 0), Offset(x1, size.height), outlinePaint, mainPaint);
    _drawLineWithOutline(canvas, Offset(x2, 0), Offset(x2, size.height), outlinePaint, mainPaint);
    _drawLineWithOutline(canvas, Offset(0, y1), Offset(size.width, y1), outlinePaint, mainPaint);
    _drawLineWithOutline(canvas, Offset(0, y2), Offset(size.width, y2), outlinePaint, mainPaint);
  }

  // 🍔 음식 가이드 (십자선)
  void _drawFoodGuide(Canvas canvas, Size size) {
    final outlinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;
    final mainPaint = Paint()
      ..color = Colors.amberAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final crossSize = 20.0;

    _drawLineWithOutline(canvas, Offset(center.dx - crossSize, center.dy), Offset(center.dx + crossSize, center.dy), outlinePaint, mainPaint);
    _drawLineWithOutline(canvas, Offset(center.dx, center.dy - crossSize), Offset(center.dx, center.dy + crossSize), outlinePaint, mainPaint);
    
    _drawCircleWithOutline(canvas, center, 4.0, outlinePaint..style=PaintingStyle.fill, mainPaint..style=PaintingStyle.fill);
  }

  // 🙋 인물 가이드 (4개 교차점)
  void _drawPersonGuide(Canvas canvas, Size size) {
    final outlinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..strokeWidth = 4.5
      ..style = PaintingStyle.stroke;
    final mainPaint = Paint()
      ..color = Colors.lightBlueAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final points = [
      Offset(size.width / 3, size.height / 3), Offset(size.width * 2 / 3, size.height / 3),
      Offset(size.width / 3, size.height * 2 / 3), Offset(size.width * 2 / 3, size.height * 2 / 3),
    ];

    for (var point in points) {
      _drawCircleWithOutline(canvas, point, 15.0, outlinePaint, mainPaint);
    }
  }

  // ⛰️ 풍경 가이드 (수평선)
  void _drawSceneryGuide(Canvas canvas, Size size) {
    final outlinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..strokeWidth = 4.5
      ..style = PaintingStyle.stroke;
    final mainPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final startPoint = Offset(0, size.height * 2 / 3);
    final endPoint = Offset(size.width, size.height * 2 / 3);
    _drawLineWithOutline(canvas, startPoint, endPoint, outlinePaint, mainPaint);
  }

  @override
  bool shouldRepaint(covariant CompositionOverlayPainter oldDelegate) {
    return oldDelegate.currentScene != currentScene ||
        oldDelegate.isGridEnabled != isGridEnabled ||
        oldDelegate.isAiAssistEnabled != isAiAssistEnabled ||
        oldDelegate.widgetSize != widgetSize;
  }
}