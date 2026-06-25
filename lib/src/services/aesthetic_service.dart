// lib/src/services/aesthetic_service.dart

import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

/// AVA person 미학 품질 추론 서비스
/// 입력 : Float32List [1, 3, 224, 224] NCHW (ImageNet 정규화)
/// 출력 : 0~1 aesthetic quality score
class AestheticService {
  OrtSession? _session;
  bool _isInitialized = false;
  bool _isDisposed = false;
  int _activeCount = 0;

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    try {
      OrtEnv.instance.init();
      final rawAsset =
          await rootBundle.load('assets/models/ava_person_model.onnx');
      final bytes = rawAsset.buffer.asUint8List();
      _session = OrtSession.fromBuffer(bytes, OrtSessionOptions());
      _isInitialized = true;
      log('AestheticService: AVA person model 로드 성공');
    } catch (e) {
      log('AestheticService: 모델 로드 실패 — $e');
    }
  }

  /// 반환값: 0~1 (null = 초기화 미완료 또는 추론 실패)
  Future<double?> score(Float32List input) async {
    if (!_isInitialized || _session == null || _isDisposed) return null;

    _activeCount++;
    OrtValueTensor? tensor;
    List<OrtValue?> outputs = [];
    OrtRunOptions? opts;

    try {
      tensor =
          OrtValueTensor.createTensorWithDataList(input, [1, 3, 224, 224]);
      opts = OrtRunOptions();
      outputs = await _session!.runAsync(opts, {'input': tensor}) ?? [];
      if (_isDisposed) return null;
      final raw = (outputs[0]?.value as List<List<double>>)[0][0];
      return raw.clamp(0.0, 1.0);
    } catch (e) {
      log('AestheticService: 추론 실패 — $e');
      return null;
    } finally {
      tensor?.release();
      for (final v in outputs) {
        v?.release();
      }
      opts?.release();
      _activeCount--;
      // dispose()가 먼저 호출됐다면 마지막 추론 완료 시점에 해제
      if (_isDisposed && _activeCount == 0) {
        _session?.release();
        _session = null;
      }
    }
  }

  void dispose() {
    _isDisposed = true;
    _isInitialized = false;
    // 진행 중인 runAsync가 없을 때만 즉시 해제; 있으면 finally 블록에서 처리
    if (_activeCount == 0) {
      _session?.release();
      _session = null;
    }
  }
}
