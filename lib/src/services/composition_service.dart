// lib/src/services/composition_service.dart

import 'dart:math' show exp;
import 'dart:ui';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:auralens/src/models/camera_settings.dart';
import 'package:auralens/src/utils/coordinate_scaler.dart';

// 다중 피사체 삼각형 구도 결과 (기존 유지)
class TriangularComposition {
  final Offset point1;
  final Offset point2;
  final Offset point3;
  TriangularComposition({required this.point1, required this.point2, required this.point3});
}

/// 멀티 구도 경쟁 평가 서비스.
///
/// [evaluateAll]이 핵심 메서드: 5개 구도를 동시 채점해 점수 내림차순으로 반환.
/// 점수는 피사체 중심과 각 구도 목표점 사이의 Gaussian decay로 계산됩니다.
///   score = exp(-d² / 2σ²)
/// d=0 → score=1.0, d=σ → score≈0.61, d=2σ → score≈0.14
class CompositionService {
  static const double _phi = 1.618033988749895; // 황금비 φ

  // ── 장면별 추천 구도 ──────────────────────────────────────────────────────
  // person : 삼각형·삼분할·황금비   — 그룹1: 인물+배경 삼각형 프레임, 파워포인트 배치
  // food   : 사각배열·삼분할·대칭   — 그룹4: 메인+사이드+소스 다중 포컬포인트 배열
  // scenery: 리딩라인·프레임·삼분할 — 그룹2/5: 소실점 수렴 또는 자연·건축 프레임
  static const Map<SceneCategory, List<CompositionType>> _sceneCompositions = {
    SceneCategory.person:  [CompositionType.triangle,     CompositionType.ruleOfThirds, CompositionType.goldenRatio],
    SceneCategory.food:    [CompositionType.rectangle,    CompositionType.ruleOfThirds, CompositionType.symmetry],
    SceneCategory.scenery: [CompositionType.leadingLines, CompositionType.frameInFrame, CompositionType.ruleOfThirds],
  };

  // ── 멀티 구도 경쟁 ────────────────────────────────────────────────────────

  /// 장면 유형에 맞는 구도만 평가해 점수 내림차순으로 반환.
  /// [scene]이 unknown이면 9개 구도 전체를 평가합니다.
  /// 반환 리스트의 첫 번째 원소가 현재 프레임에 가장 적합한 구도.
  List<CompositionResult> evaluateAll(Rect subjectBox, Size screen,
      {SceneCategory scene = SceneCategory.unknown}) {
    if (subjectBox.isEmpty) return [];

    final c = subjectBox.center;
    final W = screen.width;
    final H = screen.height;

    final all = [
      _ruleOfThirds(c, W, H),
      _goldenRatio(c, W, H),
      _goldenSpiral(c, W, H),
      _diagonal(c, W, H),
      _symmetry(c, W, H),
      _triangle(c, W, H),
      _leadingLines(c, W, H),
      _frameInFrame(c, W, H),
      _rectangle(c, W, H),
    ];

    final allowed = _sceneCompositions[scene];
    final results = allowed == null
        ? all
        : all.where((r) => allowed.contains(r.type)).toList();

    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  // ── 개별 구도 채점 ────────────────────────────────────────────────────────

  // 삼분할: 4개 교차점 (W/3, H/3) 패밀리, σ = W×0.14
  CompositionResult _ruleOfThirds(Offset c, double W, double H) {
    final pts = [
      Offset(W / 3,     H / 3),
      Offset(W * 2 / 3, H / 3),
      Offset(W / 3,     H * 2 / 3),
      Offset(W * 2 / 3, H * 2 / 3),
    ];
    final (score, target) = _nearestGaussian(c, pts, W * 0.14);
    return CompositionResult(type: CompositionType.ruleOfThirds, score: score, targetPoint: target);
  }

  // 황금비: 4개 φ-교차점 (1/φ ≈ 0.618, 1-1/φ ≈ 0.382), σ = W×0.13
  CompositionResult _goldenRatio(Offset c, double W, double H) {
    final k = 1.0 / _phi; // ≈ 0.618
    final pts = [
      Offset(W * k,       H * k),
      Offset(W * (1 - k), H * k),
      Offset(W * k,       H * (1 - k)),
      Offset(W * (1 - k), H * (1 - k)),
    ];
    final (score, target) = _nearestGaussian(c, pts, W * 0.13);
    return CompositionResult(type: CompositionType.goldenRatio, score: score, targetPoint: target);
  }

  // 황금 나선: 4개 회전 방향 수렴점(eye). 황금비와 동일 좌표지만 σ = W×0.10으로
  // 더 엄격하게 평가 — 나선은 하나의 수렴점에 정밀하게 위치해야 함.
  // k2 = 1/φ² ≈ 0.382 (짧은 변 분할점)
  CompositionResult _goldenSpiral(Offset c, double W, double H) {
    final k1 = 1.0 / _phi;          // ≈ 0.618
    final k2 = 1.0 / (_phi * _phi); // ≈ 0.382
    final pts = [
      Offset(W * k2, H * k1), // 좌하단 수렴
      Offset(W * k1, H * k2), // 우상단 수렴
      Offset(W * k2, H * k2), // 좌상단 수렴
      Offset(W * k1, H * k1), // 우하단 수렴
    ];
    final (score, target) = _nearestGaussian(c, pts, W * 0.10);
    return CompositionResult(type: CompositionType.goldenSpiral, score: score, targetPoint: target);
  }

  // 대각선: 주대각선 (0,0)→(W,H) 또는 반대각선 (W,0)→(0,H) 위 수직 투영.
  // σ = W×0.12 — 대각선에 가까울수록 높은 점수
  CompositionResult _diagonal(Offset c, double W, double H) {
    final proj1 = _project(c, Offset.zero, Offset(W, H));
    final proj2 = _project(c, Offset(W, 0), Offset(0, H));
    final d1 = (c - proj1).distance;
    final d2 = (c - proj2).distance;
    final (dist, target) = d1 <= d2 ? (d1, proj1) : (d2, proj2);
    return CompositionResult(
      type: CompositionType.diagonal,
      score: _g(dist, W * 0.12),
      targetPoint: target,
    );
  }

  // 대칭: 수직 대칭축 x=W/2 기준 수평 거리. σ = W×0.12
  // 목표점은 대칭축 위의 피사체 높이 그대로 (Offset(W/2, c.dy))
  CompositionResult _symmetry(Offset c, double W, double H) {
    final dist = (c.dx - W / 2).abs();
    return CompositionResult(
      type: CompositionType.symmetry,
      score: _g(dist, W * 0.12),
      targetPoint: Offset(W / 2, c.dy),
    );
  }

  // ── 데이터 기반 구도 채점 (4개 신규) ─────────────────────────────────────

  // 삼각형 구도 (person): 꼭짓점 3개 + 무게중심 중 최근접. σ = W×0.16
  // 그룹1 _05: 시안 삼각형 — apex(W/2, H×0.18), baseL(W×0.18, H×0.72), baseR(W×0.82, H×0.72)
  CompositionResult _triangle(Offset c, double W, double H) {
    final apex     = Offset(W / 2,    H * 0.18);
    final baseL    = Offset(W * 0.18, H * 0.72);
    final baseR    = Offset(W * 0.82, H * 0.72);
    final centroid = Offset(W / 2,    H * ((0.18 + 0.72 + 0.72) / 3));
    final (score, target) = _nearestGaussian(c, [apex, baseL, baseR, centroid], W * 0.16);
    return CompositionResult(type: CompositionType.triangle, score: score, targetPoint: target);
  }

  // 리딩라인 구도 (scenery): 소실점 수렴 후보 4개. σ = W×0.15
  // 그룹2: 나무 터널(대칭 소실점), 계단 난간(편향 소실점)
  CompositionResult _leadingLines(Offset c, double W, double H) {
    final pts = [
      Offset(W / 2,    H * 0.38), // 대칭 소실점 (터널·복도)
      Offset(W / 2,    H * 0.42), // 소실점 하향 변형
      Offset(W * 0.42, H * 0.40), // 좌편향 소실점 (계단)
      Offset(W * 0.58, H * 0.40), // 우편향 소실점
    ];
    final (score, target) = _nearestGaussian(c, pts, W * 0.15);
    return CompositionResult(type: CompositionType.leadingLines, score: score, targetPoint: target);
  }

  // 프레임 인 프레임 구도 (scenery): 내부 프레임 중앙 영역. σ = W×0.20
  // 그룹5: 경복궁 대문(건축 프레임), 경회루+나무(자연 프레임)
  CompositionResult _frameInFrame(Offset c, double W, double H) {
    final pts = [
      Offset(W / 2,    H * 0.47), // 내부 프레임 중앙 (살짝 위)
      Offset(W / 2,    H * 0.50), // 정중앙
      Offset(W * 0.45, H * 0.47), // 좌편향
      Offset(W * 0.55, H * 0.47), // 우편향
    ];
    final (score, target) = _nearestGaussian(c, pts, W * 0.20);
    return CompositionResult(type: CompositionType.frameInFrame, score: score, targetPoint: target);
  }

  // 사각 배열 구도 (food): 음식 배치 4 포컬포인트 중 최근접. σ = W×0.13
  // 그룹4: 메인 접시(중앙하단)·사이드(우상단)·소스(좌상단)·가니쉬(좌중)
  CompositionResult _rectangle(Offset c, double W, double H) {
    final pts = [
      Offset(W * 0.50, H * 0.62), // 메인 접시 (중앙 하단)
      Offset(W * 0.68, H * 0.40), // 사이드 접시 (우상단)
      Offset(W * 0.35, H * 0.36), // 소스·양념 (좌상단)
      Offset(W * 0.18, H * 0.58), // 가니쉬·소품 (좌중)
    ];
    final (score, target) = _nearestGaussian(c, pts, W * 0.13);
    return CompositionResult(type: CompositionType.rectangle, score: score, targetPoint: target);
  }

  // ── 수학 유틸 ────────────────────────────────────────────────────────────

  // Gaussian: score = exp(-d²/2σ²)
  static double _g(double dist, double sigma) =>
      exp(-(dist * dist) / (2.0 * sigma * sigma));

  // 후보 목록 중 Gaussian 점수 최고점과 해당 좌표 반환
  static (double, Offset) _nearestGaussian(
      Offset subject, List<Offset> candidates, double sigma) {
    double best  = -1.0;
    Offset bestPt = candidates.first;
    for (final p in candidates) {
      final s = _g((subject - p).distance, sigma);
      if (s > best) {
        best   = s;
        bestPt = p;
      }
    }
    return (best, bestPt);
  }

  // 선분 AB 위에 점 P를 수직 투영 (구간 클램핑 포함)
  static Offset _project(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return a;
    final t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2;
    final tc = t.clamp(0.0, 1.0);
    return Offset(a.dx + ab.dx * tc, a.dy + ab.dy * tc);
  }

  // ── 하위 호환 메서드 (기존 ViewModel 코드가 호출하는 인터페이스 유지) ──────

  List<Offset> getPowerPoints(Size screenSize) {
    final w3 = screenSize.width / 3;
    final h3 = screenSize.height / 3;
    return [Offset(w3, h3), Offset(w3 * 2, h3), Offset(w3, h3 * 2), Offset(w3 * 2, h3 * 2)];
  }

  Offset? findClosestPowerPoint(Rect detectionBox, Size screenSize) {
    final results = evaluateAll(detectionBox, screenSize);
    return results.isEmpty ? null : results.first.targetPoint;
  }

  bool isCompositionCorrect(Rect detectionBox, Offset? targetPoint, Size screenSize) {
    if (targetPoint == null || detectionBox.isEmpty) return false;
    return (detectionBox.center - targetPoint).distance < screenSize.width * 0.05;
  }

  TriangularComposition? calculateTriangularCompositionTargets(
    List<DetectedObject> detections, {
    required Size imageSize,
    required Size widgetSize,
  }) {
    if (detections.length < 2) return null;
    detections.sort((a, b) =>
        (b.boundingBox.width * b.boundingBox.height)
            .compareTo(a.boundingBox.width * a.boundingBox.height));
    final p1 = scaleRect(rect: detections[0].boundingBox, imageSize: imageSize, widgetSize: widgetSize).center;
    final p2 = scaleRect(rect: detections[1].boundingBox, imageSize: imageSize, widgetSize: widgetSize).center;
    final p3 = Offset(widgetSize.width / 2, widgetSize.height / 4);
    return TriangularComposition(point1: p1, point2: p2, point3: p3);
  }
}
