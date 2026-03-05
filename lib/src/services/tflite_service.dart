// lib/src/services/tflite_service.dart

import 'dart:developer';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:auralens/src/models/camera_settings.dart';

class TFLiteService {
  Interpreter? _interpreter;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// 1. TFLite 모델 초기화 (메모리에 로드)
  Future<void> initialize() async {
    try {
      // pubspec.yaml에 등록한 모델 경로
      _interpreter = await Interpreter.fromAsset('assets/models/auralens_model.tflite');
      _isInitialized = true;

      // 모델의 입출력 형태(Shape) 로그 확인용
      log('✅ TFLite 모델 로드 성공!');
      log('Input shape: ${_interpreter?.getInputTensor(0).shape}');
      log('Output shape: ${_interpreter?.getOutputTensor(0).shape}');

    } catch (e) {
      log('❌ TFLite 모델 로드 실패: $e');
    }
  }

  /// 2. 이미지 분류 추론 실행
  /// (입력값은 224x224 크기로 변환 및 정규화된 3D 혹은 4D 배열이어야 합니다)
  Future<SceneCategory> classifyScene(List<dynamic> inputImageMatrix) async {
    if (!_isInitialized || _interpreter == null) {
      log('모델이 초기화되지 않았습니다.');
      return SceneCategory.unknown;
    }

    try {
      // 출력값을 담을 배열 준비 (클래스가 3개이므로 [1, 3] 형태의 배열)
      // 예: [[0.1, 0.8, 0.1]] -> 음식(1)일 확률이 80%
      var output = List.generate(1, (_) => List.filled(3, 0.0));

      // 모델 추론 실행 (입력 행렬을 넣고 output 배열에 결과를 받음)
      _interpreter!.run(inputImageMatrix, output);

      // 확률이 가장 높은 인덱스(0, 1, 2) 찾기
      List<double> probabilities = output[0];
      double maxProb = probabilities[0];
      int maxIndex = 0;

      for (int i = 1; i < probabilities.length; i++) {
        if (probabilities[i] > maxProb) {
          maxProb = probabilities[i];
          maxIndex = i;
        }
      }

      // 분류 결과 반환
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
    }
  }

  /// 자원 해제
  void dispose() {
    _interpreter?.close();
  }
}