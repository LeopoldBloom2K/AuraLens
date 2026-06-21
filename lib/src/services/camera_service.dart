// lib/src/services/camera_service.dart

import 'dart:developer';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // 🚀 DeviceOrientation 사용을 위해 추가!
import 'package:auralens/src/models/camera_settings.dart'; 

class CameraService with ChangeNotifier {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  
  bool _isStreamingImages = false;
  int _selectedCameraIdx = 0;

  CameraResolution _currentResolution = CameraResolution.max;

  CameraController? get controller => _controller;
  bool get isCameraInitialized => _isCameraInitialized;
  int get selectedCameraIndex => _selectedCameraIdx;
  int get cameraCount => _cameras.length;

  CameraService();

  ResolutionPreset _getResolutionPreset(CameraResolution resolution) {
    switch (resolution) {
      case CameraResolution.low: return ResolutionPreset.low;
      case CameraResolution.medium: return ResolutionPreset.medium;
      case CameraResolution.high: return ResolutionPreset.high;
      case CameraResolution.max: return ResolutionPreset.max; 
    }
  }

  Future<void> initializeCamera({int cameraIdx = 0}) async {
    if (_isCameraInitialized && _selectedCameraIdx == cameraIdx) return;

    try {
      if (_controller != null) {
        await _controller!.dispose();
        _controller = null;
      }

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        log('사용 가능한 카메라가 없습니다.');
        return;
      }
      
      if (cameraIdx < 0 || cameraIdx >= _cameras.length) {
        cameraIdx = 0; 
      }
      _selectedCameraIdx = cameraIdx;

      ResolutionPreset preset = _getResolutionPreset(_currentResolution);

      _controller = CameraController(
        _cameras[_selectedCameraIdx], 
        preset, 
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420, 
      );

      await _controller!.initialize();
      
      // 카메라 방향 고정 (세로 모드) 
      await _controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);

      _isCameraInitialized = true;
      _controller!.addListener(_onControllerValueChanged);

    } on CameraException catch (e) {
      log('카메라 초기화 실패: $e');
      _isCameraInitialized = false;
    } finally {
      notifyListeners(); 
    }
  }

  Future<void> switchCamera() async {
    if (_cameras.length < 2) {
      log('카메라가 1개뿐이라 전환 불가.');
      return;
    }

    if (_isStreamingImages) await stopImageStream();

    _isCameraInitialized = false;
    if (_controller != null) {
      _controller!.removeListener(_onControllerValueChanged);
      await _controller!.dispose();
      _controller = null;
    }
    notifyListeners(); // 전환 중 로딩 상태를 UI에 즉시 반영

    _selectedCameraIdx = (_selectedCameraIdx + 1) % _cameras.length;
    log('카메라 전환: 총 ${_cameras.length}개, 인덱스 → $_selectedCameraIdx (${_cameras[_selectedCameraIdx].lensDirection.name})');
    await initializeCamera(cameraIdx: _selectedCameraIdx);
  }

  void _onControllerValueChanged() {
    notifyListeners(); 
  }

  Future<void> startImageStream(void Function(CameraImage image) onAvailable) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isStreamingImages) return;

    try {
      await _controller!.startImageStream(onAvailable);
      _isStreamingImages = true;
    } catch (e) {
      log('이미지 스트림 시작 실패: $e');
    }
  }

  Future<void> stopImageStream() async {
    if (_controller == null || !_isStreamingImages) return;

    try {
      await _controller!.stopImageStream();
      _isStreamingImages = false;
    } catch (e) {
      log('이미지 스트림 정지 실패: $e');
    }
  }

  Future<XFile?> takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return null;
    if (_controller!.value.isTakingPicture) return null;

    try {
      final XFile file = await _controller!.takePicture();
      return file;
    } catch (e) {
      log('사진 촬영 실패: $e');
      return null;
    }
  }

  Future<void> setFocusAndExposure(Offset normalizedPoint) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      if (_controller!.value.focusPointSupported) {
        await _controller!.setFocusMode(FocusMode.locked);
        await _controller!.setFocusPoint(normalizedPoint);
      }
      if (_controller!.value.exposurePointSupported) {
        await _controller!.setExposureMode(ExposureMode.locked);
        await _controller!.setExposurePoint(normalizedPoint);
      }
    } catch (e) {
      log('포커스/노출 설정 실패: $e');
    }
  }

  Future<void> resetAutoFocusExposure() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      await _controller!.setFocusMode(FocusMode.auto);
      await _controller!.setFocusPoint(null);
      await _controller!.setExposureMode(ExposureMode.auto);
      await _controller!.setExposurePoint(null);
    } catch (e) {
      log('포커스/노출 리셋 실패: $e');
    }
  }

  Future<void> updateCameraResolution(CameraResolution newResolution) async {
    if (_controller == null) return;
    if (_currentResolution == newResolution) return; 

    _currentResolution = newResolution;
    bool wasStreaming = _isStreamingImages;
    if (wasStreaming) await stopImageStream();

    _isCameraInitialized = false;
    if (_controller != null) {
      _controller!.removeListener(_onControllerValueChanged);
      await _controller!.dispose();
      _controller = null;
    }

    await initializeCamera(cameraIdx: _selectedCameraIdx);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerValueChanged); 
    _controller?.dispose();
    super.dispose();
  }
}