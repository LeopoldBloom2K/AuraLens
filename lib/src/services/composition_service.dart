// Received object's bounding box, class index, and confidence score from TFLiteService and provides methods to access these properties. (DetectionResult)
// lib/src/services/composition_service.dart

import 'dart:ui'; // Offset, Rect, Size 사용

/// AI 결과(좌표)를 바탕으로 구도(타겟) 계산 로직을 담당하는 서비스
class CompositionService {
  
  /// 화면 크기와 3분할 '파워 포인트' 목록을 계산합니다.
  List<Offset> getPowerPoints(Size screenSize) {
    final double thirdOfWidth = screenSize.width / 3;
    final double thirdOfHeight = screenSize.height / 3;

    return [
      Offset(thirdOfWidth, thirdOfHeight),     // 좌상단 교차점
      Offset(thirdOfWidth * 2, thirdOfHeight), // 우상단 교차점
      Offset(thirdOfWidth, thirdOfHeight * 2), // 좌하단 교차점
      Offset(thirdOfWidth * 2, thirdOfHeight * 2), // 우하단 교차점
    ];
  }

  /// 감지된 객체의 중심점에서 가장 가까운 '파워 포인트'를 찾습니다.
  ///
  /// [detectionBox] - AI가 감지한 객체의 바운딩 박스 (화면 절대 좌표)
  /// [screenSize] - 현재 화면(CustomPaint)의 크기
  Offset? findClosestPowerPoint(Rect detectionBox, Size screenSize) {
    if (detectionBox.isEmpty) return null;

    final List<Offset> powerPoints = getPowerPoints(screenSize);
    final Offset boxCenter = detectionBox.center; // 감지된 객체의 중심

    Offset closestPoint = powerPoints.first;
    double minDistance = (boxCenter - closestPoint).distanceSquared;

    for (final point in powerPoints.skip(1)) {
      final double distance = (boxCenter - point).distanceSquared;
      if (distance < minDistance) {
        minDistance = distance;
        closestPoint = point;
      }
    }
    return closestPoint;
  }

  /// 객체의 중심이 타겟 포인트에 "충분히 가까운지" 확인합니다.
  ///
  /// [detectionBox] - 감지된 객체의 바운딩 박스
  /// [targetPoint] - `findClosestPowerPoint`에서 찾은 목표 지점
  /// [screenSize] - 화면 크기 (허용 오차 계산용)
  bool isCompositionCorrect(
    Rect detectionBox, 
    Offset? targetPoint, 
    Size screenSize
  ) {
    if (targetPoint == null || detectionBox.isEmpty) return false;

    // 허용 오차 범위 (화면 너비의 5%) <- 조정 예정
    final double tolerance = screenSize.width * 0.05; 
    final Offset boxCenter = detectionBox.center;

    // 객체 중심과 타겟 간의 거리
    final double distance = (boxCenter - targetPoint).distance;

    return distance < tolerance;
  }
}