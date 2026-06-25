// lib/src/screens/camera/camera_view_model.dart

import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' show sqrt;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:auralens/src/services/camera_service.dart';
import 'package:auralens/src/services/inference_service.dart';
import 'package:auralens/src/services/aesthetic_service.dart';
import 'package:auralens/src/services/composition_service.dart';
import 'package:auralens/src/services/color_harmony_service.dart';
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
  final int _inferenceIntervalMs = 750;

  // ── Stage 1~3: ML Kit + CompositionService 상태 ──────────────────────────

  late final ObjectDetector _objectDetector;
  late final FaceDetector _faceDetector;
  final CompositionService _compositionService = CompositionService();

  // 코 랜드마크 위치 (person 씬 구도 기준점)
  Offset? _nosePoint;

  Rect?              _detectedBoundingBox;
  CompositionResult? _bestComposition;  // evaluateAll() 최고점 결과
  Size               _screenSize = Size.zero;
  Size?              _imageSize;

  // 구도 일치 판정 임계값 (Gaussian score ≥ 0.72 → 화면 너비 약 10% 이내)
  static const double _goodThreshold = 0.72;

  // ── 색상 조화 분석 상태 ────────────────────────────────────────────────────
  ColorHarmonyResult? _colorHarmony;
  DateTime _lastHarmonyTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _harmonyIntervalMs = 5000;

  // ── 미학 품질 점수 상태 ────────────────────────────────────────────────────
  final AestheticService _aestheticService = AestheticService();
  double? _aestheticScore;
  DateTime _lastAestheticTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _aestheticIntervalMs = 8000;

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
      _debugMode ? (_debugCompositionCorrect ? null : _debugTarget)
                 : _bestComposition?.targetPoint;

  bool get isCompositionCorrect =>
      _debugMode ? _debugCompositionCorrect
                 : (_bestComposition?.score ?? 0.0) >= _goodThreshold;

  CompositionType? get bestCompositionType =>
      _debugMode ? CompositionType.ruleOfThirds : _bestComposition?.type;

  double get compositionScore =>
      _debugMode ? (_debugCompositionCorrect ? 0.9 : 0.3)
                 : (_bestComposition?.score ?? 0.0);

  bool    get isManualFocusActive => _isManualFocusActive;
  Offset? get focusTapPoint       => _focusTapPoint;

  ColorHarmonyResult? get colorHarmony => _debugMode ? null : _colorHarmony;

  double? get aestheticScore => _debugMode ? null : _aestheticScore;

  Offset? get nosePoint => _debugMode ? null : _nosePoint;

  // ── 생성자 ───────────────────────────────────────────────────────────────

  CameraViewModel(this._cameraService, this._inferenceService) {
    _aestheticService.initialize();

    _objectDetector = ObjectDetector(
      options: ObjectDetectorOptions(
        mode: DetectionMode.single,
        classifyObjects: false,
        multipleObjects: false,
      ),
    );

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: true,   // 코 랜드마크 활성화
        enableClassification: false,
        enableTracking: false,
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

      // camera_android_camerax는 전·후면 모두 90° 기준으로 프레임을 전달함.
      // 센서 방향(270°)을 그대로 쓰면 전면 감지 실패 → 항상 90° 사용.
      final rotation = InputImageRotation.rotation90deg;

      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(w.toDouble(), h.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: w,
        ),
      );
    } catch (e) {
      log('InputImage 변환 실패: $e');
      return null;
    }
  }

  // ── Stage 1~3: person 씬 — FaceDetector로 얼굴+코 추적 ──────────────────

  Future<void> _runFaceDetection(CameraImage cameraImage) async {
    if (_screenSize == Size.zero) return;

    final inputImage = _buildInputImage(cameraImage);
    if (inputImage == null) return;

    // camera_android_camerax 는 항상 90° 기준 → width/height 항상 스왑
    final rotatedSize = Size(cameraImage.height.toDouble(), cameraImage.width.toDouble());
    final isFront = _cameraService.controller?.description.lensDirection
        == CameraLensDirection.front;

    try {
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        _detectedBoundingBox = null;
        _nosePoint = null;
        if (!_isManualFocusActive) _bestComposition = null;
        return;
      }

      // 가장 큰 얼굴 선택
      faces.sort((a, b) =>
          (b.boundingBox.width * b.boundingBox.height)
              .compareTo(a.boundingBox.width * a.boundingBox.height));

      final face = faces.first;

      var bbox = scaleRect(
        rect: face.boundingBox,
        imageSize: rotatedSize,
        widgetSize: _screenSize,
      );

      // 코 랜드마크 → 위젯 좌표로 변환
      final noseLM = face.landmarks[FaceLandmarkType.noseBase];
      Offset? nose;
      if (noseLM != null) {
        final noseRaw = Offset(noseLM.position.x.toDouble(), noseLM.position.y.toDouble());
        nose = scaleOffset(offset: noseRaw, imageSize: rotatedSize, widgetSize: _screenSize);
      }

      // 전면 카메라: X축 좌우 반전 (프리뷰가 미러링되어 있으므로 좌표도 맞춰야 함)
      if (isFront) {
        final W = _screenSize.width;
        bbox = Rect.fromLTRB(W - bbox.right, bbox.top, W - bbox.left, bbox.bottom);
        if (nose != null) nose = Offset(W - nose.dx, nose.dy);
      }

      _detectedBoundingBox = bbox;
      _nosePoint = nose ?? bbox.center;

      // 코 위치를 구도 기준점으로 평가
      if (!_isManualFocusActive && _nosePoint != null) {
        final noseRect = Rect.fromCenter(center: _nosePoint!, width: 1, height: 1);
        final results = _compositionService.evaluateAll(noseRect, _screenSize, scene: SceneCategory.person);
        _bestComposition = results.isNotEmpty ? results.first : null;
      }

      // 색상 조화 분석
      final nowH = DateTime.now();
      if (nowH.difference(_lastHarmonyTime).inMilliseconds >= _harmonyIntervalMs) {
        _lastHarmonyTime = nowH;
        _analyzeColorHarmony(cameraImage, _detectedBoundingBox!, _screenSize);
      }

      if (!_isManualFocusActive && _nosePoint != null) {
        _tryAutoFocus(_nosePoint!);
      }
    } catch (e) {
      log('Face 감지 실패: $e');
      _detectedBoundingBox = null;
      _nosePoint = null;
      _bestComposition = null;
    }
  }

  // ── Stage 1~3: food 씬 — ObjectDetector로 음식 감지 ──────────────────────

  Future<void> _runObjectDetection(CameraImage cameraImage) async {
    if (_screenSize == Size.zero) return;

    final inputImage = _buildInputImage(cameraImage);
    if (inputImage == null) return;

    final rotatedSize = Size(
      cameraImage.height.toDouble(),
      cameraImage.width.toDouble(),
    );

    try {
      final objects = await _objectDetector.processImage(inputImage);

      if (objects.isEmpty) {
        _detectedBoundingBox = null;
        if (!_isManualFocusActive) _bestComposition = null;
        return;
      }

      objects.sort((a, b) =>
          (b.boundingBox.width * b.boundingBox.height)
              .compareTo(a.boundingBox.width * a.boundingBox.height));

      _detectedBoundingBox = scaleRect(
        rect: objects.first.boundingBox,
        imageSize: rotatedSize,
        widgetSize: _screenSize,
      );

      if (!_isManualFocusActive) {
        final results = _compositionService.evaluateAll(
          _detectedBoundingBox!, _screenSize,
          scene: _currentScene,
        );
        _bestComposition = results.isNotEmpty ? results.first : null;
      }

      final nowH = DateTime.now();
      if (nowH.difference(_lastHarmonyTime).inMilliseconds >= _harmonyIntervalMs) {
        _lastHarmonyTime = nowH;
        _analyzeColorHarmony(cameraImage, _detectedBoundingBox!, _screenSize);
      }

      if (!_isManualFocusActive) {
        _tryAutoFocus(_detectedBoundingBox!.center);
      }
    } catch (e) {
      log('ML Kit 감지 실패: $e');
      _detectedBoundingBox = null;
      _bestComposition = null;
    }
  }

  // ── 미학 품질 점수 (fire-and-forget) ────────────────────────────────────

  void _scoreAesthetics(Float32List input) {
    _aestheticService.score(input).then((score) {
      if (!_isDisposed && score != null) {
        _aestheticScore = score;
        if (hasListeners) notifyListeners();
      }
    });
  }

  // ── 색상 조화 분석 (isolate) ─────────────────────────────────────────────

  void _analyzeColorHarmony(CameraImage img, Rect box, Size scr) {
    // CameraImage.planes[n].bytes는 native buffer 뷰일 수 있으므로
    // Dart 힙에 복사한 뒤 isolate로 전달해 SendPort 실패 및 use-after-free 방지
    final yP = img.planes[0];
    final uP = img.planes[1];
    final vP = img.planes[2];

    compute(
      ColorHarmonyService.analyze,
      ColorHarmonyInput(
        camW: img.width,
        camH: img.height,
        yBytes: Uint8List.fromList(yP.bytes),
        uBytes: Uint8List.fromList(uP.bytes),
        vBytes: Uint8List.fromList(vP.bytes),
        yRowStride:  yP.bytesPerRow,
        uvRowStride: uP.bytesPerRow,
        uvPixStride: uP.bytesPerPixel ?? 2,
        boxL: box.left,  boxT: box.top,
        boxR: box.right, boxB: box.bottom,
        scrW: scr.width, scrH: scr.height,
      ),
    ).then((result) {
      if (!_isDisposed && result != null) {
        _colorHarmony = result;
        if (hasListeners) notifyListeners();
      }
    });
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
        _bestComposition = null;
        _detectedBoundingBox = null;
        _colorHarmony = null;
        _aestheticScore = null;
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
        // ONNX 장면 분류 — modelInput을 미학 추론에도 재사용
        final modelInput = await compute(
          ImageConverter.convertCameraImageToModelInput,
          cameraImage,
        );
        final rawResult = await _inferenceService.classifyScene(modelInput);

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

        // Stage 1~3: person → FaceDetector(코 추적), food → ObjectDetector
        // scenery는 피사체가 화면 전체이므로 바운딩 박스 불필요
        if (stableScene == SceneCategory.person) {
          await _runFaceDetection(cameraImage);
        } else if (stableScene == SceneCategory.food) {
          _nosePoint = null;
          await _runObjectDetection(cameraImage);
        } else {
          // scenery: ML Kit 미사용, 화면 중앙 기준으로 구도 평가
          _detectedBoundingBox = null;
          if (!_isManualFocusActive && _screenSize != Size.zero) {
            final center = Rect.fromCenter(
              center: Offset(_screenSize.width / 2, _screenSize.height / 2),
              width: 1, height: 1,
            );
            final results = _compositionService.evaluateAll(center, _screenSize, scene: stableScene);
            _bestComposition = results.isNotEmpty ? results.first : null;
            _colorHarmony = null;
          }
        }

        // 미학 품질 평가 — person 씬에서만, 3초 쿨다운
        if (stableScene == SceneCategory.person) {
          final nowA = DateTime.now();
          if (nowA.difference(_lastAestheticTime).inMilliseconds >=
              _aestheticIntervalMs) {
            _lastAestheticTime = nowA;
            _scoreAesthetics(modelInput);
          }
        } else {
          _aestheticScore = null;
        }
      } catch (e) {
        log('AI 추론 실패: $e');
      } finally {
        _isDetecting = false;
        if (!_isDisposed && hasListeners) notifyListeners();
      }
    });

    log('CameraViewModel: ONNX + ML Kit 추론 루프 시작 (쿨다운 0.75초)');
  }

  // ── 수동 포커스 / 구도 업데이트 ──────────────────────────────────────────

  void onScreenTap(Offset localPosition, Size widgetSize) {
    _isManualFocusActive = true;
    _focusTapPoint = localPosition;

    // 탭 위치 근처(화면 너비 15% 이내)에 ML Kit 감지 박스가 있으면 그 박스를,
    // 없으면 탭 포인트 자체를 피사체로 삼아 구도 평가
    final Rect subjectBox;
    if (_detectedBoundingBox != null &&
        _detectedBoundingBox!.inflate(widgetSize.width * 0.15).contains(localPosition)) {
      subjectBox = _detectedBoundingBox!;
    } else {
      subjectBox = Rect.fromCenter(center: localPosition, width: 1, height: 1);
    }

    final tapResults = _compositionService.evaluateAll(subjectBox, widgetSize, scene: _currentScene);
    _bestComposition = tapResults.isNotEmpty ? tapResults.first : null;

    // 정규화 좌표(0~1)로 카메라 포커스/노출 설정
    _cameraService.setFocusAndExposure(Offset(
      localPosition.dx / widgetSize.width,
      localPosition.dy / widgetSize.height,
    ));

    notifyListeners();
  }

  // 2초 경과 또는 피사체가 화면 너비 15% 이상 이동 시 AF/AE 재설정
  void _tryAutoFocus(Offset subjectCenter) {
    final now      = DateTime.now();
    final movedFar = _lastAutoFocusPoint != null &&
        (_lastAutoFocusPoint! - subjectCenter).distance > _screenSize.width * 0.15;
    if (now.difference(_lastAutoFocusTime).inSeconds < 2 && !movedFar) return;
    _lastAutoFocusTime  = now;
    _lastAutoFocusPoint = subjectCenter;
    _cameraService.setFocusAndExposure(Offset(
      subjectCenter.dx / _screenSize.width,
      subjectCenter.dy / _screenSize.height,
    ));
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
    // 스트림을 재초기화하기 전에 플래그를 리셋해야 _onCameraServiceStateChanged에서
    // 카메라 재초기화 완료 후 _startModelInference()를 호출할 수 있음.
    // 이 플래그가 true인 채로 updateCameraResolution이 실행되면
    // 스트림은 중단됐지만 _onCameraServiceStateChanged가 재시작을 건너뛰는 버그 발생.
    _isStreamingModel = false;
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
    _bestComposition = null;
    _colorHarmony = null;
    _aestheticScore = null;
    _nosePoint = null;
    // 새 카메라 AE 수렴 전에 포커스/노출이 잠기는 것을 막기 위해
    // _lastAutoFocusTime을 현재 시각으로 리셋 → 전환 후 2초간 _tryAutoFocus 억제
    _lastAutoFocusTime  = DateTime.now();
    _lastAutoFocusPoint = null;
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
    _faceDetector.close();
    _aestheticService.dispose();
    _cameraService.stopImageStream();
    _isStreamingModel = false;
    _cameraService.removeListener(notifyListeners);
    _cameraService.removeListener(_onCameraServiceStateChanged);
    super.dispose();
  }
}
