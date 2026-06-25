// lib/src/services/color_harmony_service.dart

import 'dart:math' show sin, cos, atan2, pi;
import 'dart:typed_data';
import 'package:auralens/src/models/camera_settings.dart';

/// compute() 경계를 넘기 위해 CameraImage 대신 원시 타입 값만 전달.
/// CameraImage.planes[n].bytes 는 native buffer 뷰일 수 있어 isolate로
/// 직접 전송 시 SendPort 복사 실패 또는 use-after-free가 발생할 수 있음.
/// 호출 측에서 Uint8List.fromList() 로 Dart 힙에 복사한 뒤 전달해야 함.
class ColorHarmonyInput {
  final int camW;          // img.width  (raw camera width  = ML Kit height after rotation90deg)
  final int camH;          // img.height (raw camera height = ML Kit width  after rotation90deg)
  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixStride;
  final double boxL, boxT, boxR, boxB; // 위젯 좌표계 바운딩박스
  final double scrW, scrH;             // 위젯 크기

  const ColorHarmonyInput({
    required this.camW,
    required this.camH,
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixStride,
    required this.boxL, required this.boxT,
    required this.boxR, required this.boxB,
    required this.scrW, required this.scrH,
  });
}

class ColorHarmonyService {
  // ── compute() 진입점 ────────────────────────────────────────────────────────

  static ColorHarmonyResult? analyze(ColorHarmonyInput input) {
    // ML Kit rotation90deg 후 좌표계:
    //   ML Kit width  = img.height = camH
    //   ML Kit height = img.width  = camW
    final camH = input.camH.toDouble();
    final camW = input.camW.toDouble();

    // 위젯 좌표 → ML Kit rotation90deg 이미지 좌표
    final mlL = (input.boxL / input.scrW) * camH;
    final mlR = (input.boxR / input.scrW) * camH;
    final mlT = (input.boxT / input.scrH) * camW;
    final mlB = (input.boxB / input.scrH) * camW;

    final subjectHSVs    = _sampleRect(input, mlL, mlT, mlR, mlB, 12);
    final backgroundHSVs = _sampleBackground(input, mlL, mlT, mlR, mlB, camH, camW);

    if (subjectHSVs.isEmpty || backgroundHSVs.isEmpty) return null;

    final sHue = _dominantHue(subjectHSVs);
    final bHue = _dominantHue(backgroundHSVs);

    if (sHue == null || bHue == null) {
      return const ColorHarmonyResult(type: ColorHarmonyType.neutral, score: 0.55);
    }

    return _classify(_hueDiff(sHue, bHue), subjectHSVs, backgroundHSVs);
  }

  // ── 픽셀 샘플링 ─────────────────────────────────────────────────────────────

  // ML Kit 좌표 사각형 안을 grid×grid 격자로 샘플
  static List<List<double>> _sampleRect(
    ColorHarmonyInput input,
    double mlL, double mlT, double mlR, double mlB,
    int grid,
  ) {
    final result = <List<double>>[];
    for (int gy = 0; gy < grid; gy++) {
      for (int gx = 0; gx < grid; gx++) {
        final mlX = mlL + (mlR - mlL) * gx / grid;
        final mlY = mlT + (mlB - mlT) * gy / grid;
        final hsv = _mlToHsv(input, mlX, mlY);
        if (hsv != null) result.add(hsv);
      }
    }
    return result;
  }

  // 바운딩박스 바깥 4면에서 배경 샘플
  static List<List<double>> _sampleBackground(
    ColorHarmonyInput input,
    double mlL, double mlT, double mlR, double mlB,
    double camH, double camW,
  ) {
    const g = 8;
    final r = <List<double>>[];
    if (mlT > camW * 0.08) r.addAll(_sampleRect(input, 0,         0,         camH,       mlT * 0.85, g));
    if (mlB < camW * 0.92) r.addAll(_sampleRect(input, 0,         mlB * 1.1, camH,       camW,       g));
    if (mlL > camH * 0.08) r.addAll(_sampleRect(input, 0,         mlT,       mlL * 0.85, mlB,        g));
    if (mlR < camH * 0.92) r.addAll(_sampleRect(input, mlR * 1.1, mlT,       camH,       mlB,        g));
    return r;
  }

  // ML Kit 회전 좌표 → 원본 카메라 픽셀 → HSV
  // rotation90deg CW: rotated(mlX, mlY) → original camX=mlY, camY=camH-1-mlX
  static List<double>? _mlToHsv(ColorHarmonyInput input, double mlX, double mlY) {
    final camX = mlY.round().clamp(0, input.camW - 1);
    final camY = (input.camH - 1 - mlX).round().clamp(0, input.camH - 1);
    final rgb  = _readYuv(input, camX, camY);
    if (rgb == null) return null;
    final hsv = _rgbToHsv(rgb[0], rgb[1], rgb[2]);
    // 너무 어둡거나(V<0.20), 너무 밝거나(V>0.95), 채도 낮은(S<0.15) 픽셀 제외
    if (hsv[2] < 0.20 || hsv[2] > 0.95 || hsv[1] < 0.15) return null;
    return hsv;
  }

  // ── 색상 분석 ───────────────────────────────────────────────────────────────

  // 채도 가중 circular mean으로 dominant hue(0–1) 산출
  static double? _dominantHue(List<List<double>> hsvs) {
    final sat = hsvs.where((h) => h[1] > 0.20).toList();
    if (sat.isEmpty) return null;
    double sn = 0, cs = 0;
    for (final h in sat) {
      final rad = h[0] * 2 * pi;
      sn += sin(rad) * h[1]; // 채도를 가중치로
      cs += cos(rad) * h[1];
    }
    final m = atan2(sn, cs) / (2 * pi);
    return m < 0 ? m + 1.0 : m;
  }

  // 두 hue(0–1) 사이의 최소 각도 차이 → 0–0.5 반환
  static double _hueDiff(double h1, double h2) {
    final d = (h1 - h2).abs();
    return d > 0.5 ? 1.0 - d : d;
  }

  // 색상 조화 유형 분류
  static ColorHarmonyResult _classify(
    double diff, // 0–0.5 (= 0°–180°)
    List<List<double>> sHSVs,
    List<List<double>> bHSVs,
  ) {
    final sMeanSat = sHSVs.map((h) => h[1]).reduce((a, b) => a + b) / sHSVs.length;
    final bMeanSat = bHSVs.map((h) => h[1]).reduce((a, b) => a + b) / bHSVs.length;

    if (sMeanSat < 0.15 || bMeanSat < 0.15) {
      return const ColorHarmonyResult(type: ColorHarmonyType.neutral, score: 0.55);
    }

    final deg = diff * 360; // 0°–180°

    if (deg <= 30) {
      // 유사색: 0°에 가까울수록 최대 0.90
      return ColorHarmonyResult(
        type: ColorHarmonyType.analogous,
        score: 0.70 + 0.20 * (1 - deg / 30),
      );
    }
    if (deg >= 150) {
      // 보색: 180°에 가까울수록 최대 1.00
      return ColorHarmonyResult(
        type: ColorHarmonyType.complementary,
        score: 0.60 + 0.40 * ((deg - 150) / 30),
      );
    }
    if (deg >= 108 && deg <= 132) {
      // 삼각 배색: 120° ±12° 허용, 최대 0.90
      return ColorHarmonyResult(
        type: ColorHarmonyType.triadic,
        score: 0.65 + 0.25 * (1 - (deg - 120).abs() / 12),
      );
    }
    return const ColorHarmonyResult(type: ColorHarmonyType.discordant, score: 0.15);
  }

  // ── YUV 유틸 ───────────────────────────────────────────────────────────────

  static List<int>? _readYuv(ColorHarmonyInput input, int x, int y) {
    try {
      final yIdx  = y * input.yRowStride + x;
      if (yIdx >= input.yBytes.length) return null;
      final yv    = input.yBytes[yIdx];

      final uvIdx = (y ~/ 2) * input.uvRowStride + (x ~/ 2) * input.uvPixStride;
      if (uvIdx >= input.uBytes.length || uvIdx >= input.vBytes.length) return null;
      final uv    = input.uBytes[uvIdx];
      final vv    = input.vBytes[uvIdx];

      // BT.601 YCbCr → RGB
      final yf = yv.toDouble();
      final uf = uv - 128.0;
      final vf = vv - 128.0;
      return [
        (yf + 1.402    * vf).clamp(0, 255).round(),
        (yf - 0.344136 * uf - 0.714136 * vf).clamp(0, 255).round(),
        (yf + 1.772    * uf).clamp(0, 255).round(),
      ];
    } catch (_) {
      return null;
    }
  }

  static List<double> _rgbToHsv(int r, int g, int b) {
    final rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
    final max = rf > gf ? (rf > bf ? rf : bf) : (gf > bf ? gf : bf);
    final min = rf < gf ? (rf < bf ? rf : bf) : (gf < bf ? gf : bf);
    final delta = max - min;
    double h = 0;
    if (delta > 0) {
      if (max == rf)      { h = ((gf - bf) / delta) % 6; }
      else if (max == gf) { h = (bf - rf) / delta + 2; }
      else                { h = (rf - gf) / delta + 4; }
      h /= 6;
      if (h < 0) { h += 1; }
    }
    return [h, max == 0 ? 0.0 : delta / max, max];
  }
}
