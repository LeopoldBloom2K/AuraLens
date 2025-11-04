// lib/src/screens/camera/camera_view_model.dart

import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart'; //
// import 'package:auralens/src/models/detection_result.dart';
// import 'package:auralens/src/services/camera_service.dart';
// import 'package:auralens/src/services/tflite_service.dart';
// import 'package:auralens/src/utils/image_converter.dart';

/// CameraScreen의 상태와 비즈니스 로직을 관리하는 ViewModel
class CameraViewModel with ChangeNotifier {
  final CameraService _cameraService;
  final TFLiteService _tfliteService;
  
  // 1. CompositionService 인스턴스 생성
  final CompositionService _compositionService = CompositionService();

  CameraViewModel(this._cameraService, this._tfliteService) {
    _cameraService.addListener(notifyListeners);
    _startModelInference();
  }

  bool _isDetecting = false;
  List<DetectionResult> _detections = [];
  
  // 2. 새로운 상태 변수 추가
  Offset? _compositionTarget; // 구도 목표 지점 (Painter가 사용)
  bool _isCompositionCorrect = false; // 구도 일치 여부 (Painter가 사용)
  Size _screenSize = Size.zero; // 화면 크기 (계산에 필요)

  // 3. UI가 구독할 Getter 추가
  List<DetectionResult> get detections => _detections;
  CameraService get cameraService => _cameraService;
  Offset? get compositionTarget => _compositionTarget;
  bool get isCompositionCorrect => _isCompositionCorrect;
  
  // 4. 화면 크기 업데이트 함수 (UI에서 호출)
  void setScreenSize(Size size) {
    if (_screenSize == Size.zero) {
      _screenSize = size;
      log('ViewModel: 화면 크기 설정됨: $_screenSize');
    }
  }

  /// 모델 추론 스트림을 시작합니다.
  void _startModelInference() {
    log('CameraViewModel: 모델 추론 루프 시작');
    _cameraService.startImageStream((CameraImage cameraImage) {
      if (_isDetecting) return; // 이전 추론이 진행 중이면 스킵

      _isDetecting = true;
      
      // 비동기 추론 실행
      _runInference(cameraImage);
    });
  }

  /// 실제 추론을 실행하고 상태를 업데이트합니다.
  Future<void> _runInference(CameraImage cameraImage) async {
    // 1. 이미지 변환 (모델 입력 형식에 맞게)
    //    MobileNet-SSD float 모델 (입력 -1.0 ~ 1.0) 기준
    final Float32List inputBytes = ImageConverter.convertCameraImageToTFLiteInput(
      cameraImage,
      modelInputSize, // 300
      127.5,          // Mean
      127.5,          // Std
    );

    // 2. TFLite 서비스로 추론 실행
    //    (TFLiteService의 runModelOnFrame이 Uint8List 대신 Float32List를 받도록 수정 필요)
    //    ** 중요: TFLiteService의 runModelOnFrame의 인자 타입을
    //    ** Uint8List -> Float32List로 변경해야 합니다.
    
    // (TFLiteService가 수정되었다고 가정)
    // final List<DetectionResult> results = 
    //     _tfliteService.runModelOnFrame(inputBytes);

    // (임시) TFLiteService가 아직 수정되지 않았다면,
    // TFLiteService의 runModelOnFrame 내부에서 Uint8List.view(inputBytes.buffer)로 캐스팅
    // 여기서는 inputBytes가 Uint8List라고 가정하고 이전 코드 실행
    // (이전 단계의 TFLiteService가 Uint8List를 받으므로)
    
    final List<DetectionResult> results = 
        _tfliteService.runModelOnFrame(Uint8List.view(inputBytes.buffer));
        
        // 5. 구도 계산 로직 추가
    if (results.isNotEmpty) {
      // 첫 번째 감지된 사람의 바운딩 박스 (절대 좌표)
      final Rect detectionBox = Rect.fromLTRB(
        results.first.boundingBox.left * _screenSize.width,
        results.first.boundingBox.top * _screenSize.height,
        results.first.boundingBox.right * _screenSize.width,
        results.first.boundingBox.bottom * _screenSize.height,
      );

      // 5-1. 목표 지점 계산
      _compositionTarget = _compositionService.findClosestPowerPoint(
        detectionBox, 
        _screenSize,
      );
      
      // 5-2. 구도 일치 여부 계산
      _isCompositionCorrect = _compositionService.isCompositionCorrect(
        detectionBox, 
        _compositionTarget, 
        _screenSize,
      );

    } else {
      // 감지된 객체가 없으면 타겟과 피드백 초기화
      _compositionTarget = null;
      _isCompositionCorrect = false;
    }

    // 3. 상태 업데이트 및 UI 알림
    _detections = results;
    notifyListeners();

    // 4. 플래그 해제
    _isDetecting = false;
  }

  /// 사진 촬영
  Future<void> takePicture() async {
    // 갤러리 저장 로직
    final XFile? photo = await _cameraService.takePicture();
    if (photo != null) {
      // gallery_saver 패키지로 저장
      // await GallerySaver.saveImage(photo.path);
      log('사진 촬영 및 저장 완료: ${photo.path}');
    }
  }

  @override
  void dispose() {
    log('CameraViewModel 해제');
    _cameraService.stopImageStream();
    _cameraService.removeListener(notifyListeners);
    super.dispose();
  }
}