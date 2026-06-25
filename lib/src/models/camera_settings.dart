// lib/src/models/camera_settings.dart
import 'dart:ui' show Offset;

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

// 4. 구도 유형
enum CompositionType {
  ruleOfThirds('삼분할'),
  goldenRatio('황금비'),
  goldenSpiral('황금 나선'),
  diagonal('대각선'),
  symmetry('대칭'),
  // ── 데이터 기반 추가 구도 ──────────────────────
  triangle('삼각형'),      // 인물: 삼각형 프레임 안에 피사체 배치
  leadingLines('리딩라인'), // 풍경: 소실점으로 수렴하는 선
  frameInFrame('프레임'),  // 풍경: 자연·건축 프레임 내부 배치
  rectangle('사각 배열');  // 음식: 다중 포컬포인트 직사각형 배열

  final String label;
  const CompositionType(this.label);
}

// 5. 구도 평가 결과
class CompositionResult {
  final CompositionType type;
  final double score;       // 0.0 ~ 1.0 (Gaussian decay)
  final Offset targetPoint;

  const CompositionResult({
    required this.type,
    required this.score,
    required this.targetPoint,
  });
}

// 6. 색상 조화 유형
enum ColorHarmonyType {
  complementary('보색'),    // 색상환 150–180° — 강한 대비
  triadic('삼각 배색'),      // 색상환 108–132° — 균형 있는 생동감
  analogous('유사색'),       // 색상환 0–30°   — 편안하고 자연스러움
  neutral('무채색'),         // 한쪽이 무채색   — 색상 무관
  discordant('부조화');      // 그 외 구간

  final String label;
  const ColorHarmonyType(this.label);
}

// 7. 색상 조화 평가 결과
class ColorHarmonyResult {
  final ColorHarmonyType type;
  final double score; // 0.0 ~ 1.0
  const ColorHarmonyResult({required this.type, required this.score});
}