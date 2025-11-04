// tflite_flutter package is used to run TensorFlow Lite models on-device (runModelOnFrame(CameraImage image))
// image_converter() is used to convert CameraImage to TensorImage for model input and DetectionResult model is used to hold the results of object detection and then notifyListeners() is called to update the UI with new detection results.
// lib/src/services/tflite_service.dart

import 'dart:developer';
import 'dart:typed_data'; // Uint8List 사용
import 'package:flutter/material.dart'; // Rect 사용
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
// import 'package:auralens/src/models/detection_result.dart';

// (TFLiteService 클래스 상단에 모델 관련 상수 정의)
const int modelInputSize = 300; // MobileNet-SSD는 300x300을 사용
const double confidenceThreshold = 0.5; // 신뢰도 50% 이상만 감지

class TFLiteService {
  Interpreter? _interpreter;
  List<String>? _labels;
  bool _isModelLoaded = false;

  // 모델의 출력 형식에 맞게 텐서 모양 정의
  // MobileNet-SSD TFLite (non-quantized, float32) 기준
  // 1. 바운딩 박스 (위치)
  List<List<double>>? _outputBoxes; // [1, 10, 4] (10개 감지, [top, left, bottom, right])
  // 2. 클래스 ID
  List<double>? _outputClasses; // [1, 10]
  // 3. 신뢰도 점수
  List<double>? _outputScores; // [1, 10]
  // 4. 총 감지 수
  double? _numDetections; // [1]

  Future<void> loadModel({
    String modelPath = 'assets/models/mobilenet_ssd.tflite',
    String labelPath = 'assets/models/labels.txt',
  }) async {
    try {
      _interpreter = await Interpreter.fromAsset(modelPath);

      // 모델의 출력 텐서 모양에 맞게 메모리 할당
      // (모델마다 이 부분이 다릅니다!)
      final outputTensors = _interpreter!.getOutputTensors();

      // MobileNet-SSD는 4개의 출력을 가짐
      // 0: locations (Boxes), 1: classes, 2: scores, 3: numDetections
      // (순서는 모델 변환 방식에 따라 다를 수 있으므로 확인 필요)
      
      // 예시: outputTensors[0].shape = [1, 10, 4] (Boxes)
      _outputBoxes = List.filled(
        outputTensors[0].shape[0] * outputTensors[0].shape[1], 
        List.filled(outputTensors[0].shape[2], 0.0),
      ).reshape(outputTensors[0].shape);

      // 예시: outputTensors[1].shape = [1, 10] (Classes)
      _outputClasses = List.filled(
        outputTensors[1].shape[0] * outputTensors[1].shape[1], 0.0,
      ).reshape(outputTensors[1].shape);

      // 예시: outputTensors[2].shape = [1, 10] (Scores)
      _outputScores = List.filled(
        outputTensors[2].shape[0] * outputTensors[2].shape[1], 0.0,
      ).reshape(outputTensors[2].shape);

      // 예시: outputTensors[3].shape = [1] (Num Detections)
      _numDetections = 0.0; // 값은 하나만 나옴

      final labelsData = await rootBundle.loadString(labelPath);
      _labels = labelsData.split('\n');

      _isModelLoaded = true;
      log('TFLite 모델 및 레이블 로드 성공');
    } catch (e) {
      log('TFLite 모델 로드 실패: $e');
      _isModelLoaded = false;
    }
  }

  /// (이전 단계에서 Uint8List를 받도록 수정됨)
  /// Uint8List 입력을 받아 추론을 실행합니다.
  List<DetectionResult> runModelOnFrame(Uint8List inputBytes) {
    if (!_isModelLoaded || _interpreter == null) {
      log('모델이 로드되지 않았습니다.');
      return [];
    }

    // 1. TFLite 입력 준비 (Uint8List [1, 300, 300, 3])
    //    (모델에 따라 List<double>의 Float32List가 필요할 수 있음)
    //    만약 Float32 모델이라면 ImageConverter 수정 필요
    final input = [inputBytes.reshape([1, modelInputSize, modelInputSize, 3])];

    // 2. 출력 맵 준비 (할당된 메모리 사용)
    final outputs = {
      0: _outputBoxes!,
      1: _outputClasses!,
      2: _outputScores!,
      3: [_numDetections!], // 1D List로 감싸기
    };

    // 3. 인터프리터 실행
    try {
      _interpreter!.runForMultipleInputs(input, outputs);
    } catch (e) {
      log('모델 추론 실패: $e');
      return [];
    }


    // 4. 출력 데이터 파싱
    final int numDetections = outputs[3]![0].toInt(); // 감지된 총 객체 수
    final List<DetectionResult> detections = [];

    for (int i = 0; i < numDetections; i++) {
      final double score = _outputScores![0][i]; // 신뢰도

      // 신뢰도가 임계값 미만이면 무시
      if (score < confidenceThreshold) continue;

      final int classId = _outputClasses![0][i].toInt();
      final String label = _labels![classId]; // 레이블 이름 찾기

      // 'person'만 감지하도록 필터링 (README.md의 목표)
      if (label != 'person') continue;

      // 바운딩 박스 좌표 (0.0 ~ 1.0 사이의 상대 좌표)
      final double top = _outputBoxes![0][i][0];
      final double left = _outputBoxes![0][i][1];
      final double bottom = _outputBoxes![0][i][2];
      final double right = _outputBoxes![0][i][3];

      // Rect는 (left, top, right, bottom) 순서
      final Rect boundingBox = Rect.fromLTRB(left, top, right, bottom);

      detections.add(DetectionResult(
        confidence: score,
        label: label,
        boundingBox: boundingBox,
      ));
    }

    return detections;
  }

  void dispose() {
    _interpreter?.close();
  }
}