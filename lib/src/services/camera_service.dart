// lib/src/services/camera_service.dart

import 'dart:developer';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:auralens/src/models/camera_settings.dart'; // CameraResolution import

class CameraService with ChangeNotifier {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  
  // 이미지 스트림이 활성화되었는지 추적
  bool _isStreamingImages = false;

  // 현재 카메라 인덱스 (0:전면 1:후면)
  int _selectedCameraIdx = 0;

  // 현재 해상도 추적 
  CameraResolution _currentResolution = CameraResolution.medium;

  CameraController? get controller => _controller;
  bool get isCameraInitialized => _isCameraInitialized;

  // 생성자에서 카메라 초기화 시작 (main.dart에서 인스턴스 생성 시 호출)
  CameraService() {
    // initializeCamera(); // MultiProvider에서 CameraService가 create될 때 호출되도록 변경
  }

  Future<void> initializeCamera({int cameraIdx = 0}) async {
    if (_isCameraInitialized && _selectedCameraIdx == cameraIdx) return; // 이미 초기화되었다면 다시 하지 않음

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
      
      // 요청한 카메라 인덱스 유효인지 확인
      if (cameraIdx < 0 || cameraIdx >= _cameras.length) {
        cameraIdx = 0; // 유효하지않을 시 첫 번째 카메라 선택 
      }
      _selectedCameraIdx = cameraIdx;

      // 기본 해상도 preset 설정 (초기값은 medium으로 시작)
      ResolutionPreset preset = _getResolutionPreset(CameraResolution.medium);

      _controller = CameraController(
        _cameras[0], // 첫 번째 카메라 사용
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420, // ML Kit에 적합한 포맷
      );

      await _controller!.initialize();
      _isCameraInitialized = true;
      
      // 컨트롤러의 상태 변화를 CameraService 내부에서 리스닝
      _controller!.addListener(_onControllerValueChanged);

    } on CameraException catch (e) {
      log('카메라 초기화 실패: $e');
      _isCameraInitialized = false;
    } finally {
      notifyListeners(); // UI에 상태 변경 알림
    }
  }

  Future<void> switchCamera() async {
    if (_cameras.isEmpty) {
      log('전환할 카메라가 없습니다.');
      return;
    }

    log('카메라 전환중..');


    // 현재 스트리밍 중일때 해제
    bool wasStreaming = _isStreamingImages;
    if (wasStreaming) {
      await stopImageStream();
    }

    // 다음 카메라 인덱스 선택
    _selectedCameraIdx = (_selectedCameraIdx + 1) % _cameras.length; 

    // 새 카메라로 초기화
    await initializeCamera(cameraIdx: _selectedCameraIdx);

    // 이전에 스트리밍 중이었다면 다시 시작 (CameraViewModel이 반응하도록 notify)
    // ViewModel이 CameraService의 notifyListeners()를 듣고
    // _isCameraInitialized 상태가 true가 되면 _startModelInference()를 다시 호출하도록 해야 합니다.
    // 여기서는 별도로 startImageStream을 호출하지 않습니다.

    log('카메라 전환 완료: 현재 ${_selectedCameraIdx == 0 ? "후면" : "전면"} 카메라');
    notifyListeners();
  }

  



  // CameraController의 value 변경 감지 리스너
  void _onControllerValueChanged() {
    // 예를 들어, 카메라가 dispose되거나 오류가 발생할 때 상태를 업데이트할 수 있습니다.
    // log('CameraController value changed: ${_controller?.value}');
    notifyListeners(); // ViewModel에게 CameraController 상태 변화를 알림
  }

  Future<void> startImageStream(void Function(CameraImage image) onAvailable) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      log('이미지 스트림 시작 실패: 컨트롤러가 초기화되지 않았습니다.');
      return;
    }
    if (_isStreamingImages) {
      log('이미지 스트림이 이미 실행 중입니다.');
      return;
    }

    try {
      await _controller!.startImageStream(onAvailable);
      _isStreamingImages = true;
      log('이미지 스트림 시작 성공');
    } on CameraException catch (e) {
      log('이미지 스트림 시작 실패: $e');
    }
  }

  Future<void> stopImageStream() async {
    if (_controller == null || !_isStreamingImages) return;

    try {
      await _controller!.stopImageStream();
      _isStreamingImages = false;
      log('이미지 스트림 정지 성공');
    } on CameraException catch (e) {
      log('이미지 스트림 정지 실패: $e');
    }
  }

  Future<XFile?> takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      log('사진 촬영 실패: 컨트롤러가 초기화되지 않았습니다.');
      return null;
    }
    if (_controller!.value.isTakingPicture) {
      log('사진 촬영 중: 이전 촬영 완료 대기');
      return null;
    }

    try {
      final XFile file = await _controller!.takePicture();
      log('사진 촬영 성공: ${file.path}');
      return file;
    } on CameraException catch (e) {
      log('사진 촬영 실패: $e');
      return null;
    }
  }

  // [추가] 해상도 프리셋 변환 헬퍼 함수
  ResolutionPreset _getResolutionPreset(CameraResolution resolution) {
    switch (resolution) {
      case CameraResolution.low: return ResolutionPreset.low;
      case CameraResolution.medium: return ResolutionPreset.medium;
      case CameraResolution.high: return ResolutionPreset.high;
      // case CameraResolution.veryHigh: return ResolutionPreset.veryHigh; // 필요시 추가
      // case CameraResolution.max: return ResolutionPreset.max; // 필요시 추가
    }
  }

  // [추가] 카메라 해상도 업데이트 로직
  Future<void> updateCameraResolution(CameraResolution newResolution) async {
    if (controller == null || !controller!.value.isInitialized) {
      log('카메라가 아직 준비되지 않아 해상도 변경을 보류합니다.');
      return;
    }

    log('카메라 해상도 변경 시도: ${newResolution.name}');

    // 현재 해상도로 업데이트
    _currentResolution = newResolution;

    // 현재 이미지 스트림이 실행 중이라면 잠시 정지
    bool wasStreaming = _isStreamingImages;
    if (wasStreaming) {
      await stopImageStream();
    }

    // 컨트롤러 해제
    await _controller!.dispose();
    _controller = null;
    _isCameraInitialized = false;

    // 현재 컨트롤러 해제
    await _controller!.dispose();
    _controller = null;
    _isCameraInitialized = false;

    // 새 해상도로 컨트롤러 재초기화
    await initializeCamera(cameraIdx: _selectedCameraIdx);

    try {
      await _controller!.initialize();
      _isCameraInitialized = true;
      log('카메라 해상도 업데이트 성공: ${newResolution.name}');
      _controller!.addListener(_onControllerValueChanged); // 새 컨트롤러에 리스너 다시 연결
    } on CameraException catch (e) {
      log('카메라 해상도 업데이트 실패: $e');
      _isCameraInitialized = false;
    } finally {
      notifyListeners(); // UI에 상태 변경 알림
      }
    }
  

  @override
  void dispose() {
    log('CameraService 해제');
    _controller?.removeListener(_onControllerValueChanged); // 리스너 해제
    _controller?.dispose();
    super.dispose();
  }
}