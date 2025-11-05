// camera package is used to access the device camera and display the CameraPreview (startImageStream)
// Using Stack widget to overlay detection results on top of the CameraPreview. Consumer is used to listen to CameraViewModel for updates. (detection results)
// lib/src/screens/camera/camera_screen.dart

import 'package:camera/camera.dart'; //
import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:provider/provider.dart'; //
import 'package:auralens/src/screens/camera/camera_view_model.dart';
import 'package:auralens/src/services/camera_service.dart';
import 'package:auralens/src/screens/camera/widgets/composition_overlay_painter.dart';

/// README의 메인 카메라 UI 스크린
/// ViewModel을 주입하는 역할을 합니다.
class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ViewModel을 이 스크린 위젯 트리에 주입합니다.
    // ViewModel은 Context.read를 통해 main.dart에서 제공된 CameraService를 참조합니다.
    return ChangeNotifierProvider(
      create: (context) => CameraViewModel(
        context.read<CameraService>(),
      ),
      child: const CameraView(),
    );
  }
}

/// 실제 카메라 UI를 렌더링하고 ViewModel의 상태를 구독하는 위젯
class CameraView extends StatelessWidget {
  const CameraView({super.key});

  @override
  Widget build(BuildContext context) {
    // ViewModel의 상태 변경을 구독(watch)합니다.
    final cameraService = context.watch<CameraViewModel>().cameraService;

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
  Widget _buildCameraPreview(
      BuildContext context, CameraController controller) {
    
    // 1. ViewModel에서 ML Kit 결과 및 모든 상태 구독
    final List<DetectedObject> detections =
        context.watch<CameraViewModel>().detections;
    final Size? imageSize = context.watch<CameraViewModel>().imageSize;
    final Offset? compositionTarget =
        context.watch<CameraViewModel>().compositionTarget;
    final bool isCompositionCorrect =
        context.watch<CameraViewModel>().isCompositionCorrect;

    // 2. 카메라 프리뷰의 실제 종횡비(AspectRatio) 계산
    final cameraValue = controller.value;
    final cameraAspectRatio = cameraValue.aspectRatio;

    return Stack(
      fit: StackFit.expand, // Stack을 화면에 꽉 채움
      children: [
        // 레이어 1: 카메라 미리보기 (종횡비 유지)
        Center(
          child: AspectRatio(
            aspectRatio: cameraAspectRatio,
            child: CameraPreview(controller),
          ),
        ),

        // 레이어 2: AI 오버레이 (LayoutBuilder로 정확한 UI 크기 계산)
        LayoutBuilder(
          builder: (context, constraints) {
            // 현재 UI 위젯의 크기
            final widgetSize =
                Size(constraints.maxWidth, constraints.maxHeight);

            // ViewModel에 현재 UI 크기를 알려줌 (좌표 계산용)
            context.read<CameraViewModel>().setScreenSize(widgetSize);

            // 3. CustomPaint에 모든 상태 전달
            return CustomPaint(
              painter: CompositionOverlayPainter(
                detections: detections,
                imageSize: imageSize,       // 카메라 이미지 원본 크기
                widgetSize: widgetSize,     // 현재 UI 위젯 크기
                compositionTarget: compositionTarget,
                isCompositionCorrect: isCompositionCorrect,
              ),
            );
          },
        ),

        // 레이어 3: 설정 버튼 등 기타 UI
        Positioned(
          top: 50,
          right: 20,
          child: IconButton(
            icon: const Icon(Icons.settings, color: Colors.white, size: 30),
            onPressed: () {
              // TODO: (다음 단계) README의 'settings_screen.dart'로 이동
              // 예: Navigator.push(context, MaterialPageRoute(...));
            },
          ),
        ),
      ],
    );
  }
}