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
          break; // 🚀 불필요한 default 삭제 완료!
      }
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5) // 🚀 최신 문법 적용 완료!
      ..strokeWidth = 1.0;

    canvas.drawLine(Offset(size.width / 3, 0), Offset(size.width / 3, size.height), paint);
    canvas.drawLine(Offset(size.width * 2 / 3, 0), Offset(size.width * 2 / 3, size.height), paint);
    canvas.drawLine(Offset(0, size.height / 3), Offset(size.width, size.height / 3), paint);
    canvas.drawLine(Offset(0, size.height * 2 / 3), Offset(size.width, size.height * 2 / 3), paint);
  }

  void _drawFoodGuide(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.amberAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final crossSize = 20.0;

    canvas.drawLine(Offset(center.dx - crossSize, center.dy), Offset(center.dx + crossSize, center.dy), paint);
    canvas.drawLine(Offset(center.dx, center.dy - crossSize), Offset(center.dx, center.dy + crossSize), paint);
    canvas.drawCircle(center, 4.0, paint..style = PaintingStyle.fill);
  }

  void _drawPersonGuide(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.lightBlueAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final points = [
      Offset(size.width / 3, size.height / 3),
      Offset(size.width * 2 / 3, size.height / 3),
      Offset(size.width / 3, size.height * 2 / 3),
      Offset(size.width * 2 / 3, size.height * 2 / 3),
    ];

    for (var point in points) {
      canvas.drawCircle(point, 15.0, paint);
    }
  }

  void _drawSceneryGuide(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final startPoint = Offset(0, size.height * 2 / 3);
    final endPoint = Offset(size.width, size.height * 2 / 3);
    canvas.drawLine(startPoint, endPoint, paint);
  }

  @override
  bool shouldRepaint(covariant CompositionOverlayPainter oldDelegate) {
    return oldDelegate.currentScene != currentScene ||
        oldDelegate.isGridEnabled != isGridEnabled ||
        oldDelegate.isAiAssistEnabled != isAiAssistEnabled ||
        oldDelegate.widgetSize != widgetSize;
  }
}