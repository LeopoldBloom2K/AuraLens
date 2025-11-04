# AuraLens 📸✨

`AuraLens`라는 이름에 맞춰 프로젝트의 뼈대를 잡아보겠습니다.

프로젝트를 시작할 때 이 세 가지(README, 기술 스택, 디렉토리 구조)를 먼저 정의하면, 개발 과정이 훨씬 체계적이고 깔끔해집니다.

-----

### 1\. `README.md` 템플릿

리포지토리의 '얼굴'입니다. 다른 사람들이 이 프로젝트를 이해하고 사용할 수 있도록 돕습니다. (이 내용을 복사해서 `README.md` 파일에 붙여넣으세요.)

> ```markdown
> # AuraLens 📸✨
> ```

> 실시간 AI 구도 어시스턴트: "황금 비율"과 "3분할 구도"를 위한 Flutter 카메라 앱

> 
>
> -----

> ## 💡 프로젝트 소개 (About)

> **AuraLens**는 사용자가 '감성 있는' 사진을 찍을 수 있도록 실시간으로 구도를 제안하는 AI 카메라 애플리케이션입니다.

> 카메라가 비추는 피사체(인물, 사물 등)를 실시간으로 분석하여, 가장 안정적이고 미학적인 구도(3분할, 황금 비율 등)를 잡을 수 있도록 화면 위에 동적인 가이드를 제공합니다.

> 이 프로젝트는 Flutter와 On-Device AI (TensorFlow Lite)를 활용하여 개발되었습니다.

> > 
>
> ## 🚀 주요 기능

>   * **실시간 피사체 감지:** On-Device TFLite 모델(예: MobileNet-SSD)을 사용한 빠른 객체 탐지.
>   * **동적 구도 가이드:**
>       * **3분할 (Rule of Thirds):** 피사체를 3x3 그리드의 '파워 포인트'에 맞추도록 유도.
>       * **황금 비율 (Golden Ratio):** 황금 나선 또는 황금 사각형에 피사체를 배치하도록 가이드.
>   * **시각적 피드백:** 사용자가 가이드(타겟)에 피사체를 맞추면 색상이 변하는 등 직관적인 UI 제공.
>   * **크로스 플랫폼:** 단일 코드 베이스로 iOS와 Android 모두 지원 (Flutter).

> ## 🛠️ 기술 스택 (Tech Stack)

>   * **프레임워크:** Flutter (Cross-platform UI)
>   * **언어:** Dart
>   * **AI 모델:** TensorFlow Lite (On-Device, MobileNet-SSD 등)
>   * **주요 라이브러리:**
>       * `camera`: 실시간 카메라 프리뷰 및 이미지 스트림
>       * `tflite_flutter`: Flutter에서 TFLite 모델 실행
>       * `permission_handler`: 카메라/저장소 권한 관리
>       * `provider` (또는 `flutter_bloc`): 상태 관리
>       * `image`: 이미지 포맷 변환 (CameraImage -\> TFLite Input)

> ## 🏁 시작하기 (Getting Started)

> ### 1\. 전제 조건

>   * [의심스러운 링크 삭제됨] 설치
>   * TFLite 모델 파일 준비 (예: `mobilenet_ssd.tflite` 및 `labels.txt`)
>       * 준비된 모델 파일을 `/assets/models/` 디렉토리에 위치시키세요.

> ### 2\. 설치 및 실행

> ```bash
> # 1. 리포지토리 클론
> git clone [@LeopoldBloom2K](https://github.com/LeopoldBloom2K/AuraLens)
> cd AuraLens
> ```

> # 2\. Flutter 패키지 설치
>
> flutter pub get

> # 3\. (iOS만) CocoaPods 설치
>
> cd ios
> pod install
> cd ..

> # 4\. 앱 실행
>
> flutter run
>
> ````
> 
> ## 📜 라이선스 (License)

> 이 프로젝트의 코드는 [MIT License](LICENSE)를 따릅니다.

> **중요:** 이 앱에서 사용하는 사전 학습된 AI 모델(예: MobileNet-SSD v2)은 별도의 라이선스(예: Apache 2.0)를 따릅니다. 자세한 내용은 앱 내 '오픈소스 라이선스' 정보를 확인하세요.

> ```
> ```
> ````

-----

### 2\. 핵심 기술 라이브러리 (pubspec.yaml)

`pubspec.yaml` 파일의 `dependencies:` 섹션에 추가해야 할 핵심 패키지들입니다.

  * **`camera`**: Flutter 공식 카메라 플러그인. 카메라 하드웨어 제어, 실시간 미리보기, 이미지 스트림(AI 분석용)을 담당합니다.
  * **`tflite_flutter`**: Flutter에서 TensorFlow Lite 모델 파일을 로드하고 추론(inference)을 실행하는 핵심 브릿지입니다.
  * **`permission_handler`**: 앱 시작 시 사용자에게 카메라, 마이크, 저장소 접근 권한을 요청하는 필수 패키지입니다.
  * **`provider`** (또는 `flutter_bloc`): 상태 관리 솔루션. 카메라의 상태, AI 분석 결과, UI 가이드의 위치 등을 앱 전반에서 효율적으로 관리하기 위해 필수적입니다. (`provider`가 초기에 배우기 더 쉽습니다.)
  * **`image`**: 카메라 스트림에서 받은 `CameraImage` 객체(YUV 형식)를 TFLite 모델이 요구하는 `RGB` 형식의 `ByteBuffer`로 변환하는 데 매우 유용한 라이브러리입니다.
  * **`gallery_saver`** (또는 `image_gallery_saver`): 촬영한 사진을 사용자의 갤러리(앨범)에 저장할 때 사용합니다.
  * **`path_provider`**: 앱의 내부 저장소 경로를 찾는 데 사용됩니다.

-----

### 3\. 디렉토리 구조

Flutter 프로젝트가 커질수록 체계적인 구조가 중요합니다. '관심사 분리(Separation of Concerns)' 원칙을 따르는 확장 가능한 구조를 제안합니다.

```
AuraLens/
├── android/            # Android 네이티브 코드
├── ios/                # iOS 네이티브 코드
├── lib/                # 모든 Dart 코드가 위치하는 메인 폴더
│   ├── main.dart         # 앱의 시작점 (MaterialApp, Provider 설정 등)
│   │
│   ├── src/              # 핵심 소스 코드
│   │   ├── app.dart        # MaterialApp 위젯 (테마, 라우팅 정의)
│   │   │
│   │   ├── screens/        # 개별 화면 (UI + 비즈니스 로직)
│   │   │   ├── camera/
│   │   │   │   ├── camera_screen.dart   # 카메라 UI (Stack, CameraPreview)
│   │   │   │   ├── camera_view_model.dart # (선택) Provider/Bloc 로직
│   │   │   │   └── widgets/
│   │   │   │       └── composition_overlay_painter.dart # 3x3, 황금비율 그리는 CustomPaint
│   │   │   │
│   │   │   └── settings/
│   │   │       └── settings_screen.dart # 설정 및 라이선스 고지 화면
│   │   │
│   │   ├── services/       # 백그라운드 로직 (UI와 분리)
│   │   │   ├── tflite_service.dart      # TFLite 모델 로드 및 추론(runModel) 담당
│   │   │   ├── camera_service.dart      # CameraController 초기화, 스트림 관리
│   │   │   └── composition_service.dart # AI결과(좌표) -> 구도(타겟) 계산 로직
│   │   │
│   │   ├── models/         # 데이터 클래스
│   │   │   └── detection_result.dart  # TFLite 추론 결과를 담을 Dart 클래스
│   │   │
│   │   └── utils/          # 공용 헬퍼 함수
│   │       ├── image_converter.dart   # CameraImage -> TFLite input 변환
│   │       └── permissions.dart       # 권한 요청 로직
│   │
│   └── global/           # 전역 상수, 스타일 등
│       └── app_styles.dart
│
├── assets/             # 정적 파일
│   ├── models/           # AI 모델 파일
│   │   ├── mobilenet_ssd.tflite
│   │   └── labels.txt
│   ├── licenses/         # AI 모델 라이선스 텍스트 파일
│   │   └── APACHE_LICENSE_2.0.txt
│   └── images/           # 앱 아이콘, 로고 등
│
├── pubspec.yaml        # 프로젝트 의존성 및 assets 등록 (!!중요!!)
└── README.md           # (방금 위에서 만든 파일)
```
