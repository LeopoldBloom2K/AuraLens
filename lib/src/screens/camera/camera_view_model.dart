// lib/src/screens/camera/camera_view_model.dart

import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:auralens/src/services/camera_service.dart';
import 'package:auralens/src/services/composition_service.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:auralens/src/models/camera_settings.dart';
import 'package:auralens/src/utils/coordinate_scaler.dart';

// Isolate 함수 클래스 밖으로 이동함
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
  final CompositionService _compositionService = CompositionService();

  late final ObjectDetector _objectDetector;

  XFile? _recentPhoto;
  bool _isDetecting = false;
  List<DetectedObject> _detections = [];
  Offset? _compositionTarget;
  bool _isCompositionCorrect = false;
  Size _screenSize = Size.zero;
  Size? _imageSize;

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

  CameraViewModel(this._cameraService) {
    _cameraService.addListener(notifyListeners); // CameraService의 변경사항을 구독

    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);

    // 카메라 초기화가 완료된 후 이미지 스트림을 시작하도록 변경 (CameraService에서 관리)
    // _startModelInference(); 대신 CameraService의 상태를 관찰합니다.
    if (_cameraService.isCameraInitialized) {
      _startModelInference();
    } else {
      // 카메라 초기화 완료 시 _startModelInference를 호출하기 위한 리스너 추가
      _cameraService.addListener(_onCameraServiceStateChanged);
    }
  }

  // CameraService 상태 변경 리스너
  void _onCameraServiceStateChanged() {
    if (_cameraService.isCameraInitialized && !_isDetecting) {
      _startModelInference();
      _cameraService.removeListener(_onCameraServiceStateChanged); // 한 번 시작 후 제거
    }
    // notifyListeners()는 이미 CameraService.addListener(notifyListeners)에서 처리됨
  }

  void setScreenSize(Size size) {
    if (_screenSize == Size.zero) { // 최초 한 번만 설정
      _screenSize = size;
      log('ViewModel: 화면 크기 설정됨: $_screenSize');
    }
  }


  void _startModelInference() async {
    // [수정] null 체크 및 초기화 상태 확인을 더 간결하게
    final bool isCameraReady = _cameraService.controller?.value.isInitialized ?? false;

    if (!isCameraReady) {
      log('카메라 컨트롤러가 초기화되지 않았습니다. 모델 추론을 시작할 수 없습니다.');
      // 여기서 모델 추론을 시작하지 않고, CameraService가 준비될 때까지 기다립니다.
      return; 
    }
    
    // 이전에 시작되지 않았다면 이미지 스트림을 시작 (CameraService에서)
    _cameraService.startImageStream((CameraImage cameraImage) async {
      // isAiAssistEnabled가 false이면 추론을 건너뜁니다.
      if (!_isAiAssistEnabled) { 
          _detections = []; // 오버레이 지우기
          _compositionTarget = null;
          _isCompositionCorrect = false;
          notifyListeners();
          return; // AI 어시스트가 비활성화되면 추론 로직 건너뛰기
      }

      if (_isDetecting) return; // 이미 추론 중이면 스킵

      _isDetecting = true;
      try {
        final InputImage? inputImage = _inputImageFromCameraImage(cameraImage);
        if (inputImage == null) {
          _isDetecting = false;
          return;
        }

        final List<DetectedObject> results = await compute(_runModelOnIsolate, inputImage);
        _imageSize = inputImage.metadata?.size;
        _detections = results;
        _updateComposition(_detections);

      } catch (e) {
        log('ML Kit 추론 실패: $e');
      } finally {
        if (hasListeners) {
          notifyListeners();
        }
        _isDetecting = false;
      }
    });
    log('CameraViewModel: ML Kit 추론 루프 시작 (Image Stream)');
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

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    // [수정] null 체크 추가: _cameraService.controller가 null이면 바로 반환
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
    final bytes = writeBuffer.done().buffer.asUint8List();

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

    // YUV 플래너(Planar) 이미지이므로,
    // 전체 바이트 버퍼(bytes) 대신 첫 번째 평면(Y)의 바이트(image.planes[0].bytes)를 사용합니다.
return InputImage.fromBytes(
  bytes: image.planes[0].bytes, 
  metadata: InputImageMetadata(
    size: Size(image.width.toDouble(), image.height.toDouble()),
    rotation: rotation,
    format: format,
    bytesPerRow: image.planes[0].bytesPerRow, // Y 평면의 bytesPerRow
  ),
);
  }

  void toggleGrid(bool value) {
    _isGridEnabled = value;
    notifyListeners();
  }

  void toggleAiAssist(bool value) {
    _isAiAssistEnabled = value;
    notifyListeners();
    // AI 어시스트 상태 변경 시 이미지 스트림 재시작/정지 로직은 CameraService에서 처리하는 것이 더 적절합니다.
    // 여기서는 단순히 값을 변경하고 UI를 갱신합니다.
    // 만약 완전히 스트림을 멈춰야 한다면 _cameraService.stopImageStream() 호출 필요.
  }

  @override
  void dispose() {
    log('CameraViewModel 해제');
    _cameraService.stopImageStream();
    _cameraService.removeListener(notifyListeners); // CameraService 리스너 해제
    _cameraService.removeListener(_onCameraServiceStateChanged); // 추가된 리스너 해제
    _objectDetector.close();
    super.dispose();
  }

  Future<void> setCameraResolution(CameraResolution resolution) async {
    if (_cameraResolution == resolution) return;
    _cameraResolution = resolution;
    notifyListeners();

    // CameraService에서 실제 해상도 변경 로직을 호출합니다.
    // 이는 카메라 미리보기 스트림을 일시 중지하고 다시 시작해야 할 수 있습니다.
    log('카메라 해상도 변경: ${resolution.name}');
    await _cameraService.updateCameraResolution(resolution);
  }
}