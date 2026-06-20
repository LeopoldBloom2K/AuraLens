// lib/src/services/model_gate.dart

import 'dart:developer';
import 'package:flutter/services.dart';

const String _kModelAssetPath = 'assets/models/auralens_model.onnx';

/// 앱 시작 시 모델 파일 존재 여부를 단 한 번 확인합니다.
/// InferenceService 는 이 게이트를 참조해 초기화 여부를 결정합니다.
///
/// 사용법:
///   main() → await ModelGate.probe() 먼저 호출
///   이후   → ModelGate.isReady 로 상태 참조
class ModelGate {
  ModelGate._();

  static bool _isReady = false;

  /// true  → AI 모드 (모델 파일 확인됨)
  /// false → 카메라 전용 모드 (모델 파일 없음)
  static bool get isReady => _isReady;

  /// assets/models/auralens_model.onnx 의 존재 여부를 확인합니다.
  /// main() 에서 다른 서비스 초기화보다 먼저 호출해야 합니다.
  static Future<void> probe() async {
    try {
      await rootBundle.load(_kModelAssetPath);
      _isReady = true;
      log('🔓 ModelGate: $_kModelAssetPath 확인됨 → AI 모드');
    } catch (_) {
      _isReady = false;
      log('🔒 ModelGate: 모델 파일 없음 → 카메라 전용 모드로 실행합니다.');
    }
  }
}
