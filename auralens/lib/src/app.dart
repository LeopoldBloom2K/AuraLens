// lib/src/app.dart

import 'package:flutter/material.dart';
// import 'package:auralens/src/screens/camera/camera_screen.dart'; // (곧 생성할 파일)

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AuraLens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        // 앱의 전반적인 시각적 테마를 정의합니다.
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      // README.md에서 계획한 카메라 스크린을 홈으로 설정합니다.
      home: const CameraScreen(),
    );
  }
}