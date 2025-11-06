// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

// test/widget_test.dart

import 'package:auralens/src/services/camera_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// import 'package:auralens/main.dart'; (X)
import 'package:auralens/src/app.dart'; // (O) MyApp을 여기서 가져옵니다.

void main() {
  // 테스트에 필요한 서비스들을 미리 준비합니다.
  // (실제 서비스를 사용하거나, Mock 객체를 사용할 수 있습니다)
  final cameraService = CameraService();
  // (ML Kit로 변경하면서 TFLiteService는 제거됨)

  testWidgets('CameraScreen 로딩 스모크 테스트', (WidgetTester tester) async {
    // 3. main.dart의 MultiProvider와 동일한 환경으로 앱을 빌드합니다.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => cameraService, 
            // 테스트에서는 실제 카메라 초기화를 호출하지 않을 수 있습니다.
            // ..initializeCamera(), 
          ),
          // (TFLiteService Provider는 ML Kit로 전환하며 제거됨)
        ],
        child: const MyApp(), // lib/src/app.dart의 MyApp
      ),
    );

    // 기존 카운터 테스트 대신,
    // CameraScreen이 처음 로드될 때 (카메라 초기화 전)
    // 로딩 인디케이터(CircularProgressIndicator)가 표시되는지 확인합니다.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('카메라를 준비 중입니다...'), findsOneWidget);

    // 카운터 관련 테스트 로직은 삭제
    // expect(find.text('0'), findsNothing);
    // expect(find.text('1'), findsOneWidget);
  });
}