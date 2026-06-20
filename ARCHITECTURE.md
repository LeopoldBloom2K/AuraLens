# AuraLens — 프로젝트 구조 문서

> AI 카메라 구도 조정 어시스턴트  
> Flutter (Android/Web) · ONNX Runtime · Google ML Kit

---

## 전체 아키텍처 요약

```
┌─────────────────────────────────────────────────────┐
│                     main.dart                        │
│  InferenceService.initialize()  ←── 앱 시작 1회      │
│  Provider 트리 구성                                   │
└──────────────────────┬──────────────────────────────┘
                       │ Provider
          ┌────────────┼────────────┐
          ▼            ▼            ▼
   CameraService  InferenceService  CameraViewModel
   (카메라 HW)    (ONNX 추론)       (비즈니스 로직)
          │                              │
          │ 카메라 프레임 (YUV420)        │ notifyListeners()
          └──────────────────────────────┘
                       │
               CameraScreen (UI)
                       │
          ┌────────────┴────────────┐
          ▼                         ▼
   CameraPreview              CompositionOverlayPainter
   (라이브 뷰)                 (그리드 + AI 오버레이)
```

---

## 파일별 설명

### `lib/main.dart`

앱의 진입점. 다음 네 가지를 순서대로 처리합니다.

1. **게이트 프로브** — `ModelGate.probe()` 를 가장 먼저 호출해 모델 파일 존재 여부를 확인합니다.
2. **ONNX 모델 로드** — `InferenceService.initialize()` 를 호출합니다. 게이트가 열려있을 때만 실제 ORT 세션을 엽니다.
3. **화면 방향 고정** — 세로 모드(`portraitUp`) 고정.
4. **Provider 트리 구성** — `InferenceService`, `CameraService`, `CameraViewModel` 세 개를 주입합니다.

```
Provider<InferenceService>          ← 싱글톤, 모델 수명 = 앱 수명
ChangeNotifierProvider<CameraService>
ChangeNotifierProvider<CameraViewModel>
```

---

### `lib/src/app.dart`

`MaterialApp` 을 구성하는 최소 래퍼. 테마(다크/블랙), `CameraScreen` 을 홈으로 설정합니다. 로직 없음.

---

### `lib/src/models/camera_settings.dart`

앱 전체에서 공유하는 열거형 3개를 정의합니다.

| 열거형 | 값 | 역할 |
|--------|-----|------|
| `CameraResolution` | low / medium / high / max | 카메라 해상도 선택 |
| `SceneCategory` | unknown / food / person / scenery | AI 추론 결과 |
| `CameraRatio` | 1:1 / 4:3 / 16:9 | 프리뷰 화면 비율 |

`SceneCategory` 는 AI 파이프라인의 출력 타입이자, UI 렌더링 분기의 기준입니다.

---

### `lib/src/services/model_gate.dart`

앱 시작 시 모델 파일 존재 여부를 단 한 번 확인하고, 이후 `InferenceService` 가 이 상태를 참조해 초기화를 결정합니다.

```
ModelGate.probe()                          ← main() 에서 최초 1회 호출
  │
  ├─ rootBundle.load('assets/models/auralens_model.onnx') 성공
  │    → _isReady = true
  │    → 로그: 🔓 AI 모드
  │
  └─ FlutterError (파일 없음)
       → _isReady = false
       → 로그: 🔒 카메라 전용 모드

ModelGate.isReady                          ← InferenceService 에서 참조
```

**설계 의도:** 모델 파일 부재를 예외(Exception)가 아닌 명시적 상태로 다룹니다. 파일을 추가하면 코드 수정 없이 다음 실행부터 게이트가 열립니다.

---

### `lib/src/services/camera_service.dart`

Flutter `camera` 패키지를 감싼 ChangeNotifier 서비스. 카메라 하드웨어와의 접점입니다.

| 메서드 | 설명 |
|--------|------|
| `initializeCamera()` | 기기에서 카메라 목록을 조회하고 YUV420 포맷으로 컨트롤러를 초기화합니다 |
| `startImageStream(callback)` | 매 프레임을 콜백으로 흘려보내는 스트림을 시작합니다 |
| `stopImageStream()` | 스트림을 정지합니다 (갤러리 진입 시 호출) |
| `takePicture()` | 정사진을 촬영해 `XFile` 로 반환합니다 |
| `switchCamera()` | 전/후면 카메라를 전환합니다 |
| `updateCameraResolution()` | 해상도 변경 시 컨트롤러를 재초기화합니다 |

**포인트:** `imageFormatGroup: ImageFormatGroup.yuv420` 으로 고정되어 있어, `ImageConverter` 가 항상 YUV420 입력을 받는다고 가정할 수 있습니다.

---

### `lib/src/services/inference_service.dart`

ONNX Runtime 기반 장면 분류 서비스. `ModelGate` 를 확인한 뒤 ORT 세션을 엽니다.

```
initialize()
  ├─ ModelGate.isReady == false → 즉시 반환 (초기화 건너뜀)
  └─ ModelGate.isReady == true
       └─ OrtSession.fromBuffer() 로 모델 로드
            ├─ 성공 → _isInitialized = true
            └─ 실패 → _isInitialized = false (예상치 못한 오류)

classifyScene(Float32List inputData) → Future<SceneCategory>
  ├─ _isInitialized == false → SceneCategory.unknown 즉시 반환
  └─ 추론 실행
       입력: [1, 3, 224, 224] NCHW Float32List
       출력: [[p_person, p_food, p_scenery]]
       argmax → SceneCategory
```

리소스 관리: `inputTensor`, `outputs`, `runOptions` 를 `finally` 블록에서 `.release()` 합니다.

---

### `lib/src/services/composition_service.dart`

AI 추론 결과(좌표)를 구도 계산 로직으로 변환하는 서비스입니다. 현재 두 가지 기능이 구현되어 있습니다.

**`findClosestPowerPoint(detectionBox, screenSize)`**  
바운딩 박스 중심에서 3분할 4개 교차점(파워 포인트) 중 가장 가까운 점을 반환합니다.

**`calculateTriangularCompositionTargets(detections, ...)`**  
감지된 객체 2개 이상을 받아 삼각형 구도의 세 꼭짓점 `TriangularComposition` 을 반환합니다. 가장 큰 두 객체의 중심 + 화면 상단 1/4 지점으로 구성됩니다(향후 고도화 예정).

> **현재 상태:** `CompositionService` 의 메서드들은 구현은 완료되었으나 `CameraViewModel` 에 아직 연결되지 않았습니다. `CompositionOverlayPainter` 가 직접 장면 카테고리로 분기해 고정 가이드를 그리는 방식으로 동작 중입니다.

---

### `lib/src/utils/image_converter.dart`

카메라 프레임을 ONNX 모델 입력으로 변환합니다. `compute()` 로 별도 isolate 에서 실행됩니다.

```
CameraImage (YUV420)
  │
  ▼ _convertYUV420ToImage()
img.Image (RGB, 원본 해상도)
  │
  ▼ img.copyResize(224, 224)
img.Image (RGB, 224×224)
  │
  ▼ NCHW 변환 + ImageNet 정규화
Float32List [3 × 224 × 224]
  mean=[0.485, 0.456, 0.406]
  std =[0.229, 0.224, 0.225]
```

출력 메모리 레이아웃:
```
[0 .. 224×224-1]      → R 채널 전체
[224×224 .. 2×224×224-1] → G 채널 전체
[2×224×224 .. 3×224×224-1] → B 채널 전체
```

---

### `lib/src/utils/coordinate_scaler.dart`

ML Kit 이 반환하는 이미지 좌표계(픽셀)를 Flutter 위젯 좌표계(dp)로 변환하는 유틸 함수입니다.

`scaleRect()` 는 `Contain` 모드(레터박스)를 기준으로 스케일 팩터와 오프셋을 계산합니다. `CompositionService.calculateTriangularCompositionTargets()` 에서 사용됩니다.

---

### `lib/src/screens/camera/camera_view_model.dart`

카메라 화면의 비즈니스 로직 전담 ChangeNotifier. `CameraService` 와 `InferenceService` 를 조율합니다.

**AI 추론 루프 (`_startModelInference`)**

```
CameraService.startImageStream()
  │ 매 프레임 (YUV420)
  ▼
500ms 쿨다운 체크 (너무 빠른 프레임 스킵)
  │
  ▼
compute(ImageConverter.convertCameraImageToModelInput, frame)
  │ 별도 isolate
  ▼
InferenceService.classifyScene(Float32List)
  │
  ▼
_sceneHistory 에 결과 추가 (최대 7개 보관)
  │
  ▼
다수결 투표 → stableScene
  │
  ▼
_currentScene 변경 시 notifyListeners()
```

**주요 상태값**

| 필드 | 타입 | 역할 |
|------|------|------|
| `_currentScene` | `SceneCategory` | 안정화된 현재 장면 |
| `_isAiAssistEnabled` | `bool` | AI 어시스트 토글 |
| `_isGridEnabled` | `bool` | 그리드 표시 토글 |
| `_currentRatio` | `CameraRatio` | 화면 비율 |
| `_sessionPhotos` | `List<XFile>` | 세션 내 촬영 사진 목록 |

**AI 일시정지/재개:** 갤러리 진입 시 `pauseInference()` → 이미지 스트림 정지, 복귀 시 `resumeInference()` → 스트림 재시작.

---

### `lib/src/screens/camera/camera_screen.dart`

카메라 화면 UI. `StatelessWidget(CameraScreen)` → `StatefulWidget(CameraView)` 구조입니다.

**레이어 구성 (Stack)**

```
1. CameraPreview (AspectRatio 클리핑)
2. CompositionOverlayPainter (CustomPaint)
3. 상단 컨트롤 바 (비율 / 그리드 / AI 토글 / 설정)
4. 하단 컨트롤 바 (갤러리 썸네일 / 셔터 / 전환)
```

**기기 기울기 대응:** `sensors_plus` 의 `accelerometerEventStream()` 으로 X/Y 가속도를 감지해 아이콘을 `AnimatedRotation` 으로 회전시킵니다(가로 모드 물리 회전 없이 아이콘만 회전).

---

### `lib/src/screens/camera/widgets/composition_overlay_painter.dart`

`CustomPainter` 구현체. 카메라 프리뷰 위에 투명하게 덮이는 구도 안내 오버레이를 그립니다.

**렌더링 분기**

```
isGridEnabled == true
  └─ _drawGrid() : 흰색 3분할 격자선

isAiAssistEnabled == true
  ├─ SceneCategory.food    → _drawFoodGuide()    : 황색 십자선 (중앙 포커스)
  ├─ SceneCategory.person  → _drawPersonGuide()  : 청색 원 4개 (3분할 교차점)
  ├─ SceneCategory.scenery → _drawSceneryGuide() : 녹색 수평선 (하단 2/3 지점)
  └─ SceneCategory.unknown → 아무것도 그리지 않음
```

모든 선/원은 검정 외곽선(outline) + 컬러 메인선 2중 구조로 가시성을 확보합니다.

`shouldRepaint()` 는 `currentScene`, `isGridEnabled`, `isAiAssistEnabled`, `widgetSize` 변경 시에만 재드로우합니다.

---

### `lib/src/screens/settings/settings_screen.dart`

설정 화면. `CameraViewModel` 에 직접 접근해 상태를 변경합니다.

| 설정 항목 | 연결 메서드 |
|----------|------------|
| 그리드 표시 (스위치) | `viewModel.toggleGrid()` |
| AI 어시스턴트 (스위치) | `viewModel.toggleAiAssist()` |
| 사진 해상도 (다이얼로그) | `viewModel.setCameraResolution()` |

---

### `lib/src/screens/camera/gallery_screen.dart`

세션 내 촬영 사진 뷰어. `CameraViewModel.sessionPhotos` 리스트를 `PageView` 로 표시합니다.

- **핀치 줌:** `InteractiveViewer` (1x–4x)
- **공유:** `share_plus`
- **삭제:** `viewModel.deleteSessionPhoto()` → 임시 파일 물리 삭제 + 목록 제거

사진이 모두 삭제되면 `postFrameCallback` 으로 자동 뒤로가기합니다.

---

## End-to-End 흐름

### AI 모드 (모델 파일 있음)

```
① assets/models/auralens_model.onnx 배치
         │
         ▼
② 앱 시작 → ModelGate.probe()
         │  파일 확인 성공 → _isReady = true
         │  로그: 🔓 AI 모드
         ▼
③ InferenceService.initialize()
         │  ModelGate.isReady == true → OrtSession 로드
         │  _isInitialized = true
         ▼
④ CameraService.initializeCamera()
         │  YUV420 스트림 준비
         ▼
⑤ CameraViewModel._startModelInference()
         │
         │  [500ms마다]
         ▼
⑥ compute(ImageConverter.convertCameraImageToModelInput, frame)
         │  YUV420 → RGB → 224×224 → NCHW Float32List
         │  (별도 isolate, UI 블로킹 없음)
         ▼
⑦ InferenceService.classifyScene(Float32List)
         │  ONNX 추론: [1,3,224,224] → [[p0, p1, p2]]
         │  argmax → SceneCategory
         ▼
⑧ _sceneHistory 에 누적 (최대 7프레임 다수결)
         │  흔들림/오탐 방지용 안정화
         ▼
⑨ _currentScene 업데이트 → notifyListeners()
         ▼
⑩ CompositionOverlayPainter.paint()
         │
         ├─ food    → 황색 십자선
         ├─ person  → 청색 원 (3분할 교차점)
         └─ scenery → 녹색 수평선
```

### 카메라 전용 모드 (모델 파일 없음)

```
② 앱 시작 → ModelGate.probe()
         │  FlutterError (파일 없음) → _isReady = false
         │  로그: 🔒 카메라 전용 모드
         ▼
③ InferenceService.initialize()
         │  ModelGate.isReady == false → 즉시 반환
         │  _isInitialized = false
         ▼
⑦ classifyScene() → SceneCategory.unknown 즉시 반환
         ▼
⑩ CompositionOverlayPainter: unknown 분기 = 아무것도 그리지 않음
         │
         └─ 그리드·셔터·갤러리 등 카메라 기능은 모두 정상 동작
```

---

## 모델 연결 체크리스트

모델 학습·변환이 완료된 후 아래 순서대로 진행합니다.

### 1단계 — PyTorch 모델 Export

```python
# 필수 export 설정
torch.onnx.export(
    model,
    dummy_input,                      # shape: (1, 3, 224, 224)
    "auralens_model.onnx",
    input_names=["input"],            # ← 반드시 'input' 으로 지정
    output_names=["output"],
    opset_version=11,                 # ONNX Runtime 호환 버전
    dynamic_axes={"input": {0: "batch_size"}},
)
```

- [ ] `input_names=['input']` 지정 확인 (`inference_service.dart` 의 `{'input': inputTensor}` 키와 일치해야 함)
- [ ] 입력 shape `(1, 3, 224, 224)` NCHW 확인
- [ ] 출력 shape `(1, 3)` — 3개 클래스 확률값(softmax 또는 logits) 확인
- [ ] `opset_version=11` 이상 확인

### 2단계 — 클래스 순서 확인

앱 내 클래스 인덱스 매핑 (`inference_service.dart` line 60):

| 인덱스 | SceneCategory |
|--------|---------------|
| 0 | `person` |
| 1 | `food` |
| 2 | `scenery` |

- [ ] 학습 시 클래스 순서가 위 표와 일치하는지 확인
- [ ] 순서가 다르면 `inference_service.dart` 의 `switch(maxIndex)` 블록만 수정

### 3단계 — 파일 배치

```
AuraLens/
└── assets/
    └── models/
        └── auralens_model.onnx   ← 여기에 복사
```

- [ ] `assets/models/auralens_model.onnx` 파일 복사 완료
- [ ] `pubspec.yaml` 의 `assets/models/` 디렉터리 등록 확인 (이미 등록됨, 추가 수정 불필요)

### 4단계 — 빌드 및 로그 확인

- [ ] `flutter pub get` 실행
- [ ] 앱 실행 후 디버그 콘솔에서 아래 로그 확인

```
🔓 ModelGate: assets/models/auralens_model.onnx 확인됨 → AI 모드
✅ ONNX 모델 로드 성공
```

- [ ] 카메라 화면에서 AI 어시스트 아이콘(insights) 활성화 후 오버레이 등장 확인
- [ ] 음식 / 인물 / 풍경 장면별 오버레이 색상 및 형태 확인

### 트러블슈팅

| 증상 | 원인 | 조치 |
|------|------|------|
| `🔒 카메라 전용 모드` 로그 | 파일 경로 오류 또는 파일 미복사 | `assets/models/auralens_model.onnx` 위치 재확인 |
| `❌ ONNX 모델 로드 실패` 로그 | opset 불일치 또는 파일 손상 | `opset_version` 재확인 후 재export |
| 오버레이가 항상 나타나지 않음 | 클래스 순서 불일치로 `unknown` 반환 | 학습 레이블 순서와 `switch` 블록 비교 |
| 추론 결과가 불안정함 | 정규화 값 불일치 | ImageNet mean/std `[0.485,0.456,0.406]` / `[0.229,0.224,0.225]` 확인 |

---

## 패키지 의존성 요약

| 패키지 | 역할 |
|--------|------|
| `camera` | 카메라 프리뷰 및 YUV420 스트림 |
| `onnxruntime` | ONNX 모델 추론 엔진 |
| `google_mlkit_object_detection` | 객체 감지 (CompositionService 좌표 계산용) |
| `image` | YUV→RGB 변환, 리사이징 |
| `provider` | 상태 관리 (DI 컨테이너) |
| `sensors_plus` | 가속도계 (아이콘 회전) |
| `share_plus` | 사진 공유 |
| `gallery_saver_plus` | 갤러리 저장 |
| `permission_handler` | 카메라·저장소 권한 |
