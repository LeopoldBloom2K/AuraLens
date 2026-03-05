// lib/src/screens/camera/camera_screen.dart

import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:auralens/src/screens/camera/camera_view_model.dart';
import 'package:auralens/src/screens/camera/widgets/composition_overlay_painter.dart';
import 'package:auralens/src/screens/settings/settings_screen.dart';
import 'package:open_filex/open_filex.dart';

class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CameraView();
  }
}

class CameraView extends StatefulWidget {
  const CameraView({super.key});

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  DateTime? _currentBackPressTime;

  @override
  Widget build(BuildContext context) {
    final cameraService = context.watch<CameraViewModel>().cameraService;

    // 🚀 구형 WillPopScope 대신 최신 PopScope 적용!
    return PopScope(
      canPop: false, // 기본 뒤로가기 방지
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;

        DateTime now = DateTime.now();
        if (_currentBackPressTime == null ||
            now.difference(_currentBackPressTime!) > const Duration(seconds: 2)) {
          _currentBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('뒤로 가기 버튼을 한 번 더 누르면 앱이 종료됩니다.'),
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Builder(
          builder: (context) {
            if (!cameraService.isCameraInitialized ||
                cameraService.controller == null) {
              return _buildLoadingIndicator();
            }

            return _buildCameraPreview(context, cameraService.controller!);
          },
        ),
      ),
    );
  }

  int _getRotationTurns(DeviceOrientation orientation) {
    switch (orientation) {
      case DeviceOrientation.portraitUp: return 0;
      case DeviceOrientation.landscapeLeft: return 1;
      case DeviceOrientation.portraitDown: return 2;
      case DeviceOrientation.landscapeRight: return 3;
    }
  }

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

  Widget _buildCameraPreview(BuildContext context, CameraController controller) {
    return Consumer<CameraViewModel>(
      builder: (context, viewModel, child) {
        final CameraValue cameraValue = controller.value;
        final DeviceOrientation orientation = cameraValue.deviceOrientation;
        final int turns = _getRotationTurns(orientation);
        final bool isLandscape = (orientation == DeviceOrientation.landscapeLeft ||
            orientation == DeviceOrientation.landscapeRight);

        return Stack(fit: StackFit.expand, children: [
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: 1000,
                height: 1000 / cameraValue.aspectRatio,
                child: CameraPreview(controller),
              ),
            ),
          ),

          LayoutBuilder(
            builder: (context, constraints) {
              final widgetSize = Size(constraints.maxWidth, constraints.maxHeight);
              viewModel.setScreenSize(widgetSize);

              return CustomPaint(
                painter: CompositionOverlayPainter(
                  imageSize: viewModel.imageSize,
                  widgetSize: widgetSize,
                  isGridEnabled: viewModel.isGridEnabled,
                  isAiAssistEnabled: viewModel.isAiAssistEnabled,
                  currentScene: viewModel.currentScene,
                ),
              );
            },
          ),

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
                    context,
                    turns: turns,
                    icon: viewModel.isGridEnabled ? Icons.grid_on : Icons.grid_off,
                    onPressed: () => viewModel.toggleGrid(!viewModel.isGridEnabled),
                  ),
                  _buildRotatedButton(
                    context,
                    turns: turns,
                    icon: viewModel.isAiAssistEnabled ? Icons.insights : Icons.insights_outlined,
                    onPressed: () => viewModel.toggleAiAssist(!viewModel.isAiAssistEnabled),
                  ),
                  _buildRotatedButton(
                    context,
                    turns: turns,
                    icon: Icons.settings,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SettingsScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: isLandscape ? 0 : 20,
            right: isLandscape ? 20 : 0,
            left: isLandscape ? null : 0,
            child: SafeArea(
              child: Flex(
                direction: isLandscape ? Axis.vertical : Axis.horizontal,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildThumbnail(context, turns, viewModel.recentPhoto),

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

                  _buildRotatedButton(
                    context,
                    turns: turns,
                    icon: Icons.flip_camera_ios,
                    onPressed: () => viewModel.switchCamera(),
                  ),
                ],
              ),
            ),
          )
        ]);
      },
    );
  }

  Widget _buildRotatedButton(BuildContext context, {required int turns, required IconData icon, required VoidCallback onPressed}) {
    return IconButton(
      icon: RotatedBox(quarterTurns: turns, child: Icon(icon, color: Colors.white, size: 30)),
      onPressed: onPressed,
    );
  }

  Widget _buildThumbnail(BuildContext context, int turns, XFile? recentPhoto) {
    Widget content;
    if (recentPhoto == null) {
      content = const Icon(Icons.photo_library, color: Colors.white, size: 24);
    } else {
      content = ClipOval(child: Image.file(File(recentPhoto.path), width: 50, height: 50, fit: BoxFit.cover));
    }

    return GestureDetector(
      onTap: () async {
        if (recentPhoto != null) {
          final filePath = recentPhoto.path;
          try {
            final result = await OpenFilex.open(filePath);
            if (result.type != ResultType.done) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('갤러리 앱을 열 수 없습니다: ${result.message}')));
            }
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류 발생: ${e.toString()}')));
          }
        } else {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('최근 촬영한 사진이 없습니다.')));
        }
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5), // 🚀 최신 문법!
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Center(child: content),
      ),
    );
  }
}