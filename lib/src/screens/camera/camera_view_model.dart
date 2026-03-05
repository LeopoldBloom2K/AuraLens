// lib/src/screens/camera/camera_view_model.dart

import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:auralens/src/services/camera_service.dart';
import 'package:auralens/src/services/composition_service.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:auralens/src/models/camera_settings.dart';
import 'package:auralens/src/utils/coordinate_scaler.dart';
import 'package:auralens/src/services/tflite_service.dart';
import 'package:auralens/src/utils/image_converter.dart';

// Isolate 함수 클래스 밖으로 이동함 (ML Kit 백그라운드 처리용)
Future<List<DetectedObject>> _runModelOnIsolate(InputImage inputImage) async {
  final options = ObjectDetectorOptions(
    mode: DetectionMode.stream,
    classifyObjects: true,
    multipleObjects: true,
  );
  final detector = ObjectDetector(options: options);
  final results = await detector.processImage(inputImage);
  detector.close();
  return results;
}

class CameraViewModel with ChangeNotifier {
  final CameraService _cameraService;
  final TFLiteService _tfliteService; // TFLite 서비스
  final CompositionService _compositionService = CompositionService();

  late final ObjectDetector _objectDetector;

  XFile? _recentPhoto;
  bool _isDetecting = false;
  List<DetectedObject> _detections = [];
  Offset? _compositionTarget;
  bool _isCompositionCorrect = false;
  Size _screenSize = Size.zero;
  Size? _imageSize;

  // 현재 인식된 화면 상황 (기본 unknown)
  SceneCategory _currentScene = SceneCategory.unknown; 
  SceneCategory get currentScene => _currentScene;

  // UI가 구독할 Getter
  List<DetectedObject> get detections => _detections;
  CameraService get cameraService => _cameraService;
  Offset? get compositionTarget => _compositionTarget;
  bool get isCompositionCorrect => _isCompositionCorrect;
  Size? get imageSize => _imageSize;
  XFile? get recentPhoto => _recentPhoto;

  bool _isGridEnabled = true;
  bool _isAiAssistEnabled = true;
  CameraResolution _cameraResolution = CameraResolution.medium;

  bool get isGridEnabled => _isGridEnabled;
  bool get isAiAssistEnabled => _isAiAssistEnabled;
  CameraResolution get cameraResolution => _cameraResolution;

  // 모델 추론 스트림 활성화 추적 변수
  bool _isStreamingModel = false;

  CameraViewModel(this._cameraService, this._tfliteService) {
    _cameraService.addListener(notifyListeners); // CameraService의 변경사항을 구독

    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);

    if (_cameraService.isCameraInitialized) {
      _startModelInference();
    } else {
      _cameraService.addListener(_onCameraServiceStateChanged);
    }
  }

  // CameraService 상태 변경 리스너
  void _onCameraServiceStateChanged() {
    if (_cameraService.isCameraInitialized && !_isDetecting && !_isStreamingModel) {
      _startModelInference();
    }
    notifyListeners(); 
  }

  void setScreenSize(Size size) {
    if (_screenSize == Size.zero) { // 최초 한 번만 설정
      _screenSize = size;
      log('ViewModel: 화면 크기 설정됨: $_screenSize');
    }
  }

  // =========================================================
  // 🚀 핵심: 두 가지 AI 모델(ML Kit + TFLite) 병렬 실행 로직
  // =========================================================
  void _startModelInference() async {
    final bool isCameraReady = _cameraService.controller?.value.isInitialized ?? false;

    if (!isCameraReady) {
      log('카메라 컨트롤러가 초기화되지 않았습니다. 모델 추론을 시작할 수 없습니다.');
      return; 
    }
        
    if (_isStreamingModel) { 
      log('모델 추론 스트림이 이미 실행 중입니다.');
      return;
    }

    _isStreamingModel = true;

    _cameraService.startImageStream((CameraImage cameraImage) async {
      if (!_isAiAssistEnabled) { 
          _detections = []; 
          _compositionTarget = null;
          _isCompositionCorrect = false;
          _currentScene = SceneCategory.unknown; // 씬 상태 초기화
          notifyListeners();
          return; 
      }

      if (_isDetecting) return; // 이미 추론 중이면 프레임 스킵

      _isDetecting = true;
      try {
        final InputImage? inputImage = _inputImageFromCameraImage(cameraImage);
        if (inputImage == null) {
          _isDetecting = false;
          return;
        }

        // 1. [ML Kit] 바운딩 박스 찾기 (비동기)
        final mlKitFuture = compute(_runModelOnIsolate, inputImage);
        
        // 2. [TFLite] 이미지 전처리 후 장면 분류하기 (비동기)
        final tfliteFuture = compute(ImageConverter.convertCameraImageToModelInput, cameraImage)
            .then((inputMatrix) => _tfliteService.classifyScene(inputMatrix));

        // 두 AI 연산이 끝날 때까지 동시에 기다림
        final results = await Future.wait([mlKitFuture, tfliteFuture]);
        
        final detectedObjects = results[0] as List<DetectedObject>;
        final sceneCategory = results[1] as SceneCategory;

        _imageSize = inputImage.metadata?.size;
        _detections = detectedObjects;
        
        // 상황이 바뀌었을 때만 로그 출력 및 씬 업데이트
        if (_currentScene != sceneCategory) {
          _currentScene = sceneCategory;
          log('📸 현재 촬영 상황 변경 인식: ${_currentScene.label}');
        }

        _updateComposition(_detections);

      } catch (e) {
        log('AI 추론 실패: $e');
      } finally {
        if (hasListeners) {
          notifyListeners();
        }
        _isDetecting = false;
      }
    });
    log('CameraViewModel: ML Kit & TFLite 듀얼 추론 루프 시작 (Image Stream)');
  }

  void _updateComposition(List<DetectedObject> detections) {
    if (detections.isNotEmpty && _imageSize != null && _screenSize != Size.zero) {
      final Rect imageBox = detections.first.boundingBox; // 일단 첫 번째 객체 사용

      final Rect scaledBox = scaleRect(
        rect: imageBox,
        imageSize: _imageSize!,
        widgetSize: _screenSize,
      );

      _compositionTarget = _compositionService.findClosestPowerPoint(
        scaledBox,
        _screenSize,
      );
      _isCompositionCorrect = _compositionService.isCompositionCorrect(
        scaledBox,
        _compositionTarget,
        _screenSize,
      );
    } else {
      _compositionTarget = null;
      _isCompositionCorrect = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final CameraController? controller = _cameraService.controller;
    if (controller == null) {
      log('_inputImageFromCameraImage: CameraController is null.');
      return null;
    }

    final camera = controller.description;
    final sensorOrientation = camera.sensorOrientation;
    final writeBuffer = WriteBuffer();
    for (final Plane plane in image.planes) {
      writeBuffer.putUint8List(plane.bytes);
    }
    
    InputImageRotation rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation) ?? InputImageRotation.rotation0deg;
    } else if (Platform.isAndroid) {
      var rotationCompensation = (sensorOrientation + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation) ?? InputImageRotation.rotation0deg;
    } else {
      rotation = InputImageRotation.rotation0deg;
    }

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    return InputImage.fromBytes(
      bytes: image.planes[0].bytes, 
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow, 
      ),
    );
  }

  Future<void> takePicture() async {
    final XFile? photo = await _cameraService.takePicture();
    if (photo == null) return;
    _recentPhoto = photo;
    notifyListeners();

    try {
      await GallerySaver.saveImage(photo.path);
      log('사진 저장 성공: ${photo.path}');
    } catch (e) {
      log('사진 저장 실패: $e');
    }
  }

  void toggleGrid(bool value) {
    _isGridEnabled = value;
    notifyListeners();
  }

  void toggleAiAssist(bool value) {
    _isAiAssistEnabled = value;
    notifyListeners();
  }

  Future<void> setCameraResolution(CameraResolution resolution) async {
    if (_cameraResolution == resolution) return;
    _cameraResolution = resolution;
    notifyListeners();

    log('카메라 해상도 변경: ${resolution.name}');
    await _cameraService.updateCameraResolution(resolution);
  }

  Future<void> switchCamera() async {
    await _cameraService.switchCamera();
  }
  
  @override
  void dispose() {
    log('CameraViewModel 해제');
    _cameraService.stopImageStream();
    _isStreamingModel = false;  
    _cameraService.removeListener(notifyListeners); 
    _cameraService.removeListener(_onCameraServiceStateChanged); 
    _objectDetector.close();
    super.dispose();
  }
}