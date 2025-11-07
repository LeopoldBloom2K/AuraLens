// camera package is used to access the device camera and display the CameraPreview (startImageStream)
// Using Stack widget to overlay detection results on top of the CameraPreview. Consumer is used to listen to CameraViewModel for updates. (detection results)
// lib/src/screens/camera/camera_screen.dart

import 'package:camera/camera.dart'; //
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:provider/provider.dart'; //
import 'package:auralens/src/screens/camera/camera_view_model.dart';
import 'package:auralens/src/services/camera_service.dart';
import 'package:auralens/src/screens/camera/widgets/composition_overlay_painter.dart';
import 'dart:io'; // 이미지 파일 (썸네일) 사용하기 위한 import 


/// README의 메인 카메라 UI 스크린
/// ViewModel을 주입하는 역할을 합니다.
class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ViewModel을 이 스크린 위젯 트리에 주입합니다.
    // ViewModel은 Context.read를 통해 main.dart에서 제공된 CameraService를 참조합니다.
    return ChangeNotifierProvider(
      create: (context) => CameraViewModel(context.read<CameraService>()),
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
          return _buildCameraPreview(context, cameraService.controller!);
        },
      ),
    );
  }

// 기기 방향에 따라 아이콘 한번에 정렬
  int _getRotationTurns(DeviceOrientation orientation) {
    switch (orientation) {
      case DeviceOrientation.portraitUp:
      return 0; // 0도
      case DeviceOrientation.landscapeLeft:
      return 1; // 90도(시계)
      case DeviceOrientation.portraitDown:
      return 2; // 180도
      case DeviceOrientation.landscapeRight:
      return 3; // 270도(반시계)
      default:
        return 0;
    }
  }

  /// 로딩 인디케이터
  Widget _buildLoadingIndicator() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text('카메라를 준비 중입니다...', 
          style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  /// 카메라 미리보기와 구도 가이드를 겹쳐서 보여주는 위젯
  Widget _buildCameraPreview(
    BuildContext context,
    CameraController controller,
  ) {
    // 1. ViewModel에서 ML Kit 결과 및 모든 상태 구독
    final viewModel = context
        .read<CameraViewModel>();   // 방향 확인만을 위해 read

    // 컨트롤러에서 직접 방향을 가져옴
    final CameraValue cameraValue = controller.value;
    final DeviceOrientation orientation = cameraValue.deviceOrientation;
    final int turns = _getRotationTurns(orientation); 
    final bool isLandscape = (
      orientation == DeviceOrientation.landscapeLeft ||
      orientation == DeviceOrientation.landscapeRight
      );

    // 2. 카메라 프리뷰의 실제 종횡비(AspectRatio) 계산
    return Stack(
      fit: StackFit.expand, // Stack을 화면에 꽉 채움
      children: [
        // 레이어 1: 카메라 미리보기 (종횡비 유지)
        Center(
          child: AspectRatio(
            aspectRatio: cameraValue.aspectRatio,
            child: CameraPreview(controller),
          ),
        ),

        // 레이어 2: AI 오버레이 (LayoutBuilder로 정확한 UI 크기 계산)
        LayoutBuilder(
          builder: (context, constraints) {
            // 현재 UI 위젯의 크기
            final widgetSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            viewModel.setScreenSize(widgetSize);

        return Consumer<CameraViewModel>(
          builder: (context, vm, child) {
            final widgetSize = Size(constraints.maxWidth, constraints.maxHeight);
            vm.setScreenSize(widgetSize);
            
            // 3. CustomPaint에 모든 상태 전달
            return CustomPaint(
              painter: CompositionOverlayPainter(
                detections: vm.detections,
                imageSize: vm.imageSize, // 카메라 이미지 원본 크기
                widgetSize: widgetSize, // 현재 UI 위젯 크기
                compositionTarget: vm.compositionTarget,
                isCompositionCorrect: vm.isCompositionCorrect,
                isGridEnabled: vm.isGridEnabled,
                isAiAssistEnabled: vm.isAiAssistEnabled
              ),
            );
          },
        );
          },  
        ),
// 제어 버튼들 회전, 재배치 설정
        // 상단 버튼
        // 상단 버튼 바 (세로: 상단 Row, 가로: 좌측 Column)
        Positioned(
          top: isLandscape ? 0 : 50,
          left: isLandscape ? 20 : 0,
          right: isLandscape ? null : 0,
          bottom: isLandscape ? 0 : null,
          child: SafeArea(
            child: Flex(
              direction: isLandscape ? Axis.vertical : Axis.horizontal,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildRotatedButton( // 그리드
                  context,
                  turns: turns,
                  icon: Icons.grid_on, // TODO: isGridEnabled 상태에 따라 변경
                  onPressed: () {}, // TODO: viewModel.toggleGrid()
                ),
                _buildRotatedButton( // AI 어시스트
                  context,
                  turns: turns,
                  icon: Icons.insights, // TODO: isAiEnabled 상태에 따라 변경
                  onPressed: () {}, // TODO: viewModel.toggleAiAssist()
                ),
                _buildRotatedButton( // 설정
                  context,
                  turns: turns,
                  icon: Icons.settings,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const SettingsScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        
        // 하단 버튼 바 (세로: 하단 Row, 가로: 우측 Column)
        Positioned(
          bottom: isLandscape ? 0 : 20,
          right: isLandscape ? 20 : 0,
          left: isLandscape ? null : 0,
          child: SafeArea(
            child: Flex(
              direction: isLandscape ? Axis.vertical : Axis.horizontal,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 최근 갤러리 썸네일
                _buildThumbnail(context, turns), // 회전값(turns) 전달
                
                // 셔터 버튼 (회전 필요 없음)
                GestureDetector(
                  onTap: () => viewModel.takePicture(),
                  child: Container(
                    margin: isLandscape 
                        ? const EdgeInsets.symmetric(vertical: 20)
                        : const EdgeInsets.symmetric(horizontal: 20),
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.grey, width: 4),
                    ),
                  ),
                ),
                
                // 카메라 전환 버튼 (예시)
                _buildRotatedButton(
                  context,
                  turns: turns,
                  icon: Icons.flip_camera_ios,
                  onPressed: () {
                    // TODO: 카메라 전환 로직
                  },
                ),
      ],
            ),
          ),
    )
      ]
    );
  }
}

// 모든 아이콘 한번에 회전시키는 위젯 생성
Widget _buildRotatedButton(
  BuildContext context, {
    required int turns,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: RotatedBox(
      quarterTurns: turns,
      child: Icon(icon, color: Colors.white, size: 30),
      ),
      onPressed: onPressed,
    );
  }

  // 썸네일 위젯 
  Widget _buildThumbnail(BuildContext context, int turns) {  
    final recentPhoto = context.watch<CameraViewModel>().recentPhoto;

    Widget content;
    if (recentPhoto == null) {
      content = const Icon(Icons.photo_library_outlined, color: Colors.white);
    } else {
      content = ClipOval(
        child: Image.file(
          File(recentPhoto.path),
          width: 50,
          height: 50,
          fit: BoxFit.cover,
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        //TODO: 갤러리 화면 이동 로직 구현 
      },
      child: RotatedBox(
        quarterTurns: turns,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
          ),
          child: content,
        ),
      ),
    );
  }