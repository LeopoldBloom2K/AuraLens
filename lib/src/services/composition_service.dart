// Received object's bounding box, class index, and confidence score from TFLiteService and provides methods to access these properties. (DetectionResult)
// lib/src/services/composition_service.dart

import 'dart:ui';

import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart'; // Offset, Rect, Size 사용

// 삼각형을 이용해 구도를 계산하는 로직
class TriangularComposition {
  final Offset point1;
  final Offset point2;
  final Offset point3;

  TriangularComposition({required this.point1, required this.point2, required this.point3});
}

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

  TriangularComposition? calculateTriangularCompositionTargets(
    List <DetectedObject> detections, {
      required Size imageSize,
      required Size widgetSize,
    }) {
      if (detections.length < 2) {
        return null;
      }


      // TODO: 여기서 복잡한 로직이 들어갑니다.
      // 1. 감지된 객체들의 중심점(또는 바운딩 박스)들을 가져옵니다.
      // 2. 이들 중 2~3개의 가장 중요한 객체(혹은 흥미 지점)를 선별합니다.
      //    - 예: 가장 크거나, 화면 중앙에 가깝거나, 특정 라벨(음식, 사람)을 가진 객체
      // 3. 이 객체들의 위치를 기반으로 이상적인 세 번째 지점을 계산합니다.
      //    - 예: 두 객체 사이의 중간 상단/하단 지점, 또는 화면의 특정 그리드 교차점 등
      //    - 간단한 예시: 가장 큰 두 객체의 중심점과 화면 상단 중앙 (혹은 가장 가까운 그리드 교차점)
      // 4. 이 지점들을 UI에 표시될 Offset으로 스케일링하여 반환합니다.

      // 예시: 가장 큰 두 객체의 중심점과 가상의 세 번째 점으로 삼각형을 만듭니다.
      // (이 로직은 매우 단순화된 예시이며, 실제로는 더 정교한 계산이 필요합니다.)


      detections.sort((a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(a.boundingBox.width * a.boundingBox.height));

      Offset? p1, p2, p3;

      if (detections.isNotEmpty) {
      // 가장 큰 객체의 중심점
      p1 = scaleRect(
        rect: detections[0].boundingBox,
        imageSize: imageSize,
        widgetSize: widgetSize,
      ).center;
      }

      if (detections.length >= 2) {
      // 두 번째로 큰 객체의 중심점
      p2 = scaleRect(
        rect: detections[1].boundingBox,
        imageSize: imageSize,
        widgetSize: widgetSize,
      ).center;
      }

      // 세 번째 지점: (임시) 화면 상단 중앙
      if (p1 != null && p2 != null) {
        p3 = Offset(widgetSize.width / 2, widgetSize.height / 4); // 상단 1/4 지점
      }

      if (p1 != null && p2 != null && p3 != null) {
        return TriangularComposition(point1: p1, point2: p2, point3: p3);
      }

      return null;
      }

    
}

