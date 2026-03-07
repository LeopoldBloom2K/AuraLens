// lib/src/screens/camera/camera_screen.dart

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:auralens/src/screens/camera/camera_view_model.dart';
import 'package:auralens/src/screens/camera/widgets/composition_overlay_painter.dart';
import 'package:auralens/src/screens/settings/settings_screen.dart';
import 'package:auralens/src/screens/camera/gallery_screen.dart';

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
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  int _iconTurns = 0;

  @override
  void initState() {
    super.initState();
    // 🚀 수정 1: 가로 모드 아이콘 회전 방향을 현실과 맞게(반대로) 교정 완료!
    _accelSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      int newTurns = _iconTurns;
      if (event.x > 5) {
        newTurns = 1; // 폰을 왼쪽으로 눕힘 -> 아이콘은 시계방향 90도 회전
      } else if (event.x < -5) {
        newTurns = 3; // 폰을 오른쪽으로 눕힘 -> 아이콘은 반시계 90도 회전
      } else if (event.y > 5) {
        newTurns = 0; // 똑바로 세움
      } else if (event.y < -5) {
        newTurns = 2; // 거꾸로
      }

      if (newTurns != _iconTurns) {
        setState(() => _iconTurns = newTurns);
      }
    });
  }

  @override
  void dispose() {
    _accelSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cameraService = context.watch<CameraViewModel>().cameraService;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        DateTime now = DateTime.now();
        if (_currentBackPressTime == null || now.difference(_currentBackPressTime!) > const Duration(seconds: 2)) {
          _currentBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('뒤로 가기 버튼을 한 번 더 누르면 앱이 종료됩니다.'), duration: Duration(seconds: 2)),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Builder(
          builder: (context) {
            if (!cameraService.isCameraInitialized || cameraService.controller == null) {
              return _buildLoadingIndicator();
            }
            return _buildCameraPreview(context, cameraService.controller!);
          },
        ),
      ),
    );
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
        
        // 🚀 수정 2: 어떤 기기든 무조건 세로 비율로 계산되도록 강제 보정 (화면 찌그러짐 완벽 방지)
        final double aspect = cameraValue.aspectRatio;
        final double portraitAspect = aspect < 1 ? aspect : 1 / aspect;

        return Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: AspectRatio(
                aspectRatio: viewModel.currentRatio.value,
                child: ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: 1000,
                      height: 1000 / portraitAspect,
                      child: CameraPreview(controller),
                    ),
                  ),
                ),
              ),
            ),

            Container(
              alignment: Alignment.center,
              child: AspectRatio(
                aspectRatio: viewModel.currentRatio.value,
                child: LayoutBuilder(
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
              ),
            ),

            Positioned(
              top: 50,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildRotatedTextButton(
                      context,
                      turns: _iconTurns,
                      text: viewModel.currentRatio.label,
                      onPressed: () => viewModel.toggleRatio(),
                    ),
                    const SizedBox(width: 16),
                    _buildRotatedButton(
                      context,
                      turns: _iconTurns,
                      icon: viewModel.isGridEnabled ? Icons.grid_on : Icons.grid_off,
                      onPressed: () => viewModel.toggleGrid(!viewModel.isGridEnabled),
                    ),
                    const SizedBox(width: 16),
                    _buildRotatedButton(
                      context,
                      turns: _iconTurns,
                      icon: viewModel.isAiAssistEnabled ? Icons.insights : Icons.insights_outlined,
                      onPressed: () => viewModel.toggleAiAssist(!viewModel.isAiAssistEnabled),
                    ),
                    const SizedBox(width: 16),
                    _buildRotatedButton(
                      context,
                      turns: _iconTurns,
                      icon: Icons.settings,
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
                      },
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildThumbnail(context, _iconTurns, viewModel.recentPhoto),

                    GestureDetector(
                      onTap: () => viewModel.takePicture(),
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade400, width: 4),
                        ),
                      ),
                    ),

                    _buildRotatedButton(
                      context,
                      turns: _iconTurns,
                      icon: Icons.flip_camera_ios,
                      size: 36,
                      onPressed: () => viewModel.switchCamera(),
                    ),
                  ],
                ),
              ),
            )
          ],
        );
      },
    );
  }

  Widget _buildRotatedButton(BuildContext context, {required int turns, required IconData icon, required VoidCallback onPressed, double size = 30}) {
    return IconButton(
      icon: AnimatedRotation(
        turns: turns * 0.25,
        duration: const Duration(milliseconds: 300),
        child: Icon(icon, color: Colors.white, size: size,
        shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.8),
              blurRadius: 4.0,
              offset: const Offset(1.0, 1.0),
            )
          ],
        ),
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildRotatedTextButton(BuildContext context, {required int turns, required String text, required VoidCallback onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedRotation(
        turns: turns * 0.25,
        duration: const Duration(milliseconds: 300),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 1.5),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 4.0,
                offset: const Offset(1.0, 1.0),
              )
            ],
          ),
          child: Text(text, style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
            shadows: [
                  Shadow(
                    color: Colors.black,
                    blurRadius: 3.0,
                    offset: Offset(1.0, 1.0),
                  )
                ],
              )
            ),
          ),
        ),
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
        final viewModel = context.read<CameraViewModel>();
        if (viewModel.sessionPhotos.isNotEmpty) {
          await viewModel.pauseInference(); // 카메라 프리뷰 일시 정지

          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const GalleryScreen()),
          );

          viewModel.resumeInference(); // 카메라 프리뷰 재개
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('아직 촬영한 사진이 없습니다.')),
          );
        }
      },
      child: AnimatedRotation(
        turns: turns * 0.25,
        duration: const Duration(milliseconds: 300),
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 4.0,
                offset: const Offset(1.0, 1.0),
              )
            ],
          ),
          child: Center(child: content),
        ),
      ),
    );
  }
}