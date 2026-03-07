// lib/main.dart

import 'package:auralens/src/screens/camera/camera_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 화면 방향 고정을 위한 import 문
import 'package:provider/provider.dart';
import 'package:auralens/src/app.dart';
import 'package:auralens/src/services/camera_service.dart';
import 'package:auralens/src/services/tflite_service.dart';

void main() async {
  // Flutter 앱 실행 전 네이티브 바인딩 보장
  WidgetsFlutterBinding.ensureInitialized();

  // 화면 방향을 세로 모드로 고정 (모든 화면에서 세로 모드 유지)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // TFLite 모델 로드 (앱 시작 시 한 번만)
  final tfliteService = TFLiteService();
  await tfliteService.initialize();

  // 앱 실행
  runApp(
    MultiProvider(
      providers: [
        Provider<TFLiteService>.value(value: tfliteService), // TFLiteService를 Provider로 제공
        // CameraService를 ChangeNotifierProvider로 제공
        ChangeNotifierProvider(
          create: (_) => CameraService()..initializeCamera(), // 앱 시작 시 카메라 초기화
        ),
        ChangeNotifierProvider(
          create: (context) => CameraViewModel(
            context.read<CameraService>(),
            context.read<TFLiteService>(),
          )
        ),
      ],
      child: const MyApp(), // MyApp은 lib/src/app.dart에 정의
    ),
  );
}