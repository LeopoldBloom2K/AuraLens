// lib/main.dart

import 'package:auralens/src/screens/camera/camera_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 화면 방향 고정을 위한 import 문
import 'package:provider/provider.dart';
import 'package:auralens/src/app.dart';
import 'package:auralens/src/services/camera_service.dart';
import 'package:auralens/src/services/inference_service.dart';
import 'package:auralens/src/services/model_gate.dart';
import 'package:auralens/src/utils/permissions.dart';

void main() async {
  // Flutter 앱 실행 전 네이티브 바인딩 보장
  WidgetsFlutterBinding.ensureInitialized();

  // 화면 방향을 세로 모드로 고정 (모든 화면에서 세로 모드 유지)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // 카메라·저장소 권한 요청 — 카메라 초기화보다 먼저 실행
  await Permissions.requestCameraAndStoragePermissions();

  // 모델 파일 존재 여부 확인 (게이트) — 반드시 InferenceService 보다 먼저 실행
  await ModelGate.probe();

  // ONNX 모델 로드 — ModelGate.isReady == true 일 때만 실제 초기화됨
  final inferenceService = InferenceService();
  await inferenceService.initialize();

  // 앱 실행
  runApp(
    MultiProvider(
      providers: [
        Provider<InferenceService>.value(value: inferenceService),
        // CameraService를 ChangeNotifierProvider로 제공
        ChangeNotifierProvider(
          create: (_) => CameraService()..initializeCamera(), // 앱 시작 시 카메라 초기화
        ),
        ChangeNotifierProvider(
          create: (context) => CameraViewModel(
            context.read<CameraService>(),
            context.read<InferenceService>(),
          )
        ),
      ],
      child: const MyApp(), // MyApp은 lib/src/app.dart에 정의
    ),
  );
}