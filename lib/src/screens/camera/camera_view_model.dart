// lib/src/screens/camera/camera_view_model.dart

import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:auralens/src/services/camera_service.dart';
import 'package:auralens/src/services/inference_service.dart';
import 'package:auralens/src/utils/image_converter.dart';
import 'package:auralens/src/models/camera_settings.dart'; 

class CameraViewModel with ChangeNotifier {
  final CameraService _cameraService;
  final InferenceService _inferenceService;

  XFile? _recentPhoto;

  // 촬영한 모든 사진을 저장하는 List 
  final List<XFile> _sessionPhotos = [];
  List<XFile> get sessionPhotos => _sessionPhotos;

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
  CameraResolution _cameraResolution = CameraResolution.max;

  // 현재 화면 비율 상태 변수 (기본 4:3)
  CameraRatio _currentRatio = CameraRatio.ratio4_3;
  CameraRatio get currentRatio => _currentRatio;

  // 🚀 비율 토글 함수
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


  bool get isGridEnabled => _isGridEnabled;
  bool get isAiAssistEnabled => _isAiAssistEnabled;
  CameraResolution get cameraResolution => _cameraResolution;

  bool _isStreamingModel = false;

  // 🚀 무거운 ResNet 모델과 테스트 기기의 성능을 고려해 추론 간격을 500ms(0.5초)로 수정
  DateTime _lastInferenceTime = DateTime.now();
  final int _inferenceIntervalMs = 500; 

  CameraViewModel(this._cameraService, this._inferenceService) {
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

  Future<void> _startModelInference() async {
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

      final now = DateTime.now();
      
      // 500ms 간격 체크, 너무 빠르면 프레임 드랍(스킵) 처리
      if (now.difference(_lastInferenceTime).inMilliseconds < _inferenceIntervalMs) {   
        return;
      }
      
      // 🚀 추론 시작 시점 기록
      _lastInferenceTime = now;
      _isDetecting = true;

      try {
        final rawResult = await compute(ImageConverter.convertCameraImageToModelInput, cameraImage)
            .then((inputMatrix) => _inferenceService.classifyScene(inputMatrix));

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
    log('CameraViewModel: ONNX 추론 루프 시작 (쿨다운 0.5초) 🚀');
  }

  Future<void> takePicture() async {
    final XFile? photo = await _cameraService.takePicture();
    if (photo == null) return;
    _recentPhoto = photo;
    // List에 새로 촬영한 사진 추가 (최신 사진이 앞에 오도록)
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
    _sceneHistory.clear();

    await _cameraService.switchCamera();

    // 전환 후 카메라가 초기화되면 추론 루프를 재시작합니다.
    _startModelInference();
  }

  // 갤러리 진입 시: AI 프레임 공급 일시 정지
  Future<void> pauseInference() async {
    log('CameraViewModel: 갤러리 진입 - AI 연산 일시 정지');
    await _cameraService.stopImageStream();
    _isStreamingModel = false;
    _isDetecting = false;
  }

  // 갤러리에서 돌아왔을 때: AI 프레임 공급 재개
  Future<void> resumeInference() async {
    log('CameraViewModel: 카메라 복귀 - AI 연산 재개');
    if (!_isStreamingModel && _cameraService.isCameraInitialized) {
      await _startModelInference();
    }
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

  void deleteSessionPhoto(XFile photo) {
    _sessionPhotos.remove(photo); // 리스트에서 제거

    // 만약 지운 사진이 썸네일에 떠 있는 '가장 최근 사진'이라면, 그 이전 사진으로 썸네일 교체
    if (_recentPhoto?.path == photo.path) {
      _recentPhoto = _sessionPhotos.isNotEmpty ? _sessionPhotos.first : null;
    }
    
    notifyListeners(); // UI 즉시 새로고침!

    try {
      File(photo.path).deleteSync(); // 스마트폰 용량 확보를 위해 임시 파일 물리적 삭제
      log('사진 삭제 완료: ${photo.path}');
    } catch (e) {
      log('사진 삭제 실패: $e');
    }
  }


}