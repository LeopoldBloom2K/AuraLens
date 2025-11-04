// tflite_flutter package is used to run TensorFlow Lite models on-device (runModelOnFrame(CameraImage image))
// image_converter() is used to convert CameraImage to TensorImage for model input and DetectionResult model is used to hold the results of object detection and then notifyListeners() is called to update the UI with new detection results.
// lib/src/services/tflite_service.dart

import 'dart:developer';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart'; //
// import 'package:auralens/src/models/detection_result.dart'; // 2번 파일
// import 'package:auralens/src/utils/image_converter.dart'; // (곧 생성할 파일)

/// TFLite 모델 로드 및 추론을 담당하는 서비스
class TFLiteService {
  Interpreter? _interpreter;
  List<String>? _labels;
  bool _isModelLoaded = false;

  /// 모델과 레이블 파일을 로드합니다.
  Future<void> loadModel({
    String modelPath = 'assets/models/mobilenet_ssd.tflite', //
    String labelPath = 'assets/models/labels.txt', //
  }) async {
    try {
      // 인터프리터 로드
      _interpreter = await Interpreter.fromAsset(modelPath);
      
      // 레이블 로드
      final labelsData = await rootBundle.loadString(labelPath);
      _labels = labelsData.split('\n');

      _isModelLoaded = true;
      log('TFLite 모델 및 레이블 로드 성공');

    } catch (e) {
      log('TFLite 모델 로드 실패: $e');
      _isModelLoaded = false;
    }
  }

  /// 실시간 카메라 프레임에서 추론을 실행합니다.
  /// (이 함수의 구체적인 구현은 선택한 모델(예: SSD, YOLO)의
  /// 입력/출력 형식에 따라 크게 달라집니다.)
  Future<List<DetectionResult>> runModelOnFrame(CameraImage cameraImage) async {
    if (!_isModelLoaded || _interpreter == null) {
      log('모델이 로드되지 않았습니다.');
      return [];
    }

    // 1. CameraImage를 TFLite 입력 형식(예: ByteBuffer)으로 변환
    //    (ImageConverter 유틸리티 필요)
    // final inputBytes = await ImageConverter.convertCameraImageToInput(cameraImage);
    
    // 2. 모델의 입력/출력 텐서 준비
    //    (모델마다 Shape이 다름)
    //    예: final input = [inputBytes];
    //    예: final output = { 0: List.filled(10 * 4, 0.0).reshape([1, 10, 4]), ... };
    
    // 3. 인터프리터 실행
    // _interpreter?.runForMultipleInputs([input], output);

    // 4. 출력(output) 데이터를 파싱하여 List<DetectionResult>로 변환
    //    (가장 복잡한 부분)
    
    // 임시 반환 (실제 구현 필요)
    return []; 
  }

  /// 서비스 종료 시 리소스 해제
  void dispose() {
    _interpreter?.close();
  }
}