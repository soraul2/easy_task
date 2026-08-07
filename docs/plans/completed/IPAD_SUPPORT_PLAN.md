# PlanBase iPad 네이티브 지원 계획

기준일: 2026-08-07

상태: 완료

## 1. 목표

현재 iPhone 전용으로 배포되는 PlanBase iOS 앱을 iPhone과 iPad를 함께 지원하는
universal 앱으로 전환한다. iPad에서 iPhone 호환 창과 검은 여백 없이 전체 화면으로
실행하고, 세로·가로 방향에서 칸반·캘린더·기록·메모의 핵심 흐름을 사용할 수 있게 한다.

## 2. 현재 원인

- `PlanBase-iOS`의 Debug/Release `TARGETED_DEVICE_FAMILY`가 `1`로 설정되어 있다.
- iPad에서는 앱이 네이티브 iPad 앱이 아니라 iPhone 호환 모드로 실행된다.
- 모바일 화면은 유연한 SwiftUI 컨테이너를 주로 사용하지만 iPad 시뮬레이터 회귀 검증은 없다.

## 3. 변경 경계

- bundle ID, CloudKit container, App Group과 SwiftData schema는 변경하지 않는다.
- iPhone의 데이터 규칙, 탭 구성, 알림, 딥링크와 위젯 snapshot 흐름을 유지한다.
- 앱·위젯·모바일 테스트 타겟의 지원 기기 설정을 함께 맞춘다.
- 고정 폭을 새로 강제하지 않고 SwiftUI의 가용 공간과 size class를 기준으로 배치한다.
- iPad 전용 기능 확장보다 전체 화면 실행과 기존 기능의 안정적인 사용을 우선한다.

## 4. 실행 단계

### Phase 1 — universal 타겟 전환

- [x] iOS 앱 Debug/Release의 기기군을 `1,2`로 변경한다.
- [x] Widget Extension과 모바일 단위·UI 테스트 타겟도 `1,2`로 맞춘다.
- [x] iPad 전용 지원 방향을 Info.plist에 명시한다.
- [x] Xcode가 계산한 앱·위젯 기기군이 `1,2`인지 확인한다.

### Phase 2 — 적응형 레이아웃 점검

- [x] 최상위 탭과 네 개 주요 화면이 iPad 전체 화면을 채우는지 확인한다.
- [x] 칸반 목록과 빠른 추가, 캘린더 월 그리드, 기록 카드, 메모 목록을 세로·가로에서 확인한다.
- [x] sheet, 입력 필드, toolbar, safe area가 잘리거나 과도하게 늘어나지 않는지 확인한다.
- [x] 기존 유연한 레이아웃으로 충분한지 판정하고 불필요한 고정 폭을 추가하지 않는다.

### Phase 3 — 회귀 검증

- [x] iPad UI 테스트에 네이티브 전체 화면 판정을 추가한다.
- [x] iPad 시뮬레이터에서 launch/tab navigation smoke test를 실행한다.
- [x] iPhone 시뮬레이터 UI 테스트로 기존 모바일 동작을 확인한다.
- [x] 공통 Debug/Release 테스트와 iOS·macOS Debug/Release 빌드를 통과한다.
- [x] `git diff --check`로 프로젝트 파일과 문서 형식을 확인한다.

## 5. 완료 기준

- iPad에서 앱 창이 화면 전체를 사용하며 검은 호환 모드 여백이 없다.
- iPad 세로·가로에서 네 개 탭과 주요 생성·조회 흐름을 사용할 수 있다.
- iPhone UI와 기존 데이터·CloudKit 호환성에 회귀가 없다.
- iPad 대상 빌드와 자동화된 전체 화면 회귀 검증이 통과한다.

## 6. 완료 결과

- iPad(A16) 시뮬레이터에서 세로·가로 전체 화면 실행을 확인했다.
- iPadOS 상단 탭에서 칸반·캘린더·기록·메모 이동을 확인했다.
- 가로 모드에서 일정 추가 sheet와 입력 필드가 정상적으로 표시됐다.
- Release 산출물의 앱과 위젯 `UIDeviceFamily`가 모두 `[1, 2]`로 생성됐다.
