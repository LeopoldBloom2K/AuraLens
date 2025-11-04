// CameraImage from camera package is converted to TensorImage for tflite_flutter package with ByteBuffer. image package is used for this conversion.
// lib/src/utils/image_converter.dart

import 'dart:developer';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img; // 'image' 패키지를 'img' 별칭으로 사용

/// CameraImage를 TFLite가 요구하는 형식으로 변환하는 유틸리티
class ImageConverter {
  /// CameraImage (YUV)를 TFLite 입력 형식(RGB ByteBuffer)으로 변환합니다.
  ///
  /// [cameraImage] - 카메라 스트림에서 받은 이미지
  /// [inputSize] - TFLite 모델이 요구하는 정사각형 입력 크기 (예: 300)
  /// [mean] - 모델 정규화를 위한 평균값 (예: 127.5)
  /// [std] - 모델 정규화를 위한 표준편차값 (예: 127.5)
  static Float32List convertCameraImageToTFLiteInput(
    CameraImage cameraImage,
    int inputSize,
    double mean,
    double std,
  ) {
    try {
      // 1. CameraImage(YUV)를 'image' 패키지의 Image (RGB) 객체로 변환
      final img.Image image = _convertYUV420ToImage(cameraImage);

      // 2. 모델 입력 크기에 맞게 이미지 크기 조정 (Resize)
      //    (중앙을 기준으로 정사각형으로 크롭 후 리사이즈)
      final img.Image resizedImage = img.copyResizeCropSquare(image, size: inputSize);

      // 3. 이미지를 TFLite 입력 형식(ByteBuffer)으로 변환
      return _imageToFloat32List(resizedImage, inputSize, mean, std);

    } catch (e) {
      log('ImageConverter 변환 실패: $e');
      rethrow;
    }
  }

  /// 'image' 패키지를 사용하여 YUV를 RGB로 변환
  static img.Image _convertYUV420ToImage(CameraImage cameraImage) {
    final int width = cameraImage.width;
    final int height = cameraImage.height;

    final yPlane = cameraImage.planes[0].bytes;
    final uPlane = cameraImage.planes[1].bytes;
    final vPlane = cameraImage.planes[2].bytes;

    final yuv420 = img.Image(width: width, height: height, format: img.Format.uint8, numChannels: 3); // 임시 RGB 이미지 생성

    final int uvRowStride = cameraImage.planes[1].bytesPerRow;
    final int uvPixelStride = cameraImage.planes[1].bytesPerPixel!;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yIndex = y * width + x;
        final int uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

        final int yValue = yPlane[yIndex];
        final int uValue = uPlane[uvIndex];
        final int vValue = vPlane[uvIndex];

        // YUV to RGB 변환 공식 (ITU-R BT.601)
        int r = (yValue + 1.402 * (vValue - 128)).round();
        int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).round();
        int b = (yValue + 1.772 * (uValue - 128)).round();

        // 값 범위 클리핑 (0-255)
        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);
        
        yuv420.setPixelRgb(x, y, r, g, b);
      }
    }
    return yuv420;
  }

  /// RGB `Image`를 정규화된 `Uint8List` (ByteBuffer)로 변환
  static Uint8List _imageToByteList(
      img.Image image, int inputSize, double mean, double std) {
    
    // MobileNet-SSD는 [1, 300, 300, 3] 형태의 Uint8List를 받습니다.
    final inputBytes = Uint8List(1 * inputSize * inputSize * 3);
    
    int pixelIndex = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = image.getPixel(x, y);
        
        // 정규화 (모델에 따라 다름)
        // (pixel.r - mean) / std; 
        // MobileNet-SSD (Uint8)의 경우 정규화가 필요 없을 수 있습니다.
        // TFLite Flutter는 종종 -1~1 또는 0~1 범위의 Float32List를 요구합니다.
        // 이 예제는 Uint8 모델을 가정합니다. (0-255)
        
        inputBytes[pixelIndex++] = pixel.r.toInt();
        inputBytes[pixelIndex++] = pixel.g.toInt();
        inputBytes[pixelIndex++] = pixel.b.toInt();
      }
    }
    return inputBytes;
  }

  /// RGB `Image`를 정규화된 `Float32List`로 변환 (MobileNet-SSD float 모델 기준)
  static Float32List _imageToFloat32List(
      img.Image image, int inputSize, double mean, double std) {
    
    // [1, 300, 300, 3] 형태의 Float32List
    final inputBytes = Float32List(1 * inputSize * inputSize * 3);
    
    int pixelIndex = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = image.getPixel(x, y);
        
        // 정규화 (예: -1.0 ~ 1.0 범위)
        inputBytes[pixelIndex++] = (pixel.r - mean) / std;
        inputBytes[pixelIndex++] = (pixel.g - mean) / std;
        inputBytes[pixelIndex++] = (pixel.b - mean) / std;
      }
    }
    return inputBytes;
  }
}