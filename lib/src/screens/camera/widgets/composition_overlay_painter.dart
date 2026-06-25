// lib/src/screens/camera/widgets/composition_overlay_painter.dart

import 'dart:math' show pi;
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
  final CompositionType? compositionType;
  final double compositionScore;
  final ColorHarmonyResult? colorHarmony;
  final double? aestheticScore;
  final Offset? nosePoint;
  // 0=portrait, 1=landscape CCW (phone rotated right), 3=landscape CW (phone rotated left)
  final int rotationTurns;

  const CompositionOverlayPainter({
    this.imageSize,
    required this.widgetSize,
    required this.isGridEnabled,
    required this.isAiAssistEnabled,
    required this.currentScene,
    this.detectedBoundingBox,
    this.compositionTarget,
    this.isCompositionCorrect = false,
    this.glowAnimation,
    this.compositionType,
    this.compositionScore = 0.0,
    this.colorHarmony,
    this.aestheticScore,
    this.nosePoint,
    this.rotationTurns = 0,
  }) : super(repaint: glowAnimation);

  // 황금비 φ = 1.618…  피보나치 반지름 = W / φ³ ≈ W × 0.236
  static const double _phi = 1.618033988749895;

  // ── 씬별 색상 ────────────────────────────────────────────────────────────

  Color get _sceneColor => switch (currentScene) {
    SceneCategory.person  => const Color(0xFF80D8FF), // light blue
    SceneCategory.food    => const Color(0xFFFFD740), // amber
    SceneCategory.scenery => Colors.white,
    SceneCategory.unknown => Colors.white,
  };

  // ML Kit 미감지 시 씬별 기본 구도 목표점 (새 구도 유형 기준으로 갱신)
  Offset _defaultMainPoint(Size size) => switch (currentScene) {
    SceneCategory.person  => Offset(size.width / 2,      size.height * 0.40), // 삼각형 무게중심 영역
    SceneCategory.food    => Offset(size.width * 0.50,   size.height * 0.62), // 메인 접시 영역
    SceneCategory.scenery => Offset(size.width / 2,      size.height * 0.38), // 리딩라인 소실점
    SceneCategory.unknown => Offset(size.width / 2,      size.height / 2),
  };

  double _fibRadius(Size size) => size.width / (_phi * _phi * _phi);

  // ── 좌표 회전 변환 ──────────────────────────────────────────────────────────

  // portrait 위젯 좌표 → 회전된 캔버스 좌표
  // rotationTurns == 1 (90° CW, phone rotated CCW): (ox,oy) → (oy, W-ox)
  // rotationTurns == 3 (90° CCW, phone rotated CW): (ox,oy) → (H-oy, ox)
  Offset _toRotated(Offset pt, Size s) {
    switch (rotationTurns) {
      case 1: return Offset(pt.dy,          s.width  - pt.dx);
      case 3: return Offset(s.height - pt.dy, pt.dx);
      default: return pt;
    }
  }

  Rect _rectToRotated(Rect r, Size s) {
    switch (rotationTurns) {
      case 1:
        // portrait (L,T,R,B) → rotated (T, W-R, B, W-L)
        return Rect.fromLTRB(r.top, s.width - r.right, r.bottom, s.width - r.left);
      case 3:
        // portrait (L,T,R,B) → rotated (H-B, L, H-T, R)
        return Rect.fromLTRB(s.height - r.bottom, r.left, s.height - r.top, r.right);
      default:
        return r;
    }
  }

  // ── 메인 paint ────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    // 폰을 가로로 들면 캔버스를 회전해 오버레이도 가로 기준으로 그림
    // portrait 위젯은 항상 세로이므로 canvas transform으로만 보정
    final Size drawSize;
    if (rotationTurns == 1) {
      canvas.translate(size.width, 0);
      canvas.rotate(pi / 2);
      drawSize = Size(size.height, size.width);
    } else if (rotationTurns == 3) {
      canvas.translate(0, size.height);
      canvas.rotate(-pi / 2);
      drawSize = Size(size.height, size.width);
    } else {
      drawSize = size;
    }

    if (isGridEnabled) _drawGrid(canvas, drawSize);
    if (!isAiAssistEnabled || currentScene == SceneCategory.unknown) return;

    // portrait 위젯 좌표 → 회전된 캔버스 좌표로 변환
    final effectiveTarget = compositionTarget   != null ? _toRotated(compositionTarget!,    size) : null;
    final effectiveBox    = detectedBoundingBox != null ? _rectToRotated(detectedBoundingBox!, size) : null;
    final effectiveNose   = nosePoint           != null ? _toRotated(nosePoint!,             size) : null;

    final mainPoint = effectiveTarget ?? _defaultMainPoint(drawSize);
    final radius    = _fibRadius(drawSize);
    final color     = _sceneColor;
    final pulse     = glowAnimation?.value ?? 0.0;

    // 씬별 고정 오버레이 — compositionType이 아닌 currentScene 기준으로 항상 표시
    switch (currentScene) {
      case SceneCategory.person:
        _drawTriangleOverlay(canvas, drawSize, effectiveBox, color, pulse);
      case SceneCategory.food:
        _drawFoodRectangle(canvas, drawSize, mainPoint, effectiveBox, color, pulse);
      case SceneCategory.scenery:
        if (compositionType == CompositionType.frameInFrame) {
          _drawFrameInFrame(canvas, drawSize, effectiveTarget, color, pulse);
        } else {
          _drawConvergenceLines(canvas, drawSize, mainPoint, color, pulse);
        }
      case SceneCategory.unknown:
        _drawLeadingLines(canvas, drawSize, mainPoint, color, pulse);
    }

    _drawMainCircle(canvas, mainPoint, radius, color, pulse);

    if (effectiveBox != null && !isCompositionCorrect) {
      _drawSubjectMarker(canvas, effectiveBox.center, color);
    }

    // 코 추적 마커 (person 씬 전용)
    if (currentScene == SceneCategory.person && effectiveNose != null) {
      _drawNoseMarker(canvas, effectiveNose, color, pulse);
    }

    if (compositionType != null) {
      _drawCompositionLabel(canvas, drawSize, compositionType!, compositionScore, color);
    }

    if (colorHarmony != null) {
      _drawHarmonyBadge(canvas, drawSize, colorHarmony!);
    }

    if (aestheticScore != null && currentScene == SceneCategory.person) {
      _drawAestheticBadge(canvas, drawSize, aestheticScore!);
    }
  }

  // ── 3분할 그리드 ──────────────────────────────────────────────────────────

  void _drawGrid(Canvas canvas, Size size) {
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.30)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.42)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    for (final x in [size.width / 3, size.width * 2 / 3]) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), shadow);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (final y in [size.height / 3, size.height * 2 / 3]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), shadow);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  // ── 하단 모서리 → 구도 목표점 수렴 점선 ──────────────────────────────────

  void _drawLeadingLines(
      Canvas canvas, Size size, Offset target, Color color, double pulse) {
    final dashAlpha  = isCompositionCorrect ? (0.80 + 0.15 * pulse) : 0.55;
    final glowRadius = isCompositionCorrect ? (5.0  + 3.0  * pulse) : 3.5;

    for (final corner in [Offset(0, size.height), Offset(size.width, size.height)]) {
      // 글로우 레이어
      canvas.drawLine(
        corner, target,
        Paint()
          ..color      = color.withValues(alpha: 0.22)
          ..strokeWidth = 7.0
          ..style      = PaintingStyle.stroke
          ..strokeCap  = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius),
      );

      // 점선 본선
      canvas.drawPath(
        _dashedLine(corner, target, 7.0, 6.0),
        Paint()
          ..color      = color.withValues(alpha: dashAlpha)
          ..strokeWidth = 1.3
          ..style      = PaintingStyle.stroke
          ..strokeCap  = StrokeCap.round,
      );
    }
  }

  // ── 삼각형 구도 (person) ── 그룹1: 감지된 bbox 기준 삼각형 ──────────────────
  //
  // bbox 감지 시: bbox를 감싸는 삼각형 동적 계산
  //   apex  = bbox 중앙 상단 (머리 위)
  //   baseL = bbox 좌하단 밖
  //   baseR = bbox 우하단 밖
  // bbox 미감지 시: 화면 기준 기본 가이드 삼각형

  void _drawTriangleOverlay(Canvas canvas, Size size, Rect? bbox, Color color, double pulse) {
    final W = size.width;
    final H = size.height;

    final Offset apex, baseL, baseR;
    if (bbox != null) {
      final margin = (bbox.width + bbox.height) * 0.18;
      apex  = Offset(bbox.center.dx,
                     (bbox.top - margin).clamp(0.0, H));
      baseL = Offset((bbox.left  - margin).clamp(0.0, W),
                     (bbox.bottom + margin * 0.5).clamp(0.0, H));
      baseR = Offset((bbox.right + margin).clamp(0.0, W),
                     (bbox.bottom + margin * 0.5).clamp(0.0, H));
    } else {
      apex  = Offset(W / 2,    H * 0.18);
      baseL = Offset(W * 0.18, H * 0.72);
      baseR = Offset(W * 0.82, H * 0.72);
    }

    final dashAlpha  = isCompositionCorrect ? (0.75 + 0.20 * pulse) : 0.50;
    final glowRadius = isCompositionCorrect ? (6.0  + 3.0  * pulse) : 4.0;

    final path = Path()
      ..moveTo(apex.dx,  apex.dy)
      ..lineTo(baseL.dx, baseL.dy)
      ..lineTo(baseR.dx, baseR.dy)
      ..close();

    canvas.drawPath(path, Paint()
      ..color      = color.withValues(alpha: 0.18)
      ..strokeWidth = 8.0
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius));

    final linePaint = Paint()
      ..color      = color.withValues(alpha: dashAlpha)
      ..strokeWidth = 1.5
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.round;

    if (isCompositionCorrect) {
      canvas.drawPath(path, linePaint);
    } else {
      canvas.drawPath(_dashedPath(path, 8.0, 6.0), linePaint);
    }

    for (final v in [apex, baseL, baseR]) {
      canvas.drawCircle(v, 3.5, Paint()
        ..color = color.withValues(alpha: dashAlpha * 0.90)
        ..style = PaintingStyle.fill);
    }
  }

  // ── 리딩라인 구도 (scenery) ── 그룹2: 소실점 높이 기준 동적 수렴선 ───────────
  //
  // 수렴선 출발점이 target.dy 를 중심으로 ±H×0.32 범위에서 계산됨.
  // target 위치가 높아질수록 선들이 더 가파르게 모이고,
  // target 위치가 낮아질수록 완만하게 펼쳐짐 → 실제 원근감과 일치.

  void _drawConvergenceLines(
      Canvas canvas, Size size, Offset target, Color color, double pulse) {
    final dashAlpha  = isCompositionCorrect ? (0.80 + 0.15 * pulse) : 0.55;
    final glowRadius = isCompositionCorrect ? (5.0  + 3.0  * pulse) : 3.5;
    final W = size.width;
    final H = size.height;

    // target 수직 위치 기준으로 spread 결정 (소실점 높이에 따라 원근감 자동 조정)
    final spread = H * 0.32;
    final topY   = (target.dy - spread).clamp(0.0, H);
    final botY   = (target.dy + spread).clamp(0.0, H);

    final sources = [
      Offset(0, topY),
      Offset(0, botY),
      Offset(W, topY),
      Offset(W, botY),
    ];

    for (final src in sources) {
      canvas.drawLine(src, target, Paint()
        ..color      = color.withValues(alpha: 0.18)
        ..strokeWidth = 7.0
        ..style      = PaintingStyle.stroke
        ..strokeCap  = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius));

      canvas.drawPath(_dashedLine(src, target, 9.0, 7.0), Paint()
        ..color      = color.withValues(alpha: dashAlpha * 0.80)
        ..strokeWidth = 1.0
        ..style      = PaintingStyle.stroke
        ..strokeCap  = StrokeCap.round);
    }
  }

  // ── 프레임 인 프레임 구도 (scenery) ── 그룹5: compositionTarget 중심 프레임 ──
  //
  // compositionTarget 이 있으면 내부 프레임을 그 위치에 중심 정렬.
  // 피사체가 화면 한쪽에 치우친 경우에도 프레임이 따라가며 구도를 안내함.

  void _drawFrameInFrame(Canvas canvas, Size size, Offset? effectiveTarget, Color color, double pulse) {
    final frameW = size.width  * 0.64;
    final frameH = size.height * 0.72;

    // effectiveTarget 중심 정렬 (없으면 화면 중앙 약간 위)
    final center = effectiveTarget ?? Offset(size.width / 2, size.height * 0.47);
    final rawL   = center.dx - frameW / 2;
    final rawT   = center.dy - frameH / 2;

    // 화면 밖으로 벗어나지 않도록 클램핑
    final left = rawL.clamp(0.0, size.width  - frameW);
    final top  = rawT.clamp(0.0, size.height - frameH);
    final innerRect = Rect.fromLTWH(left, top, frameW, frameH);

    final tl = innerRect.topLeft;
    final tr = innerRect.topRight;
    final bl = innerRect.bottomLeft;
    final br = innerRect.bottomRight;

    final dashAlpha  = isCompositionCorrect ? (0.75 + 0.20 * pulse) : 0.50;
    final glowRadius = isCompositionCorrect ? (6.0  + 4.0  * pulse) : 4.0;

    canvas.drawRect(innerRect, Paint()
      ..color      = color.withValues(alpha: 0.14)
      ..strokeWidth = 9.0
      ..style      = PaintingStyle.stroke
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius));

    canvas.drawPath(
      _dashedPath(Path()..addRect(innerRect), 14.0, 9.0),
      Paint()
        ..color      = color.withValues(alpha: dashAlpha * 0.45)
        ..strokeWidth = 0.9
        ..style      = PaintingStyle.stroke);

    const arm = 28.0;
    final cp = Paint()
      ..color      = color.withValues(alpha: dashAlpha)
      ..strokeWidth = 2.0
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.round;

    canvas.drawLine(tl, tl + const Offset( arm, 0), cp);
    canvas.drawLine(tl, tl + const Offset(0,  arm), cp);
    canvas.drawLine(tr, tr - const Offset( arm, 0), cp);
    canvas.drawLine(tr, tr + const Offset(0,  arm), cp);
    canvas.drawLine(bl, bl + const Offset( arm, 0), cp);
    canvas.drawLine(bl, bl - const Offset(0,  arm), cp);
    canvas.drawLine(br, br - const Offset( arm, 0), cp);
    canvas.drawLine(br, br - const Offset(0,  arm), cp);
  }

  // ── 사각 배열 구도 (food) ── 그룹4: bbox 기준 포컬포인트 동적 배치 ───────────
  //
  // bbox 감지 시: 감지된 음식 위치에서 bbox 크기 비례로 나머지 포컬포인트를 방사 배치
  //   pts[0] = bbox.center (메인 접시)
  //   pts[1..3] = step = (bbox.w + bbox.h) × 0.28 거리에 사이드·소스·가니쉬 배치
  // bbox 미감지 시: 화면 기준 기본 고정 포컬포인트

  void _drawFoodRectangle(
      Canvas canvas, Size size, Offset mainPoint, Rect? bbox, Color color, double pulse) {
    final W = size.width;
    final H = size.height;
    final dashAlpha  = isCompositionCorrect ? (0.75 + 0.20 * pulse) : 0.55;
    final glowRadius = isCompositionCorrect ? (5.0  + 3.0  * pulse) : 3.5;
    final List<Offset> pts;

    if (bbox != null) {
      final cx   = bbox.center.dx;
      final cy   = bbox.center.dy;
      final step = (bbox.width + bbox.height) * 0.28;
      pts = [
        bbox.center,
        Offset(cx + step * 0.90, cy - step * 0.70),
        Offset(cx - step * 0.60, cy - step * 0.72),
        Offset(cx - step * 1.00, cy + step * 0.18),
      ].map((p) => Offset(
        p.dx.clamp(W * 0.04, W * 0.96),
        p.dy.clamp(H * 0.04, H * 0.96),
      )).toList();
    } else {
      pts = [
        Offset(W * 0.50, H * 0.62),
        Offset(W * 0.68, H * 0.40),
        Offset(W * 0.35, H * 0.36),
        Offset(W * 0.18, H * 0.58),
      ];
    }

    for (final pair in [
      [0, 1], [1, 2], [2, 3], [3, 0], [0, 2],
    ]) {
      final a = pts[pair[0]];
      final b = pts[pair[1]];
      canvas.drawLine(a, b, Paint()
        ..color      = color.withValues(alpha: 0.12)
        ..strokeWidth = 5.0
        ..style      = PaintingStyle.stroke
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0));
      canvas.drawPath(_dashedLine(a, b, 6.0, 5.0), Paint()
        ..color      = color.withValues(alpha: dashAlpha * 0.55)
        ..strokeWidth = 0.9
        ..style      = PaintingStyle.stroke);
    }

    for (final pt in pts) {
      final isActive = (pt - mainPoint).distance < W * 0.08;
      final r        = isActive ? 13.0 : 9.0;
      canvas.drawCircle(pt, r, Paint()
        ..color      = color.withValues(alpha: 0.15)
        ..strokeWidth = isActive ? 6.0 : 4.0
        ..style      = PaintingStyle.stroke
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius));
      canvas.drawPath(
        _dashedPath(Path()..addOval(Rect.fromCircle(center: pt, radius: r)), 6.0, 4.0),
        Paint()
          ..color      = color.withValues(alpha: dashAlpha * (isActive ? 0.95 : 0.65))
          ..strokeWidth = 1.2
          ..style      = PaintingStyle.stroke);
    }
  }

  // ── 황금비 원 (구도 목표점) + 글로우 ─────────────────────────────────────

  void _drawMainCircle(
      Canvas canvas, Offset center, double radius, Color color, double pulse) {
    final glowAlpha = isCompositionCorrect ? (0.38 + 0.28 * pulse) : 0.22;
    final outerBlur = isCompositionCorrect ? (10.0 + 5.0  * pulse) : 8.0;

    // 외곽 글로우
    canvas.drawCircle(center, radius, Paint()
      ..color      = color.withValues(alpha: glowAlpha)
      ..strokeWidth = 5.0
      ..style      = PaintingStyle.stroke
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, outerBlur));

    // 내곽 글로우
    canvas.drawCircle(center, radius, Paint()
      ..color      = color.withValues(alpha: glowAlpha * 1.6)
      ..strokeWidth = 2.0
      ..style      = PaintingStyle.stroke
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, outerBlur * 0.35));

    // 원 본선: 구도 일치 → 실선 / 불일치 → 점선
    final ring = Paint()
      ..color      = color.withValues(alpha: 0.93)
      ..strokeWidth = 1.5
      ..style      = PaintingStyle.stroke;

    if (isCompositionCorrect) {
      canvas.drawCircle(center, radius, ring);
    } else {
      canvas.drawPath(
        _dashedPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
            9.0, 5.0),
        ring,
      );
    }

    // 중심점 (글로우 + 실점)
    canvas.drawCircle(center, 5.0, Paint()
      ..color      = color.withValues(alpha: 0.5)
      ..style      = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0));
    canvas.drawCircle(center, 2.2, Paint()
      ..color = color.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill);
  }

  // ── 피사체 현위치 마커 (십자 + 점) ───────────────────────────────────────

  void _drawSubjectMarker(Canvas canvas, Offset center, Color color) {
    const arm   = 9.0;
    final paint = Paint()
      ..color      = color.withValues(alpha: 0.60)
      ..strokeWidth = 1.2
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.round;

    canvas.drawLine(Offset(center.dx - arm, center.dy), Offset(center.dx + arm, center.dy), paint);
    canvas.drawLine(Offset(center.dx, center.dy - arm), Offset(center.dx, center.dy + arm), paint);
    canvas.drawCircle(center, 2.5, Paint()
      ..color = color.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill);
  }

  // ── 코 추적 마커 (다이아몬드 + 작은 글로우 원) ───────────────────────────

  void _drawNoseMarker(Canvas canvas, Offset pt, Color color, double pulse) {
    final alpha  = isCompositionCorrect ? (0.90 + 0.08 * pulse) : 0.70;
    final glow   = isCompositionCorrect ? (4.0  + 2.0  * pulse) : 3.0;
    const size   = 6.0;

    // 글로우
    canvas.drawCircle(pt, size + 4, Paint()
      ..color      = color.withValues(alpha: 0.20)
      ..style      = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow));

    // 다이아몬드 (코 마커)
    final path = Path()
      ..moveTo(pt.dx,        pt.dy - size) // top
      ..lineTo(pt.dx + size, pt.dy)        // right
      ..lineTo(pt.dx,        pt.dy + size) // bottom
      ..lineTo(pt.dx - size, pt.dy)        // left
      ..close();

    canvas.drawPath(path, Paint()
      ..color = color.withValues(alpha: alpha * 0.25)
      ..style = PaintingStyle.fill);
    canvas.drawPath(path, Paint()
      ..color      = color.withValues(alpha: alpha)
      ..strokeWidth = 1.5
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.round);

    // 중심점
    canvas.drawCircle(pt, 2.0, Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.fill);
  }

  // ── 구도 유형 레이블 뱃지 ────────────────────────────────────────────────

  void _drawCompositionLabel(
      Canvas canvas, Size size, CompositionType type, double score, Color color) {
    final label = '${type.label}  ${(score * 100).round()}%';
    final tp    = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color:        color.withValues(alpha: isCompositionCorrect ? 0.95 : 0.75),
          fontSize:     11,
          fontWeight:   FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    const padH     = 10.0;
    const padV     = 5.0;
    const topInset = 14.0;

    final badgeLeft = (size.width - tp.width) / 2 - padH;
    final badge     = RRect.fromRectAndRadius(
      Rect.fromLTWH(badgeLeft, topInset, tp.width + padH * 2, tp.height + padV * 2),
      const Radius.circular(10),
    );

    canvas.drawRRect(badge, Paint()..color = Colors.black.withValues(alpha: 0.48));

    if (isCompositionCorrect) {
      canvas.drawRRect(badge, Paint()
        ..color      = color.withValues(alpha: 0.55)
        ..style      = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0));
    }

    tp.paint(canvas, Offset((size.width - tp.width) / 2, topInset + padV));
  }

  // ── 색상 조화 배지 ────────────────────────────────────────────────────────

  // 구도 배지 아래 28px 위치에 색상 조화 유형과 점수 표시
  void _drawHarmonyBadge(Canvas canvas, Size size, ColorHarmonyResult harmony) {
    final harmonyColor = _harmonyColor(harmony.type);
    final isPositive   = harmony.type != ColorHarmonyType.discordant;
    final label        = '${harmony.type.label}  ${(harmony.score * 100).round()}%';

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color:         harmonyColor.withValues(alpha: isPositive ? 0.92 : 0.60),
          fontSize:      11,
          fontWeight:    FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    const padH     = 10.0;
    const padV     = 5.0;
    const topInset = 14.0 + 28.0; // 구도 배지(14) 아래 간격(28)

    final badgeLeft = (size.width - tp.width) / 2 - padH;
    final badge     = RRect.fromRectAndRadius(
      Rect.fromLTWH(badgeLeft, topInset, tp.width + padH * 2, tp.height + padV * 2),
      const Radius.circular(10),
    );

    canvas.drawRRect(badge, Paint()..color = Colors.black.withValues(alpha: 0.48));

    if (isPositive) {
      canvas.drawRRect(badge, Paint()
        ..color       = harmonyColor.withValues(alpha: 0.45)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 3.0));
    }

    tp.paint(canvas, Offset((size.width - tp.width) / 2, topInset + padV));
  }

  // ── 미학 품질 배지 (색상 조화 배지 아래) ─────────────────────────────────

  void _drawAestheticBadge(Canvas canvas, Size size, double score) {
    // 0~1 → 퍼센트 / 색상 결정
    final pct = (score * 100).round();
    final badgeColor = score >= 0.70
        ? const Color(0xFF69F0AE) // 초록: 높은 품질
        : score >= 0.55
            ? const Color(0xFFFFD740) // 노랑: 보통
            : Colors.white70;          // 흰색: 낮은 품질

    final label = '인물 품질  $pct%';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: badgeColor.withValues(alpha: score >= 0.55 ? 0.92 : 0.60),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    const padH     = 10.0;
    const padV     = 5.0;
    const topInset = 14.0 + 28.0 + 28.0; // 구도(14) + 조화(28) + 이 배지(28)

    final badgeLeft = (size.width - tp.width) / 2 - padH;
    final badge = RRect.fromRectAndRadius(
      Rect.fromLTWH(
          badgeLeft, topInset, tp.width + padH * 2, tp.height + padV * 2),
      const Radius.circular(10),
    );

    canvas.drawRRect(badge, Paint()..color = Colors.black.withValues(alpha: 0.48));

    if (score >= 0.55) {
      canvas.drawRRect(
          badge,
          Paint()
            ..color = badgeColor.withValues(alpha: 0.40)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0));
    }

    tp.paint(canvas, Offset((size.width - tp.width) / 2, topInset + padV));
  }

  Color _harmonyColor(ColorHarmonyType type) => switch (type) {
    ColorHarmonyType.complementary => const Color(0xFFFF6E6E), // 붉은 계열 (강한 대비)
    ColorHarmonyType.triadic       => const Color(0xFF69F0AE), // 초록 계열 (균형)
    ColorHarmonyType.analogous     => const Color(0xFF40C4FF), // 하늘 계열 (자연스러움)
    ColorHarmonyType.neutral       => Colors.white70,
    ColorHarmonyType.discordant    => const Color(0xFF9E9E9E), // 회색 (부조화)
  };

  // ── 점선 유틸 ─────────────────────────────────────────────────────────────

  Path _dashedLine(Offset from, Offset to, double dash, double gap) =>
      _dashedPath(Path()..moveTo(from.dx, from.dy)..lineTo(to.dx, to.dy), dash, gap);

  Path _dashedPath(Path source, double dashLen, double gapLen) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      double d    = 0.0;
      bool   draw = true;
      while (d < metric.length) {
        final seg = draw ? dashLen : gapLen;
        if (draw) result.addPath(metric.extractPath(d, d + seg), Offset.zero);
        d    += seg;
        draw  = !draw;
      }
    }
    return result;
  }

  // ── 재드로우 판단 ─────────────────────────────────────────────────────────

  @override
  bool shouldRepaint(covariant CompositionOverlayPainter old) =>
      old.currentScene         != currentScene        ||
      old.isGridEnabled        != isGridEnabled       ||
      old.isAiAssistEnabled    != isAiAssistEnabled   ||
      old.widgetSize           != widgetSize          ||
      old.detectedBoundingBox  != detectedBoundingBox ||
      old.compositionTarget    != compositionTarget   ||
      old.isCompositionCorrect != isCompositionCorrect ||
      old.compositionType      != compositionType     ||
      old.compositionScore     != compositionScore    ||
      old.colorHarmony         != colorHarmony        ||
      old.aestheticScore       != aestheticScore      ||
      old.nosePoint            != nosePoint           ||
      old.rotationTurns        != rotationTurns;
}
