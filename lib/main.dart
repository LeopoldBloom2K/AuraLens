// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:auralens/src/app.dart';
import 'package:auralens/src/services/camera_service.dart';

void main() async {
  // Flutter 앱 실행 전 네이티브 바인딩 보장
  WidgetsFlutterBinding.ensureInitialized();

  // 서비스 인스턴스 생성
  final cameraService = CameraService();

  // 앱 실행
  runApp(
    MultiProvider(
      providers: [
        // CameraService를 ChangeNotifierProvider로 제공
        ChangeNotifierProvider(
          create: (_) => cameraService..initializeCamera(), // 앱 시작 시 카메라 초기화
        ),
      ],
      child: const MyApp(), // MyApp은 lib/src/app.dart에 정의
    ),
  );
}
