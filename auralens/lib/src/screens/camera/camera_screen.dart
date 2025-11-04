// camera package is used to access the device camera and display the CameraPreview (startImageStream)
// Using Stack widget to overlay detection results on top of the CameraPreview. Consumer is used to listen to CameraViewModel for updates. (detection results)
// lib/src/screens/camera/camera_screen.dart

import 'package:camera/camera.dart'; //
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; //
// import 'package:auralens/src/screens/camera/camera_view_model.dart';
// import 'package:auralens/src/services/camera_service.dart';
// import 'package:auralens/src/services/tflite_service.dart';
// import 'package:auralens/src/screens/camera/widgets/composition_overlay_painter.dart';

/// README의 메인 카메라 UI 스크린
class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ViewModel을 이 스크린에 주입합니다.
    // ViewModel은 Context.read를 통해 main.dart에서 제공된 Service들을 참조합니다.
    return ChangeNotifierProvider(
      create: (context) => CameraViewModel(
        context.read<CameraService>(),
        context.read<TFLiteService>(),
      ),
      child: const CameraView(),
    );
  }
}

/// 실제 카메라 UI를 렌더링하는 위젯
class CameraView extends StatelessWidget {
  const CameraView({super.key});

  @override
  Widget build(BuildContext context) {
    // ViewModel의 상태를 구독(watch)합니다.
    final cameraViewModel = context.watch<CameraViewModel>();
    final cameraService = cameraViewModel.cameraService;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Builder(
        builder: (context) {
          // 1. 카메라 서비스가 초기화되었는지 확인
          if (!cameraService.isCameraInitialized ||
              cameraService.controller == null) {
            return _buildLoadingIndicator();
          }

          // 2. 카메라 미리보기 및 오버레이 빌드
          final cameraController = cameraService.controller!;
          return _buildCameraPreview(context, cameraController);
        },
      ),
      // 3. 사진 촬영 버튼
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // ViewModel의 촬영 함수 호출
          context.read<CameraViewModel>().takePicture();
        },
        child: const Icon(Icons.camera_alt),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  /// 로딩 인디케이터
  Widget _buildLoadingIndicator() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text(
            '카메라를 준비 중입니다...',
            style: TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  /// 카메라 미리보기와 구도 가이드를 겹쳐서 보여주는 위젯

      BuildContext context, CameraController controller) {

    // 1. ViewModel에서 Detections 리스트 구독
    final detections = context.watch<CameraViewModel>().detections;

    // 2. 카메라 프리뷰의 실제 종횡비(AspectRatio) 계산
    final cameraValue = controller.value;
    final cameraAspectRatio = cameraValue.aspectRatio;

    // 3. 카메라 프리뷰 사이즈 (CustomPaint에 전달하기 위함)
    final cameraPreviewSize = cameraValue.previewSize!;

    return Stack(
      fit: StackFit.expand, // Stack을 화면에 꽉 채움
      children: [
        // 레이어 1: 카메라 미리보기
        Center(
          child: CameraPreview(controller),
        ),

        // 레이어 2: 3분할 가이드 및 AI 가이드 오버레이
        CustomPaint(
          painter: CompositionOverlayPainter(
              detections: detections, // ViewModel의 감지 결과 전달
              cameraPreviewSize: cameraPreviewSize, // 프리뷰 원본 사이즈 전달
          ),
        ),
        // 레이어 3: 설정 버튼 등 기타 UI
        Positioned(
          top: 50,
          right: 20,
          child: IconButton(
            icon: const Icon(Icons.settings, color: Colors.white, size: 30),
            onPressed: () {
              // TODO: README의 'settings_screen.dart'로 이동
            },
          ),
        ),
      ],
    );
  }
}