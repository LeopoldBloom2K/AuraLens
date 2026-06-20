// lib/src/utils/image_converter.dart

import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

class ImageConverter {
  /// CameraImage(YUV420) → Float32List [1, 3, 224, 224] (NCHW)
  /// PyTorch/ONNX 모델의 채널-우선(Channel-First) 입력 형식에 맞춥니다.
  /// ImageNet 정규화: mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]
  static Float32List convertCameraImageToModelInput(CameraImage image) {
    final img.Image rgbImage = _convertYUV420ToImage(image);
    final img.Image resized = img.copyResize(rgbImage, width: 224, height: 224);

    // NCHW 평탄화: R채널 전체 → G채널 전체 → B채널 전체
    final Float32List input = Float32List(3 * 224 * 224);
    const int planeSize = 224 * 224;

    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixel = resized.getPixel(x, y);
        final int idx = y * 224 + x;
        input[idx]                = (pixel.r / 255.0 - 0.485) / 0.229;
        input[planeSize + idx]    = (pixel.g / 255.0 - 0.456) / 0.224;
        input[planeSize * 2 + idx] = (pixel.b / 255.0 - 0.406) / 0.225;
      }
    }

    return input;
  }

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

        final int yValue = image.planes[0].bytes[pY];
        final int uValue = image.planes[1].bytes[uvOffset];
        final int vValue = image.planes[2].bytes[uvOffset];

        final int r = (yValue + 1.402 * (vValue - 128)).round().clamp(0, 255);
        final int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).round().clamp(0, 255);
        final int b = (yValue + 1.772 * (uValue - 128)).round().clamp(0, 255);

        rgbImage.setPixelRgb(x, y, r, g, b);
        pY++;
      }
    }
    return rgbImage;
  }
}
