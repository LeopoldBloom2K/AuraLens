// lib/src/screens/camera/camera_view_model.dart

import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' show sqrt;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:auralens/src/services/camera_service.dart';
import 'package:auralens/src/services/inference_service.dart';
import 'package:auralens/src/services/composition_service.dart';
import 'package:auralens/src/utils/image_converter.dart';
import 'package:auralens/src/utils/coordinate_scaler.dart';
import 'package:auralens/src/models/camera_settings.dart';

class CameraViewModel with ChangeNotifier {
  final CameraService _cameraService;
  final InferenceService _inferenceService;

  // ── 기존 상태 ────────────────────────────────────────────────────────────

  XFile? _recentPhoto;
  final List<XFile> _sessionPhotos = [];
  List<XFile> get sessionPhotos => _sessionPhotos;

  bool _isDetecting = false;

  SceneCategory _currentScene = SceneCategory.unknown;

  final List<SceneCategory> _sceneHistory = [];
  final int _historyLength = 7;

  bool _isGridEnabled = true;
  bool _isAiAssistEnabled = true;
  CameraResolution _cameraResolution = CameraResolution.max;
  CameraRatio _currentRatio = CameraRatio.ratio4_3;

  bool _isStreamingModel = false;
  DateTime _lastInferenceTime = DateTime.now();
  final int _inferenceIntervalMs = 500;

  // ── Stage 1~3: ML Kit + CompositionService 상태 ──────────────────────────

  late final ObjectDetector _objectDetector;
  final CompositionService _compositionService = CompositionService();

  Rect?   _detectedBoundingBox;   // 위젯 좌표계 바운딩 박스
  Offset? _compositionTarget;     // 가장 가까운 파워포인트
  bool    _isCompositionCorrect = false;
  Size    _screenSize = Size.zero;
  Size?   _imageSize;

  // ── 수동 포커스 / 자동 포커스 상태 ──────────────────────────────────────────

  bool _isManualFocusActive = false;
  Offset? _focusTapPoint;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  DateTime _lastAutoFocusTime = DateTime.fromMillisecondsSinceEpoch(0);
  Offset? _lastAutoFocusPoint;
  static const double _moveThreshold = 3.5; // m/s² (gravity 제거됨)

  // ── Debug mode ───────────────────────────────────────────────────────────

  bool _isDisposed = false;
  bool _debugMode = false;
  SceneCategory _debugScene = SceneCategory.person;
  bool _debugCompositionCorrect = false;

  bool get debugMode => _debugMode;

  // 디버그용 가짜 바운딩 박스 (화면 중앙 55%×45% 크기)
  Rect get _debugBox {
    if (_screenSize == Size.zero) return const Rect.fromLTWH(80, 200, 220, 300);
    return Rect.fromCenter(
      center: Offset(_screenSize.width / 2, _screenSize.height * 0.43),
      width:  _screenSize.width  * 0.55,
      height: _screenSize.height * 0.42,
    );
  }

  // 디버그용 가짜 구도 목표 (오른쪽 파워포인트)
  Offset get _debugTarget => _screenSize == Size.zero
      ? const Offset(280, 200)
      : Offset(_screenSize.width * 0.67, _screenSize.height * 0.33);

  void toggleDebugMode() {
    _debugMode = !_debugMode;
    notifyListeners();
  }

  void debugCycleScene() {
    const scenes = [SceneCategory.person, SceneCategory.food, SceneCategory.scenery];
    _debugScene = scenes[(scenes.indexOf(_debugScene) + 1) % scenes.length];
    notifyListeners();
  }

  void debugToggleComposition() {
    _debugCompositionCorrect = !_debugCompositionCorrect;
    notifyListeners();
  }

  // ── Getters ──────────────────────────────────────────────────────────────

  CameraService get cameraService  => _cameraService;
  Size?   get imageSize            => _imageSize;
  XFile?  get recentPhoto          => _recentPhoto;
  bool    get isGridEnabled        => _isGridEnabled;
  bool    get isAiAssistEnabled    => _isAiAssistEnabled;
  CameraResolution get cameraResolution => _cameraResolution;
  CameraRatio      get currentRatio     => _currentRatio;

  SceneCategory get currentScene =>
      _debugMode ? _debugScene : _currentScene;

  Rect? get detectedBoundingBox =>
      _debugMode ? _debugBox : _detectedBoundingBox;

  Offset? get compositionTarget =>
      _debugMode ? (_debugCompositionCorrect ? null : _debugTarget) : _compositionTarget;

  bool get isCompositionCorrect =>
      _debugMode ? _debugCompositionCorrect : _isCompositionCorrect;

  bool    get isManualFocusActive => _isManualFocusActive;
  Offset? get focusTapPoint       => _focusTapPoint;

  // ── 생성자 ───────────────────────────────────────────────────────────────

  CameraViewModel(this._cameraService, this._inferenceService) {
    _objectDetector = ObjectDetector(
      options: ObjectDetectorOptions(
        mode: DetectionMode.stream,
        classifyObjects: false,   // 분류는 ONNX가 담당
        multipleObjects: false,   // 주 피사체 1개만 추적
      ),
    );

    _cameraService.addListener(notifyListeners);

    if (_cameraService.isCameraInitialized) {
      _startModelInference();
    } else {
      _cameraService.addListener(_onCameraServiceStateChanged);
    }

    // 카메라 움직임 감지 → 수동 포커스 자동 해제
    _accelSub = userAccelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((UserAccelerometerEvent event) {
      if (!_isManualFocusActive) return;
      final mag = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (mag > _moveThreshold) _resetManualFocus();
    });
  }

  // ── 화면 크기 등록 ───────────────────────────────────────────────────────

  void setScreenSize(Size size) {
    if (_screenSize == Size.zero) {
      _screenSize = size;
      log('ViewModel: 화면 크기 설정됨: $_screenSize');
    }
  }

  // ── 카메라 초기화 대기 ───────────────────────────────────────────────────

  void _onCameraServiceStateChanged() {
    if (_cameraService.isCameraInitialized && !_isDetecting && !_isStreamingModel) {
      _startModelInference();
    }
    notifyListeners();
  }

  // ── Stage 1: ML Kit InputImage 변환 ─────────────────────────────────────

  // CameraX YUV_420_888 → NV21 변환 후 ML Kit 전달
  // (InputImageFormat.yuv420은 iOS 전용; Android는 nv21 필요)
  InputImage? _buildInputImage(CameraImage image) {
    try {
      final int w = image.width;
      final int h = image.height;
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final int yRowStride  = yPlane.bytesPerRow;
      final int uvRowStride = uPlane.bytesPerRow;
      final int uvPixStride = uPlane.bytesPerPixel ?? 2;

      // NV21 = Y(w×h) + VU interleaved(w×h/2)
      final nv21 = Uint8List(w * h + (w * h ~/ 2));

      // Y 평면: 패딩 제거하며 행 단위 복사
      for (int row = 0; row < h; row++) {
        nv21.setRange(row * w, row * w + w, yPlane.bytes, row * yRowStride);
      }

      // VU 인터리브
      int uvDst = w * h;
      for (int row = 0; row < h ~/ 2; row++) {
        for (int col = 0; col < w ~/ 2; col++) {
          final int srcIdx = row * uvRowStride + col * uvPixStride;
          nv21[uvDst++] = vPlane.bytes[srcIdx]; // V 먼저 (NV21)
          nv21[uvDst++] = uPlane.bytes[srcIdx]; // U 다음
        }
      }

      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(w.toDouble(), h.toDouble()),
          rotation: InputImageRotation.rotation90deg,
          format: InputImageFormat.nv21,
          bytesPerRow: w,
        ),
      );
    } catch (e) {
      log('InputImage 변환 실패: $e');
      return null;
    }
  }

  // ── Stage 1~3: ML Kit 감지 + CompositionService 연결 ────────────────────

  Future<void> _runObjectDetection(CameraImage cameraImage) async {
    if (_screenSize == Size.zero) return;

    final inputImage = _buildInputImage(cameraImage);
    if (inputImage == null) return;

    try {
      final objects = await _objectDetector.processImage(inputImage);

      if (objects.isEmpty) {
        _detectedBoundingBox = null;
        if (!_isManualFocusActive) _compositionTarget = null;
        _isCompositionCorrect = false;
        return;
      }

      // 가장 큰 객체 선택
      objects.sort((a, b) =>
          (b.boundingBox.width * b.boundingBox.height)
              .compareTo(a.boundingBox.width * a.boundingBox.height));

      // ML Kit rotation90deg 적용 후 좌표계는 이미지의 가로/세로가 교환됨
      final rotatedSize = Size(
        cameraImage.height.toDouble(),
        cameraImage.width.toDouble(),
      );

      // Stage 2에서 그릴 바운딩 박스를 위젯 좌표로 변환
      _detectedBoundingBox = scaleRect(
        rect: objects.first.boundingBox,
        imageSize: rotatedSize,
        widgetSize: _screenSize,
      );

      // Stage 3: 가장 가까운 파워포인트 찾기 (수동 모드에서는 덮어쓰지 않음)
      if (!_isManualFocusActive) {
        _compositionTarget = _compositionService.findClosestPowerPoint(
          _detectedBoundingBox!,
          _screenSize,
        );
      }

      _isCompositionCorrect = _compositionService.isCompositionCorrect(
        _detectedBoundingBox!,
        _compositionTarget,
        _screenSize,
      );

      // 자동 포커스: 수동 포커스가 비활성 상태일 때만, 2초 간격 또는 피사체가 크게 이동한 경우
      if (!_isManualFocusActive) {
        final subjectCenter = _detectedBoundingBox!.center;
        final now = DateTime.now();
        final movedFar = _lastAutoFocusPoint != null &&
            (_lastAutoFocusPoint! - subjectCenter).distance > _screenSize.width * 0.15;
        if (now.difference(_lastAutoFocusTime).inSeconds >= 2 || movedFar) {
          _lastAutoFocusTime = now;
          _lastAutoFocusPoint = subjectCenter;
          _cameraService.setFocusAndExposure(Offset(
            subjectCenter.dx / _screenSize.width,
            subjectCenter.dy / _screenSize.height,
          ));
        }
      }
    } catch (e) {
      log('ML Kit 감지 실패: $e');
      _detectedBoundingBox = null;
      _compositionTarget = null;
      _isCompositionCorrect = false;
    }
  }

  // ── 메인 추론 루프 ───────────────────────────────────────────────────────

  Future<void> _startModelInference() async {
    final bool isCameraReady =
        _cameraService.controller?.value.isInitialized ?? false;
    if (!isCameraReady) {
      log('카메라 컨트롤러가 초기화되지 않았습니다.');
      return;
    }
    if (_isStreamingModel) return;

    _isStreamingModel = true;

    _cameraService.startImageStream((CameraImage cameraImage) async {
      if (_isDisposed) return;
      if (!_isAiAssistEnabled) {
        _compositionTarget = null;
        _isCompositionCorrect = false;
        _detectedBoundingBox = null;
        _currentScene = SceneCategory.unknown;
        _sceneHistory.clear();
        notifyListeners();
        return;
      }

      if (_isDetecting) return;

      final now = DateTime.now();
      if (now.difference(_lastInferenceTime).inMilliseconds < _inferenceIntervalMs) {
        return;
      }

      _lastInferenceTime = now;
      _isDetecting = true;

      try {
        // ONNX 장면 분류
        final rawResult = await compute(
          ImageConverter.convertCameraImageToModelInput,
          cameraImage,
        ).then((input) => _inferenceService.classifyScene(input));

        _imageSize = Size(
          cameraImage.width.toDouble(),
          cameraImage.height.toDouble(),
        );

        // 7프레임 다수결 안정화
        _sceneHistory.add(rawResult);
        if (_sceneHistory.length > _historyLength) {
          _sceneHistory.removeAt(0);
        }

        final Map<SceneCategory, int> voteCount = {};
        for (final scene in _sceneHistory) {
          voteCount[scene] = (voteCount[scene] ?? 0) + 1;
        }
        final stableScene = voteCount.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key;

        if (_currentScene != stableScene) {
          _currentScene = stableScene;
          log('📸 [안정화 완료] 현재 촬영 상황: ${_currentScene.name}');
        }

        // Stage 1~3: person·food 에서만 ML Kit 객체 감지 실행
        // scenery는 피사체가 화면 전체이므로 바운딩 박스 불필요
        if (stableScene == SceneCategory.person ||
            stableScene == SceneCategory.food) {
          await _runObjectDetection(cameraImage);
        } else {
          _detectedBoundingBox = null;
          _compositionTarget = null;
          _isCompositionCorrect = false;
        }
      } catch (e) {
        log('AI 추론 실패: $e');
      } finally {
        _isDetecting = false;
        if (!_isDisposed && hasListeners) notifyListeners();
      }
    });

    log('CameraViewModel: ONNX + ML Kit 추론 루프 시작 (쿨다운 0.5초)');
  }

  // ── 수동 포커스 / 구도 업데이트 ──────────────────────────────────────────

  void onScreenTap(Offset localPosition, Size widgetSize) {
    _isManualFocusActive = true;
    _focusTapPoint = localPosition;

    // 탭한 위치 기준으로 가장 가까운 파워포인트를 구도 목표로 설정
    final tapRect = Rect.fromCenter(center: localPosition, width: 1, height: 1);
    _compositionTarget = _compositionService.findClosestPowerPoint(tapRect, widgetSize);

    // 정규화 좌표(0~1)로 카메라 포커스/노출 설정
    _cameraService.setFocusAndExposure(Offset(
      localPosition.dx / widgetSize.width,
      localPosition.dy / widgetSize.height,
    ));

    notifyListeners();
  }

  void _resetManualFocus() {
    if (!_isManualFocusActive) return;
    _isManualFocusActive = false;
    _focusTapPoint = null;
    _lastAutoFocusTime = DateTime.fromMillisecondsSinceEpoch(0);
    _lastAutoFocusPoint = null;
    _cameraService.resetAutoFocusExposure();
    if (!_isDisposed && hasListeners) notifyListeners();
  }

  // ── 나머지 기존 기능들 ───────────────────────────────────────────────────

  void toggleRatio() {
    switch (_currentRatio) {
      case CameraRatio.ratio4_3:
        _currentRatio = CameraRatio.ratio16_9;
        break;
      case CameraRatio.ratio16_9:
        _currentRatio = CameraRatio.ratio1_1;
        break;
      case CameraRatio.ratio1_1:
        _currentRatio = CameraRatio.ratio4_3;
        break;
    }
    notifyListeners();
  }

  Future<void> takePicture() async {
    final XFile? photo = await _cameraService.takePicture();
    if (photo == null) return;
    _recentPhoto = photo;
    _sessionPhotos.insert(0, photo);
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
    _isStreamingModel = false;
    _isDetecting = false;
    _isManualFocusActive = false;
    _focusTapPoint = null;
    _sceneHistory.clear();
    _detectedBoundingBox = null;
    _compositionTarget = null;
    _isCompositionCorrect = false;
    await _cameraService.switchCamera();
    _startModelInference();
  }

  Future<void> pauseInference() async {
    log('CameraViewModel: 갤러리 진입 - AI 연산 일시 정지');
    await _cameraService.stopImageStream();
    _isStreamingModel = false;
    _isDetecting = false;
  }

  Future<void> resumeInference() async {
    log('CameraViewModel: 카메라 복귀 - AI 연산 재개');
    if (!_isStreamingModel && _cameraService.isCameraInitialized) {
      await _startModelInference();
    }
  }

  void deleteSessionPhoto(XFile photo) {
    _sessionPhotos.remove(photo);
    if (_recentPhoto?.path == photo.path) {
      _recentPhoto = _sessionPhotos.isNotEmpty ? _sessionPhotos.first : null;
    }
    notifyListeners();
    try {
      File(photo.path).deleteSync();
      log('사진 삭제 완료: ${photo.path}');
    } catch (e) {
      log('사진 삭제 실패: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    log('CameraViewModel 해제');
    _accelSub?.cancel();
    _objectDetector.close();
    _cameraService.stopImageStream();
    _isStreamingModel = false;
    _cameraService.removeListener(notifyListeners);
    _cameraService.removeListener(_onCameraServiceStateChanged);
    super.dispose();
  }
}
