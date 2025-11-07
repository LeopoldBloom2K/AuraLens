// CameraService to handle camera initialization and streaming
// lib/src/services/camera_service.dart

import 'dart:developer';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// CameraController 초기화 및 스트림 관리를 담당하는 서비스
class CameraService with ChangeNotifier {
  CameraController? _controller;
  CameraController? get controller => _controller;

  CameraImage? _cameraImage;
  CameraImage? get cameraImage => _cameraImage;

  bool _isCameraInitialized = false;
  bool get isCameraInitialized => _isCameraInitialized;

  bool _isStreaming = false;

  /// 카메라를 초기화합니다.
  Future<void> initializeCamera() async {
    if (_isCameraInitialized) return;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        log('사용 가능한 카메라가 없습니다.');
        return;
      }

      final camera = cameras.first; // 첫 번째 카메라(보통 후면) 사용

      _controller = CameraController(
        camera, // 후면 카메라
        ResolutionPreset.high, // 고해상도 (모델 성능에 따라 조절)
        enableAudio: false,     // 오디오 비활성화
        imageFormatGroup: ImageFormatGroup.yuv420, // iOS/Android 호환 형식
      );

      await _controller!.initialize();
      _isCameraInitialized = true;
      // 물리적 회전 방향 감지
      _controller.enableOrientationListener();
      // 컨트롤러 값 변경시마다 UI에 알림
      _controller.addListener(notifyListeners);

      notifyListeners(); // 성공시에만 호출함

    } catch (e) {
      log('카메라 초기화 실패: $e');
      _controller = null;
      _isCameraInitialized = false;
      notifyListeners();    // 실패시의 호출
    }
  }

  /// 카메라 이미지 스트림을 시작합니다.
  void startImageStream(Function(CameraImage) onFrame) {
    if (_controller == null || !_isCameraInitialized || _isStreaming) return;

    _controller!.startImageStream((image) {
      if (_isStreaming) {
        _cameraImage = image;
        onFrame(image); // TFLite 추론을 위해 콜백 실행
      }

    });
    _isStreaming = true;
    log('카메라 스트림 시작');
  }

  /// 카메라 이미지 스트림을 중지합니다.
  void stopImageStream() {
    if (_controller == null || !_isCameraInitialized || !_isStreaming) return;

    _controller!.stopImageStream();
    _isStreaming = false;
    _cameraImage = null;
    log('카메라 스트림 중지');
  }

  /// 사진을 촬영합니다.
  Future<XFile?> takePicture() async {
    if (_controller == null || !_isCameraInitialized || _controller!.value.isTakingPicture) {
      return null;
    }
    
    try {
      final XFile file = await _controller!.takePicture();
      return file;
    } catch (e) {
      log('사진 촬영 실패: $e');
      return null;
    }
  }

  /// 서비스 종료 시 리소스 해제
  @override
  void dispose() {
    stopImageStream();
    _controller?.removeListener(notifyListeners);
    _controller?.disableOrientationListener();
    _controller?.dispose();
    _controller = null;
    _isCameraInitialized = false;
    log('CameraService 해제');
    super.dispose();
  }
}