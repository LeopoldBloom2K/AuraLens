// lib/src/utils/image_converter.dart

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

class ImageConverter {
  /// CameraImage(YUV420)를 TFLite 모델 입력 형태인 [1][3][224][224] 배열로 변환합니다.
  static List<List<List<List<double>>>> convertCameraImageToModelInput(CameraImage image) {
    // 1. 카메라 이미지를 다루기 쉬운 RGB 형태(img.Image)로 변환
    img.Image rgbImage = _convertYUV420ToImage(image);

    // 2. 모델 입력 크기인 224x224로 리사이징
    img.Image resizedImage = img.copyResize(rgbImage, width: 224, height: 224);

    // 3. 모델이 기대하는 [1, 224, 224, 3] 형태의 4차원 배열 생성 (Batch, Channel, Height, Width)
    // PyTorch에서 ONNX로 변환했기 때문에 채널(RGB)이 먼저 옵니다.
    List<List<List<List<double>>>> input = [
      List.generate(224, (y) => 
        List.generate(224, (x) {
          final pixel = resizedImage.getPixel(x, y);
          
            // 한 픽셀당 [R, G, B] 순서로 정규화된 값을 리스트로 묶어줍니다.
          return [
            ((pixel.r / 255.0) - 0.485) / 0.229, // R
            ((pixel.g / 255.0) - 0.456) / 0.224, // G
            ((pixel.b / 255.0) - 0.406) / 0.225, // B
          ];
        })
      )
    ];

    return input;
  }

  /// YUV420 포맷의 CameraImage를 img.Image 객체로 변환하는 헬퍼 메서드
  static img.Image _convertYUV420ToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel!;

    final img.Image rgbImage = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      int pY = y * image.planes[0].bytesPerRow;
      int pUV = (y >> 1) * uvRowStride;

      for (int x = 0; x < width; x++) {
        final int uvOffset = pUV + ((x >> 1) * uvPixelStride);
        
        // YUV 값 추출
        final int yValue = image.planes[0].bytes[pY];
        final int uValue = image.planes[1].bytes[uvOffset];
        final int vValue = image.planes[2].bytes[uvOffset];

        // YUV를 RGB로 변환 (공식 적용)
        int r = (yValue + 1.402 * (vValue - 128)).round().clamp(0, 255);
        int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).round().clamp(0, 255);
        int b = (yValue + 1.772 * (uValue - 128)).round().clamp(0, 255);

        // 픽셀 설정
        rgbImage.setPixelRgb(x, y, r, g, b);
        pY++;
      }
    }
    return rgbImage;
  }
}