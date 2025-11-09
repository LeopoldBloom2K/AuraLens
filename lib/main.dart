// lib/main.dart

import 'package:auralens/src/screens/camera/camera_view_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:auralens/src/app.dart';
import 'package:auralens/src/services/camera_service.dart';

void main() async {
  // Flutter 앱 실행 전 네이티브 바인딩 보장
  WidgetsFlutterBinding.ensureInitialized();

  // 앱 실행
  runApp(
    MultiProvider(
      providers: [
        // CameraService를 ChangeNotifierProvider로 제공
        ChangeNotifierProvider(
          create: (_) => CameraService(), // 앱 시작 시 카메라 초기화
        ),
        ChangeNotifierProvider(
          create: (context) => CameraViewModel(context.read<CameraService>())
        ),
      ],
      child: const MyApp(), // MyApp은 lib/src/app.dart에 정의
    ),
  );
}
