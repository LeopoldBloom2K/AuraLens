// lib/src/screens/camera/camera_screen.dart

import 'dart:developer'; // log 사용
import 'dart:io'; // Platform 및 File 사용
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart'; // url_launcher 사용
import 'package:auralens/src/screens/camera/camera_view_model.dart';
import 'package:auralens/src/services/camera_service.dart';
import 'package:auralens/src/screens/camera/widgets/composition_overlay_painter.dart';
import 'package:auralens/src/screens/settings/settings_screen.dart';

/// README의 메인 카메라 UI 스크린
class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // main.dart에서 Provider를 제공하므로 여기서는 바로 CameraView를 반환합니다.
    return const CameraView();
  }
}

/// [수정] StatelessWidget -> StatefulWidget
/// 실제 카메라 UI를 렌더링하고 ViewModel의 상태를 구독하는 위젯
class CameraView extends StatefulWidget {
  const CameraView({super.key});

  @override
  State<CameraView> createState() => _CameraViewState();
}

/// [수정] State 클래스 생성
class _CameraViewState extends State<CameraView> {
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

  // [이동] 헬퍼 함수를 State 클래스 내부로
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

  // [이동] 헬퍼 함수를 State 클래스 내부로
  Widget _buildLoadingIndicator() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text('카메라를 준비 중입니다...', style: TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  // [이동] 헬퍼 함수를 State 클래스 내부로
  Widget _buildCameraPreview(
    BuildContext context,
    CameraController controller,
  ) {
    // 1. ViewModel에서 ML Kit 결과 및 모든 상태 구독
    return Consumer<CameraViewModel>(
      builder: (context, viewModel, child) {
        // 컨트롤러에서 직접 방향을 가져옴
        final CameraValue cameraValue = controller.value;
        final DeviceOrientation orientation = cameraValue.deviceOrientation;
        final int turns = _getRotationTurns(orientation);
        final bool isLandscape = (orientation ==
                DeviceOrientation.landscapeLeft ||
            orientation == DeviceOrientation.landscapeRight);

        // 2. 카메라 프리뷰의 실제 종횡비(AspectRatio) 계산
        return Stack(fit: StackFit.expand, children: [
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

              // 3. CustomPaint에 모든 상태 전달
              return CustomPaint(
                painter: CompositionOverlayPainter(
                  detections: viewModel.detections,
                  imageSize: viewModel.imageSize, // 카메라 이미지 원본 크기
                  widgetSize: widgetSize, // 현재 UI 위젯 크기
                  compositionTarget: viewModel.compositionTarget,
                  isCompositionCorrect: viewModel.isCompositionCorrect,
                  isGridEnabled: viewModel.isGridEnabled,
                  isAiAssistEnabled: viewModel.isAiAssistEnabled,
                  // triangularComposition: viewModel.triangularComposition // 추후 추가
                ),
              );
            },
          ),
          // 제어 버튼들 회전, 재배치 설정
          // 상단 버튼 바
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
                  _buildRotatedButton(
                    // 그리드
                    context,
                    turns: turns,
                    icon: viewModel.isGridEnabled
                        ? Icons.grid_on
                        : Icons.grid_off, // 아이콘 변경
                    onPressed: () =>
                        viewModel.toggleGrid(!viewModel.isGridEnabled), // 연결
                  ),
                  _buildRotatedButton(
                    // AI 어시스트
                    context,
                    turns: turns,
                    icon: viewModel.isAiAssistEnabled
                        ? Icons.insights
                        : Icons.insights_outlined, // 아이콘 변경
                    onPressed: () => viewModel
                        .toggleAiAssist(!viewModel.isAiAssistEnabled), // 연결
                  ),
                  _buildRotatedButton(
                    // 설정
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

          // 하단 버튼 바
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
                  _buildThumbnail(
                      context, turns, viewModel.recentPhoto), // 회전값(turns) 전달

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
                    onPressed: () => viewModel.switchCamera(), // 수정된 로직
                  ),
                ],
              ),
            ),
          )
        ]);
      },
    );
  }

  // [이동] 헬퍼 함수를 State 클래스 내부로
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

  // [이동 & 수정] 썸네일 위젯
  Widget _buildThumbnail(BuildContext context, int turns, XFile? recentPhoto) {
    Widget content;
    if (recentPhoto == null) {
      content = const Icon(Icons.photo_library, color: Colors.white, size: 24);
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
      onTap: () async {
        // [수정] `mounted` 체크는 State 클래스 내부에서만 사용 가능합니다.
        // `await` 호출 전에 `context`를 사용하는 변수를 저장할 필요 없이,
        // `await` 호출 후에 `mounted`를 체크하는 것이 더 안전합니다.

        if (recentPhoto != null) {
          final filePath = recentPhoto.path;
          Uri uri;

          if (Platform.isAndroid) {
            uri = Uri.file(filePath);
          } else if (Platform.isIOS) {
            uri = Uri.file(filePath);
          } else {
            uri = Uri.file(filePath);
          }

          try {
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            } else {
              // [수정] await 이후 context를 사용하기 전 mounted 체크
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('갤러리 앱을 열 수 없습니다.')),
              );
              log('갤러리 앱 실행 실패: $uri');
            }
          } catch (e) {
            log('갤러리 앱 실행 중 오류 발생: $e');
            // [수정] await 이후 context를 사용하기 전 mounted 체크
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('갤러리 앱 실행 중 오류: ${e.toString()}')),
            );
          }
        } else {
          // [수정] 동기 코드라도 mounted 체크를 하는 것이 안전합니다.
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('최근 촬영한 사진이 없습니다.')),
          );
        }
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.black.withValues(),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Center(child: content),
      ),
    );
  }
}