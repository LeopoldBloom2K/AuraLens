// lib/src/screens/camera/camera_view_model.dart

import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:auralens/src/services/camera_service.dart';
import 'package:auralens/src/services/tflite_service.dart';
import 'package:auralens/src/utils/image_converter.dart';
import 'package:auralens/src/models/camera_settings.dart'; // 🚀 여기서 SceneCategory를 불러옵니다!

class CameraViewModel with ChangeNotifier {
  final CameraService _cameraService;
  final TFLiteService _tfliteService;

  XFile? _recentPhoto;
  bool _isDetecting = false;

  Offset? _compositionTarget;
  bool _isCompositionCorrect = false;
  Size _screenSize = Size.zero;
  Size? _imageSize;

  SceneCategory _currentScene = SceneCategory.unknown;
  SceneCategory get currentScene => _currentScene;

  final List<SceneCategory> _sceneHistory = [];
  final int _historyLength = 7;

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

  bool _isStreamingModel = false;

  CameraViewModel(this._cameraService, this._tfliteService) {
    _cameraService.addListener(notifyListeners);

    if (_cameraService.isCameraInitialized) {
      _startModelInference();
    } else {
      _cameraService.addListener(_onCameraServiceStateChanged);
    }
  }

  void _onCameraServiceStateChanged() {
    if (_cameraService.isCameraInitialized && !_isDetecting && !_isStreamingModel) {
      _startModelInference();
    }
    notifyListeners();
  }

  void setScreenSize(Size size) {
    if (_screenSize == Size.zero) {
      _screenSize = size;
      log('ViewModel: 화면 크기 설정됨: $_screenSize');
    }
  }

  void _startModelInference() async {
    final bool isCameraReady = _cameraService.controller?.value.isInitialized ?? false;

    if (!isCameraReady) {
      log('카메라 컨트롤러가 초기화되지 않았습니다. 모델 추론을 시작할 수 없습니다.');
      return;
    }

    if (_isStreamingModel) {
      return;
    }

    _isStreamingModel = true;

    _cameraService.startImageStream((CameraImage cameraImage) async {
      if (!_isAiAssistEnabled) {
        _compositionTarget = null;
        _isCompositionCorrect = false;
        _currentScene = SceneCategory.unknown;
        _sceneHistory.clear();
        notifyListeners();
        return;
      }

      if (_isDetecting) return;

      _isDetecting = true;
      try {
        final rawResult = await compute(ImageConverter.convertCameraImageToModelInput, cameraImage)
            .then((inputMatrix) => _tfliteService.classifyScene(inputMatrix));

        _imageSize = Size(cameraImage.width.toDouble(), cameraImage.height.toDouble());

        // 다수결 투표 안정화 로직
        _sceneHistory.add(rawResult);
        if (_sceneHistory.length > _historyLength) {
          _sceneHistory.removeAt(0);
        }

        final Map<SceneCategory, int> voteCount = {};
        for (var scene in _sceneHistory) {
          voteCount[scene] = (voteCount[scene] ?? 0) + 1;
        }

        final stableScene = voteCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;

        if (_currentScene != stableScene) {
          _currentScene = stableScene;
          log('📸 [안정화 완료] 현재 촬영 상황: ${_currentScene.name}');
          notifyListeners();
        }

      } catch (e) {
        log('AI 추론 실패: $e');
      } finally {
        if (hasListeners) {
          notifyListeners();
        }
        _isDetecting = false;
      }
    });
    log('CameraViewModel: TFLite 추론 루프 시작 🚀');
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
    super.dispose();
  }
}