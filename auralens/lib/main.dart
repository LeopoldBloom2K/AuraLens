// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:auralens/src/app.dart';
// import 'package:auralens/src/services/camera_service.dart';
// import 'package:auralens/src/services/tflite_service.dart';

void main() async {
  // Flutter 앱 실행 전 네이티브 바인딩 보장
  WidgetsFlutterBinding.ensureInitialized();

  // (옵션) 권한을 앱 시작 시 요청할 경우
  // await Permissions.requestCameraAndStoragePermissions();

  // 서비스 인스턴스 생성
  final cameraService = CameraService();
  final tfliteService = TFLiteService();

  // 앱 실행
  runApp(
    MultiProvider(
      providers: [
        // CameraService를 ChangeNotifierProvider로 제공
        ChangeNotifierProvider(
          create: (_) => cameraService..initializeCamera(), // 앱 시작 시 카메라 초기화
        ),
        // TFLiteService를 Provider로 제공 (상태 변경 알림이 필요 없는 경우)
        Provider(
          create: (_) => tfliteService..loadModel(), // 앱 시작 시 모델 로드
          lazy: false, // 앱 시작 시 바로 로드
          dispose: (_, service) => service.dispose(),
        ),
        
        // (추후) CompositionService, CameraViewModel 등 추가
      ],
      child: const MyApp(), // MyApp은 lib/src/app.dart에 정의
    ),
  );
}

// MyApp 클래스는 lib/src/app.dart 로 분리하는 것을 권장합니다.
// 예시:
// class MyApp extends StatelessWidget {
//   const MyApp({Key? key}) : super(key: key);
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'AuraLens',
//       theme: ThemeData(
//         primarySwatch: Colors.blue,
//         brightness: Brightness.dark,
//       ),
//       home: const CameraScreen(), //
//     );
//   }
// }