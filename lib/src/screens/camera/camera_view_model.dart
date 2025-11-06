// lib/src/screens/camera/camera_view_model.dart  tflitemodel -> google ML kit으로 변경

import 'dart:developer';
import 'dart:io'; // Platform 확인
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // SystemChrome
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:auralens/src/services/camera_service.dart';
import 'package:auralens/src/services/composition_service.dart';

class CameraViewModel with ChangeNotifier {
  final CameraService _cameraService;
  final CompositionService _compositionService = CompositionService();

  // ML Kit ObjectDetector 인스턴스
  late final ObjectDetector _objectDetector;

  bool _isDetecting = false;
  List<DetectedObject> _detections = []; // ML Kit의 모델을 직접 사용
  Offset? _compositionTarget;
  bool _isCompositionCorrect = false;
  Size _screenSize = Size.zero;
  Size? _imageSize; // 카메라 이미지 원본 크기

  // UI가 구독할 Getter
  List<DetectedObject> get detections => _detections;
  CameraService get cameraService => _cameraService;
  Offset? get compositionTarget => _compositionTarget;
  bool get isCompositionCorrect => _isCompositionCorrect;
  Size? get imageSize => _imageSize; // Painter의 좌표 스케일링에 필요

  CameraViewModel(this._cameraService) {
    _cameraService.addListener(notifyListeners);

    // 1. ML Kit ObjectDetector 초기화
    // 기본 "Stream" 모드, 'person'만 감지하도록 설정
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);

    // 2. 추론 루프 시작
    _startModelInference();
  }

  void setScreenSize(Size size) {
    if (_screenSize == Size.zero) {
      _screenSize = size;
      log('ViewModel: 화면 크기 설정됨: $_screenSize');
    }
  }

  void _startModelInference() {
    log('CameraViewModel: ML Kit 추론 루프 시작');
    _cameraService.startImageStream((CameraImage cameraImage) async {
      if (_isDetecting || _screenSize == Size.zero) return;

      _isDetecting = true;
      try {
        // ML Kit가 요구하는 InputImage로 변환
        final InputImage? inputImage = _inputImageFromCameraImage(cameraImage);
        if (inputImage == null) return;

        // 이미지 크기 저장 (Painter의 스케일링 계산용)
        _imageSize = inputImage.metadata?.size;

        // 3. ML Kit로 이미지 처리
        final List<DetectedObject> results = await _objectDetector.processImage(
          inputImage,
        );

        // 4. 'person' 레이블 필터링
        final List<DetectedObject> personDetections = results
            .where(
              (obj) => obj.labels.any(
                (label) => label.text.toLowerCase() == 'person',
              ),
            )
            .toList();

        // 5. 구도 계산
        _updateComposition(personDetections);

        // 6. 상태 업데이트
        _detections = personDetections;
      } catch (e) {
        log('ML Kit 추론 실패: $e');
      } finally {
        notifyListeners();
        _isDetecting = false;
      }
    });
  }

  /// ML Kit에 최적화된 구도 계산
  void _updateComposition(List<DetectedObject> personDetections) {
    if (personDetections.isNotEmpty && _imageSize != null) {
      // ML Kit는 이미지 원본 기준 절대 좌표(Rect)를 반환
      final Rect imageBox = personDetections.first.boundingBox;

      // TODO: (중요) Painter에서 스케일링을 하므로 여기서는 상대 좌표로 변환
      // (이 부분은 Painter에서 처리하는 것이 더 정확함)

      // ViewModel은 UI 좌표계로 변환하여 CompositionService에 전달
      final Rect scaledBox = _scaleRect(
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

  /// 사진 촬영
  Future<void> takePicture() async {
    final XFile? photo = await _cameraService.takePicture();
    if (photo != null) {
      try {
        await GallerySaver.saveImage(photo.path);
        log('사진 저장 성공: ${photo.path}');
        // TODO: 사용자에게 "저장 완료" 피드백 (Snackbar 등)
      } catch (e) {
        log('사진 저장 실패: $e');
      }
    }
  }

  @override
  void dispose() {
    log('CameraViewModel 해제');
    _cameraService.stopImageStream();
    _cameraService.removeListener(notifyListeners);
    _objectDetector.close(); // ML Kit 리소스 해제
    super.dispose();
  }

  /// CameraImage를 ML Kit InputImage로 변환 (좌표 변환의 핵심)
  ///
  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _cameraService.controller!.description;
    final sensorOrientation = camera.sensorOrientation; // 90, 180, 270...

    InputImageRotation rotation;
    if (Platform.isIOS) {
      rotation =
          InputImageRotationValue.fromRawValue(sensorOrientation) ??
          InputImageRotation.rotation0deg;
    } else if (Platform.isAndroid) {
      var rotationCompensation = (sensorOrientation + 360) % 360;
      rotation =
          InputImageRotationValue.fromRawValue(rotationCompensation) ??
          InputImageRotation.rotation0deg;
    } else {
      rotation = InputImageRotation.rotation0deg;
    }

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    return InputImage.fromBytes(
      bytes: image.planes[0].bytes, // YUV의 Y평면 (또는 BGRA)
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  /// ML Kit 좌표(이미지 기준)를 UI 좌표(위젯 기준)로 스케일링
  Rect _scaleRect({
    required Rect rect,
    required Size imageSize,
    required Size widgetSize,
  }) {
    // (이 스케일링 로직은 CameraPreview가 '모cover' 드일 때를 가정한 것이며,
    // 'contain' (AspectRatio) 모드에서는 더 복잡한 계산이 필요합니다.)

    final double scaleX = widgetSize.width / imageSize.width;
    final double scaleY = widgetSize.height / imageSize.height;

    // TODO: AspectRatio에 맞춘 정확한 스케일링 필요
    // (우선은 단순 비율로 계산)
    return Rect.fromLTRB(
      rect.left * scaleX,
      rect.top * scaleY,
      rect.right * scaleX,
      rect.bottom * scaleY,
    );
  }

  // [신규] UI 토글 상태 변수
  bool _isGridEnabled = true; // 그리드 (기본값: 켜기)
  bool _isAiAssistEnabled = true; // AI 어시스트 (기본값: 켜기)
  // AiMode _currentMode = AiMode.person; // (추후 풍경 모드 추가 시)

  // [신규] UI가 구독할 Getter
  bool get isGridEnabled => _isGridEnabled;
  bool get isAiAssistEnabled => _isAiAssistEnabled;

  // [신규] UI가 호출할 토글 함수
  void toggleGrid() {
    _isGridEnabled = !_isGridEnabled;
    notifyListeners(); // UI 갱신 알림
  }

  void toggleAiAssist() {
    _isAiAssistEnabled = !_isAiAssistEnabled;
    notifyListeners(); // UI 갱신 알림
  }
}
