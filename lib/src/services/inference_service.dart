// lib/src/services/inference_service.dart

import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:auralens/src/models/camera_settings.dart';
import 'package:auralens/src/services/model_gate.dart';

class InferenceService {
  OrtSession? _session;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (!ModelGate.isReady) {
      log('⏭️ InferenceService: 게이트 닫힘 — 초기화 건너뜁니다.');
      return;
    }

    try {
      OrtEnv.instance.init();
      final sessionOptions = OrtSessionOptions();
      final rawAsset = await rootBundle.load('assets/models/auralens_model.onnx');
      final bytes = rawAsset.buffer.asUint8List();
      _session = OrtSession.fromBuffer(bytes, sessionOptions);
      _isInitialized = true;
      log('✅ ONNX 모델 로드 성공');
    } catch (e) {
      log('❌ ONNX 모델 로드 실패: $e');
    }
  }

  /// 입력: Float32List [1, 3, 224, 224] (NCHW)
  /// PyTorch export 시 input_names 에 지정한 이름과 'input' 키가 일치해야 합니다.
  Future<SceneCategory> classifyScene(Float32List inputData) async {
    if (!_isInitialized || _session == null) {
      log('모델이 초기화되지 않았습니다.');
      return SceneCategory.unknown;
    }

    OrtValueTensor? inputTensor;
    List<OrtValue?> outputs = [];
    OrtRunOptions? runOptions;

    try {
      inputTensor = OrtValueTensor.createTensorWithDataList(inputData, [1, 3, 224, 224]);
      runOptions = OrtRunOptions();
      outputs = await _session!.runAsync(runOptions, {'input': inputTensor}) ?? [];

      final probabilities = (outputs[0]?.value as List<List<double>>)[0];

      double maxProb = probabilities[0];
      int maxIndex = 0;
      for (int i = 1; i < probabilities.length; i++) {
        if (probabilities[i] > maxProb) {
          maxProb = probabilities[i];
          maxIndex = i;
        }
      }

      log('분류 결과: 인덱스 $maxIndex, 확률: ${maxProb.toStringAsFixed(2)}');

      switch (maxIndex) {
        case 0:
          return SceneCategory.person;
        case 1:
          return SceneCategory.food;
        case 2:
          return SceneCategory.scenery;
        default:
          return SceneCategory.unknown;
      }
    } catch (e) {
      log('추론 중 에러 발생: $e');
      return SceneCategory.unknown;
    } finally {
      inputTensor?.release();
      for (final v in outputs) {
        v?.release();
      }
      runOptions?.release();
    }
  }

  void dispose() {
    _session?.release();
    OrtEnv.instance.release();
  }
}
