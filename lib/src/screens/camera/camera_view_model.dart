// lib/src/screens/camera/camera_view_model.dart  tflitemodel -> google ML kit으로 변경

import 'dart:developer';
import 'dart:io'; // Platform 확인
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // SystemChrome
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:auralens/src/services/camera_service.dart';
import 'package:auralens/src/services/composition_service.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:auralens/src/models/camera_settings.dart';
import 'package:auralens/src/utils/coordinate_scaler.dart';

class CameraViewModel with ChangeNotifier {
  final CameraService _cameraService;
  final CompositionService _compositionService = CompositionService();

  // ML Kit ObjectDetector 인스턴스
  late final ObjectDetector _objectDetector;

  // 최근 저장된 사진 썸네일 상태 변수 
  XFile? _recentPhoto;


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
  XFile? get recentPhoto => _recentPhoto; // 썸네일

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

  Future<List<DetectedObject>> _runModelOnIsolate(InputImage inputImage) async {
  // Isolate에서는 ViewModel의 _objectDetector에 접근할 수 없으므로,
  // 여기서 새로 생성하거나, Isolate 생성 시 전달해야 합니다.
  // (간단한 예시를 위해 매번 생성)
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

  void _startModelInference() async {
    log('CameraViewModel: ML Kit 추론 루프 시작');
    _cameraService.startImageStream((CameraImage cameraImage) async {
      if (_cameraService.controller == null || !_cameraService.controller!.value.isInitialized) {
        log('카메라 컨트롤러가 초기화되지 않았습니다. 모델 추론을 시작할 수 없습니다.');
        return;
      }
      
      _isDetecting = true;
      try {
        // ML Kit가 요구하는 InputImage로 변환
        final InputImage? inputImage = _inputImageFromCameraImage(cameraImage);
        if (inputImage == null) {
          _isDetecting = false;
          return;
        }
        final List<DetectedObject> results = await compute(_runModelOnIsolate, inputImage);
          // 이미지 크기 저장 (Painter의 스케일링 계산용)
          _imageSize = inputImage.metadata?.size;

          // // 4. 'person' 레이블 필터링
          // final List<DetectedObject> personDetections = results
          //     .where(
          //       (obj) =>
          //       obj.labels.any(
          //             (label) => label.text.toLowerCase() == 'person',
          //       ),
          // )
          //     .toList();

          // 모든 감지된 객체를 저장함
          _detections = results;

          // TODO: 여기에서 '주요 객체' (예: 음식, 사람)를 선별하고,
          // 이 객체들을 이용해 구도 분석을 수행하는 함수를 호출합니다.
          // List<DetectedObject> mainObjects = _filterMainObjects(_detections);
          // _updateComposition(mainObjects); // 이제 mainObjects를 기반으로 구도 업데이트

          // 6. 상태 업데이트
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
  }

  /// ML Kit에 최적화된 구도 계산
  void _updateComposition(List<DetectedObject> personDetections) {
    if (personDetections.isNotEmpty && _imageSize != null) {
      // ML Kit는 이미지 원본 기준 절대 좌표(Rect)를 반환
      final Rect imageBox = personDetections.first.boundingBox;

      // TODO: (중요) Painter에서 스케일링을 하므로 여기서는 상대 좌표로 변환
      // (이 부분은 Painter에서 처리하는 것이 더 정확함)

      // ViewModel은 UI 좌표계로 변환하여 CompositionService에 전달
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

  /// 사진 촬영
  Future<void> takePicture() async {
    final XFile? photo = await _cameraService.takePicture();
    if (photo == null) return;
    // 촬영한 사진 상태 변수에 저장 후 UI에 알림
    _recentPhoto = photo;
    notifyListeners(); // UI (썸네일) 갱신

    try {
      await GallerySaver.saveImage(photo.path);
      log('사진 저장 성공: ${photo.path}');
      // TODO: 사용자에게 "저장 완료" 피드백 (Snackbar 등)
    } catch (e) {
      log('사진 저장 실패: $e');
    }
  }

  /// CameraImage를 ML Kit InputImage로 변환 (좌표 변환의 핵심)
  ///
  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _cameraService.controller!.description;
    final sensorOrientation = camera.sensorOrientation; // 90, 180, 270...
    final writeBuffer = WriteBuffer();
    for (final Plane plane in image.planes) {
      writeBuffer.putUint8List(plane.bytes);
    }
    final bytes = writeBuffer
        .done()
        .buffer 
        .asUint8List();

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
  Rect scaleRect({
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
  CameraResolution _cameraResolution = CameraResolution.medium; // 기본값

  // [신규] UI가 구독할 Getter
  bool get isGridEnabled => _isGridEnabled;
  bool get isAiAssistEnabled => _isAiAssistEnabled;
  CameraResolution get cameraResolution => _cameraResolution;

  // [신규] UI가 호출할 토글 함수
  void toggleGrid(bool value) {
    _isGridEnabled = value;
    notifyListeners();
    // TODO: 만약 그리드 활성화/비활성화 시 CameraService에 알려야 한다면 여기서 호출
  }

  void toggleAiAssist(bool value) {
    _isAiAssistEnabled = value;
    notifyListeners(); // UI 갱신 알림
    // TODO: AI 어시스트 활성화/비활성화 시 추론 루프를 시작/정지해야 한다면 여기서 호출
    // 현재는 _startModelInference()가 isAiAssistEnabled를 사용하고 있으므로,
    // 이 값을 변경하면 자연스럽게 동작합니다.
  }

  @override
  void dispose() {
    log('CameraViewModel 해제');
    _cameraService.stopImageStream();
    _cameraService.controller?.removeListener(notifyListeners);
    _objectDetector.close(); // ML Kit 리소스 해제
    super.dispose();
  }

  Future<void> setCameraResolution(CameraResolution resolution) async {
    if (_cameraResolution == resolution) return;
    _cameraResolution = resolution;
    notifyListeners();

    // TODO: 카메라 해상도 변경 로직 (매우 중요!)
    // 카메라 컨트롤러를 dispose 하고 새로운 해상도로 다시 initialize 해야 합니다.
    // 이는 카메라 미리보기 스트림에 영향을 미치므로, 사용자에게 잠시 카메라가 멈출 수 있음을 알리거나
    // 전환 중 로딩 스피너를 보여주는 것이 좋습니다.
    // 예: await _cameraService.updateCameraResolution(resolution);
    log('카메라 해상도 변경: ${resolution.name}');
  }
}
