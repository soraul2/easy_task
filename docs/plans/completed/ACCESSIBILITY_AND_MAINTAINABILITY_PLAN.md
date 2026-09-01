# 접근성·문구·문서·파일 구조 개선 계획

기준일: 2026-09-01
상태: 완료 — 구현·회귀 검증·TestFlight 업로드 완료

배포 결과: iOS·macOS `1.0 (60)` App Store Connect 업로드 성공, 패키지 처리 시작

## 1. 목표와 범위

이 계획은 2026-09-01 구조·UI/UX 점검에서 제안한 개선 항목 중 아래 네 가지만
실행 가능한 단위로 구체화한다.

1. iPhone 접근성 글자 크기 전용 레이아웃 정리
2. 기록 카드의 `상세보기` 문구를 실제 동작에 맞게 `보드 열기`로 변경
3. 루트 `AGENTS.md`를 현재 영속 스키마 V8 기준으로 갱신
4. 다시 커진 대형 파일을 책임 단위로 점진 분리

명시적으로 제외하는 항목:

- macOS 플로팅 내비게이션과 콘텐츠 겹침 개선
- `scripts/verify-platform-builds.sh`에 Xcode UI test를 편입하는 작업
- 새 기능, 전면적인 시각 디자인 변경, 테마 재설계
- SwiftData 모델·migration·백업 형식·CloudKit 계약 변경
- bundle ID, CloudKit container, App Group, 레거시 호환 이름 변경

대상 밖인 회귀 스크립트는 수정하지 않지만, 접근성 레이아웃을 검증하기 위한 기존
Xcode UI test는 해당 단계에서 직접 실행한다.

## 2. 현재 기준점

### 2.1 확인된 문제

| 항목 | 현재 상태 | 개선 방향 |
|---|---|---|
| 접근성 글자 크기 | `accessibility5`에서 보드 전체 스크롤 fallback은 있으나 날짜 헤더, 일정 제목, 빠른 추가, 상태 선택, 작업 카드의 세로 공간과 줄바꿈이 불안정하다. | 접근성 크기에서는 수평 압축 대신 세로 배치와 자연스러운 줄바꿈을 사용한다. |
| 기록 카드 문구 | 버튼은 날짜 보드를 열고 접근성 레이블도 칸반보드 열기로 정확하지만 화면에는 `상세보기`로 표시된다. | 가시 문구를 `보드 열기`로 맞춘다. |
| 작업 지도 | `AGENTS.md`는 현재 스키마를 V6로 설명하지만 실제 container와 아키텍처 문서는 V8을 사용한다. | 구현을 기준으로 현재 스키마, 동결 스키마, 모델 표를 V8까지 갱신한다. |
| 파일 책임 | 이전 구조 정리 이후 앱 루트와 기능·코어 파일 일부가 다시 700~1,200줄 규모로 커졌다. | 공개 API와 동작을 보존하면서 역할이 분명한 타입·extension만 이동한다. |

### 2.2 대형 파일 기준선

계획 작성 시점의 주요 후보는 다음과 같다. 줄 수는 분리 우선순위를 찾는 보조 지표이며,
분리 자체의 근거는 서로 다른 책임이 한 파일에 섞였는지 여부로 판단한다.

| 파일 | 줄 수 | 주요 분리 후보 |
|---|---:|---|
| `mobile/App/PlanBaseMobileApp.swift` | 1,196 | 앱 진입, 복구 UI, 탭 루트, 동기화 UI, 테마 UI |
| `shared/Core/Services/BoundedQueryService.swift` | 1,098 | Board, Calendar, Archive, Template 등 도메인별 query |
| `desktop/App/Features/Archive/DiaryView.swift` | 993 | 조회 상태, composer, review section, attachment UI |
| `mobile/App/Features/Board/MobileBoardComponents.swift` | 935 | 헤더·입력·필터, 목록·행, 상태 제어 |
| `shared/Core/Services/CalendarWidgetSnapshot.swift` | 882 | snapshot 값, 생성 규칙, 발행 orchestration |
| `shared/Core/Services/BackupPackageRecordMerge.swift` | 876 | 모델별 merge와 참조 수렴 |
| `shared/Core/Services/BackupPackageCodec.swift` | 857 | package encode/decode와 검증 보조 로직 |
| `shared/Core/Theme/AppTheme.swift` | 848 | 토큰, preset, 저장·선택 규칙 |
| `desktop/App/AppRootView.swift` | 804 | 앱 루트, 동기화 UI, 테마 UI, 플로팅 탭 UI |
| `desktop/App/Features/Calendar/CalendarView.swift` | 714 | query host, 월 상태, 화면 orchestration |

## 3. 공통 실행 원칙

- 현재 사용자 변경을 reset하거나 덮어쓰지 않는다. 실행 단계 시작 전에 대상 파일과 겹치는
  미커밋 변경을 확인하고, 진행 중 기능 변경을 먼저 안정화한다.
- 접근성 동작 변경과 파일 이동을 같은 커밋에 섞지 않는다. 먼저 테스트로 동작을 고정한 뒤
  구조만 분리한다.
- 기본 글자 크기 레이아웃을 유지하고, 접근성 크기에서만 필요한 분기를 최소한으로 추가한다.
- 접근성 크기에서 글자를 억지로 축소하는 `minimumScaleFactor`보다 줄바꿈, 세로 배치,
  스크롤을 우선한다.
- 터치 대상은 최소 44×44pt를 유지하고 VoiceOver 레이블·힌트·읽기 순서를 보존한다.
- 기존 `EasyTaskSchemaV1`~`V7` 정의는 수정하지 않는다. 현재 V8 모델과 공개 API도
  이 작업에서는 변경하지 않는다.
- 앱 소스 파일을 추가하면 `PlanBase.xcodeproj/project.pbxproj`의 group과 target membership을
  함께 갱신한다. `shared/Core` 아래 파일은 SwiftPM 자동 탐색을 사용한다.
- 대형 파일 분리에서는 공개 타입명, 접근 수준, 저장 transaction 경계, notification 흐름을
  유지한다.
- 자연스러운 책임 경계가 없다면 줄 수를 줄이기 위한 인위적인 분리는 하지 않고 예외 사유를
  이 문서에 기록한다.

## 4. 단계별 실행 계획

### Phase 0 — 기준점과 회귀 fixture 고정

- [x] `git status --short`로 현재 사용자 변경과 네 작업 범위의 충돌 여부를 기록한다.
- [x] `swift test`와 iOS/macOS Debug build 결과를 기준점으로 남긴다.
- [x] iPhone 기본 글자 크기와 `accessibility5`에서 보드·캘린더·기록·메모 화면을 캡처한다.
- [x] 접근성 fixture에 긴 날짜, 긴 일정 제목, 긴 작업 제목, 체크리스트, 알림 기록이 모두
  표시되는지 확인한다.
- [x] 기존 `testAccessibilityTextSizeKeepsBoardActionsReachable`가 통과하는지 확인한다.

완료 조건:

- 구현 전 실패 지점과 정상 동작이 같은 fixture로 재현된다.
- 대상 파일의 기존 사용자 변경을 보존할 실행 순서가 정해진다.

### Phase 1 — iPhone 접근성 글자 크기 레이아웃

#### 1.1 공통 합격 기준

`DynamicTypeSize.accessibility1`~`.accessibility5`에서 다음 조건을 만족해야 한다.

- 핵심 제목과 상태가 수평으로 잘리거나 겹치지 않는다.
- 핵심 조작 버튼은 화면 스크롤을 통해 도달 가능하고 실제로 탭할 수 있다.
- 고정 높이 때문에 텍스트가 잘리지 않는다.
- 수평 control이 공간을 다 쓰면 세로 stack 또는 menu 표현으로 전환된다.
- VoiceOver의 레이블, 값, 힌트와 논리적 읽기 순서가 유지된다.
- 기본 글자 크기에서 기존 정보 밀도와 주요 배치가 불필요하게 달라지지 않는다.

#### 1.2 보드 레이아웃 정리

- [x] `BoardHeader`의 날짜 이동, 날짜 제목, 오늘 버튼을 접근성 크기 전용 세로 구조로
  정리한다.
- [x] 긴 날짜 제목은 두 줄 이상 자연스럽게 읽히게 하고 좌우 이동 버튼과 겹치지 않게 한다.
- [x] `BoardEventStrip`의 긴 일정 제목을 축소해서 숨기지 않고 줄바꿈 또는 독립 행으로 표시한다.
- [x] `BoardQuickAdd`는 입력창과 추가 버튼이 서로 압축되지 않도록 접근성 크기에서 세로로
  배치한다.
- [x] `BoardStatusPicker`는 현재 menu fallback을 유지하되 선택 상태와 작업 수가 잘리지 않는지
  확인한다.
- [x] `MobileTaskRow`는 제목, 메타 정보, 체크리스트 진행, 상태 변경, 편집·삭제 동작을
  접근성 크기에서 별도 행으로 재배치한다.
- [x] 보드 전체 ScrollView와 작업 목록의 중첩 스크롤이 VoiceOver·손가락 스크롤을 방해하지
  않게 유지한다.

예상 파일:

- `mobile/App/Features/Board/MobileBoardView.swift`
- `mobile/App/Features/Board/MobileBoardComponents.swift`
- `mobile/Tests/PlanBaseLaunchUITests.swift`

#### 1.3 캘린더·기록·메모 점검

- [x] 캘린더에서 월 이동, 이벤트 추가, 날짜 선택, 일정 제목이 접근성 크기에서 잘리지 않는지
  확인하고 실패한 component만 수정한다.
- [x] 기록에서 필터, 활동 요약, 날짜 카드, `보드 열기` 동작이 스크롤로 접근 가능한지 확인한다.
- [x] 메모에서 새 메모, 목록 제목, 편집 영역의 toolbar가 키보드 표시 중에도 접근 가능한지
  확인한다.
- [x] 각 화면에서 고정 frame, 한 줄 제한, 과도한 `minimumScaleFactor` 사용을 찾아 실제
  clipping이 재현되는 부분만 보정한다.

전 화면을 새로 디자인하지 않는다. 기존 UI test와 실제 캡처에서 실패가 확인된 component만
변경 대상으로 삼는다.

#### 1.4 자동·수동 검증 강화

- [x] 기존 접근성 UI test에 날짜 제목, 일정 제목, 빠른 추가, 상태 menu, 작업 편집·상태 동작의
  존재와 hittable 검증을 추가한다.
- [x] 캘린더·기록·메모는 탭 진입만 확인하지 않고 각 화면의 대표 조작 하나가 도달 가능한지
  검증한다.
- [x] 필요한 component에 안정적인 accessibility identifier를 추가한다.
- [x] iPhone 세로 방향에서 `accessibility5` reference screenshot을 다시 생성한다.
- [x] 기본 글자 크기와 `accessibility1`에서도 수동 smoke test를 수행해 분기 경계의 급격한
  layout jump가 없는지 확인한다.
- [x] UI test의 접근성 hierarchy로 보드 헤더부터 첫 작업 동작까지 읽기 순서와 중복
  identifier가 없는지 확인한다.

완료 조건:

- 접근성 글자 크기에서 긴 fixture의 핵심 텍스트가 잘리지 않는다.
- 보드·캘린더·기록·메모의 대표 동작이 UI test 또는 명시한 수동 검증을 통과한다.
- 기본 글자 크기 레이아웃에 의도하지 않은 회귀가 없다.

### Phase 2 — 기록 카드 문구를 동작과 일치시키기

- [x] `MobileArchiveRecordCard` 버튼의 가시 문구를 `상세보기`에서 `보드 열기`로 바꾼다.
- [x] 기존 `onOpenBoardDate` 호출과 날짜 변환 로직은 변경하지 않는다.
- [x] 기존 접근성 레이블과 힌트가 가시 문구와 충돌하지 않는지 확인한다.
- [x] 버튼에 날짜별 고유 identifier를 부여하고 기록 화면 UI test에서 버튼 존재와 보드 이동을
  확인한다.
- [x] 검증 후 `CROSS_PLATFORM_PARITY_PLAN.md`의 동일 미해결 항목을 완료 처리한다.

예상 파일:

- `mobile/App/Features/Archive/MobileArchiveRecordCard.swift`
- `mobile/Tests/PlanBaseLaunchUITests.swift`
- `docs/plans/active/CROSS_PLATFORM_PARITY_PLAN.md`

완료 조건:

- 화면 문구, 접근성 설명, 실제 이동 목적지가 모두 날짜 보드를 가리킨다.
- 해당 날짜의 보드가 선택된 상태로 열리는 기존 동작이 유지된다.

### Phase 3 — `AGENTS.md`를 V8 기준으로 갱신

문서 수정 전에 다음 구현 파일을 source of truth로 대조한다.

- `shared/Core/Persistence/PlanBaseContainerFactory.swift`
- `shared/Core/Persistence/EasyTaskMigrationPlan.swift`
- `shared/PlanBaseCore/Exports.swift`
- `docs/ARCHITECTURE.md`

실행 항목:

- [x] 프로젝트 요약의 현재 영속 스키마를 `EasyTaskSchemaV8`로 수정한다.
- [x] 배포 호환성 설명을 동결된 `EasyTaskSchemaV1`~`V7`과 현재 V8의 관계에 맞춘다.
- [x] `Exports.swift` 설명을 현재 re-export 공개 API 기준으로 다시 작성한다.
- [x] 데이터 모델 표에 V7의 `TaskCompletionActivity`와 V8의 `TaskProgressEvent`를 추가한다.
- [x] migration·모델 변경 체크리스트가 다음 버전 추가 방식과 V8 현재 상태를 정확히 설명하게
  수정한다.
- [x] 앱 시작, query/session, Live Activity 관련 설명에서 새 모델의 역할이 빠진 곳을 점검한다.
- [x] `README.md`, `docs/ARCHITECTURE.md`, `docs/CLOUDKIT_SYNC.md`와 상충하는 버전 표기가 없는지
  검색한다.

`docs/STRUCTURE_CLEANUP_CHECKLIST.md`는 2026-07-24 완료 당시 기록이므로 과거 실행 결과를
현재형으로 다시 쓰지 않는다. 필요한 경우 문서 상단에 역사적 스냅샷임을 명확히 하는 정도만
별도 판단한다.

완료 조건:

- `AGENTS.md`만 읽어도 현재 V8, 동결된 V1~V7, 다음 schema 추가 원칙을 혼동하지 않는다.
- 호환 식별자와 실제 코드에는 변경이 없다.
- 저장소 전체에서 현재 스키마를 V6로 잘못 설명하는 운영 문서가 남지 않는다.

### Phase 4 — 대형 파일 점진 분리

Phase 1~3의 동작·문서 변경이 검증된 뒤 구조 변경만 별도 작업으로 수행한다. 한 batch에는
가능하면 원본 파일 1개와 새 파일 2~4개만 포함하고, 매 batch 직후 해당 플랫폼 build 또는
SwiftPM test를 실행한다.

#### 4.1 앱 루트와 app chrome 분리

우선순위가 가장 높다. 앱 생명주기와 화면 component가 한 파일에 섞인 부분을 분리한다.

- [x] `mobile/App/PlanBaseMobileApp.swift`
  - 앱 진입점과 `PlanBaseLaunchEnvironment`만 루트에 남긴다.
  - persistence 복구 UI를 `Infrastructure` 파일로 이동한다.
  - `MobileAppRootView`와 tab/deep-link orchestration을 독립 파일로 이동한다.
  - CloudKit 상태 UI와 theme picker를 각각 독립 component 파일로 이동한다.
- [x] `desktop/App/AppRootView.swift`
  - `AppRootView`의 화면 orchestration을 유지한다.
  - CloudKit 상태 button/sheet를 독립 component 파일로 이동한다.
  - theme selector/picker/preset card를 독립 component 파일로 이동한다.
  - `FloatingTabBar`를 독립 app chrome 파일로 이동한다. 이 단계에서는 겹침 동작을 수정하지
    않는다.
- [x] 새 파일의 Xcode group과 iOS/macOS target membership을 확인한다.

목표는 각 루트 파일이 앱 시작과 최상위 orchestration을 빠르게 파악할 수 있는 크기와 책임을
갖게 하는 것이다. 600줄 이하는 참고 목표이며, 응집된 코드까지 강제로 분리하지 않는다.

#### 4.2 기능 UI 분리

- [x] `MobileBoardComponents.swift`를 다음 책임으로 나눈다.
  - 헤더·일정·빠른 추가
  - 상태 filter
  - 작업 목록·빈 상태
  - 작업 행·체크리스트
  - 작업 상태 control·press feedback
- [x] `DiaryView.swift`에서 root query/orchestration과 composer, review section,
  attachment presentation을 타입 경계에 맞춰 분리한다.
- [x] `CalendarView.swift`에서 bounded query host, 월 navigation 상태, 화면 composition을
  분리하되 sheet 상태와 선택 날짜의 단일 소유자는 유지한다.
- [x] 같은 파일 안의 `private` 타입을 옮기면서 접근 수준을 불필요하게 `public` 또는
  internal로 넓히지 않는다. 필요하면 작은 묶음을 같은 새 파일로 함께 이동한다.
- [x] 각 기능의 accessibility identifier와 UI 동작이 그대로 유지되는지 확인한다.

#### 4.3 공통 코어 분리

공통 코어는 UI보다 회귀 범위가 크므로 마지막에 수행한다.

- [x] `BoundedQueryService`를 Board, Calendar, Archive/Review, Template/Memo 등 도메인별
  extension 파일로 분리한다.
- [x] `CalendarWidgetSnapshot`의 값 타입·생성 규칙·store/deep-link 경계를 분리하고 기존
  publisher orchestration 파일을 유지한다.
- [x] `BackupPackageCodec`와 `BackupPackageRecordMerge`는 package 검증, encode/decode,
  모델별 merge, 참조 수렴 경계를 다시 확인한 뒤 분리한다.
- [x] `AppTheme`은 색상 token, preset 정의, 선택·저장 규칙을 분리한다.
- [x] 기존 함수 signature, DTO `Codable` 형태, merge 순서, rollback 의미를 변경하지 않는다.
- [x] core 파일 한 개를 분리할 때마다 관련 단위 테스트를 먼저 실행하고, 묶음 마지막에는
  전체 `swift test`를 실행한다.

#### 4.4 대형 파일 완료 판정

위 기준선 표의 각 파일은 다음 중 하나를 만족해야 한다.

1. 두 개 이상의 독립 책임이 확인되어 파일을 분리하고 관련 검증을 통과한다.
2. 하나의 응집된 구현이라 분리 이득보다 접근 수준 확대나 순서 의존 위험이 크면 그대로 두고,
   그 근거를 이 문서에 기록한다.

단순히 모든 파일을 특정 줄 수 아래로 만드는 것을 완료 조건으로 사용하지 않는다.

완료 조건:

- 앱 루트에서 생명주기와 최상위 화면 흐름을 바로 찾을 수 있다.
- 기능 UI는 component 이름과 파일 위치가 일치한다.
- 공통 서비스 공개 API, 저장·rollback, bounded query 의미가 그대로 유지된다.
- 새 앱 파일은 모두 올바른 Xcode target에 포함된다.
- 전체 회귀 게이트가 통과한다.

#### 4.5 실행 결과

| 기준선 파일 | 기준선 | 분리 후 원본 | 새 책임 파일 |
|---|---:|---:|---|
| `PlanBaseMobileApp.swift` | 1,196 | 206 | `MobileAppRootView` 647, 동기화 128, 테마 189, 복구 UI 39 |
| `BoundedQueryService.swift` | 1,098 | 379 | Archive 426, Calendar 120, Review 52, Support 34, Activity 107 |
| `DiaryView.swift` | 993 | 655 | Task summary 164, prompt picker 58, attachment 150 |
| `MobileBoardComponents.swift` | 935 | 176 | header 374, task list 463 |
| `CalendarWidgetSnapshot.swift` | 882 | 579 | store 113, deep link 192 |
| `BackupPackageRecordMerge.swift` | 876 | 446 | task/review merge 435 |
| `BackupPackageCodec.swift` | 857 | 639 | package models 220 |
| `AppTheme.swift` | 848 | 208 | preset 643 |
| `AppRootView.swift` | 804 | 452 | 동기화 98, 테마 207, tab bar 41 |
| `CalendarView.swift` | 714 | 549 | header 151, query host 40 |

모든 이동은 타입·extension 경계만 바꿨다. 공개 signature, SwiftData schema, backup DTO,
merge 순서, rollback, CloudKit·App Group 식별자는 변경하지 않았다.

#### 4.6 검증 및 배포 결과

- 기준점과 최종 Debug `swift test`: 331건 통과
- 최종 Release `swift test -c release`: Debug 전용 1건을 제외한 330건 통과
- `PlanBaseMobileTests`: 16건 통과
- 접근성5 대표 흐름, 기록 접힘·보드 이동, 기본 글자 크기 smoke UI test: 각 1건 통과
- 접근성5 보드·캘린더·기록·메모 reference screenshot과 접근성 hierarchy 확인
- 접근성1 보드 세로 화면을 추가 캡처해 분기 경계의 줄바꿈·조작 도달성 확인
- `git diff --check`, Xcode project·ExportOptions plist 검증 통과
- `./scripts/verify-platform-builds.sh`: iOS·macOS Debug/Release 전체 빌드 통과
- iOS·macOS 서명 archive의 앱·위젯 build 60, bundle ID와 공유 entitlement 검증 통과
- App Store Connect에 iOS·macOS `1.0 (60)` 업로드 성공, 패키지 처리 시작

## 5. 검증 명령

### 단계별 빠른 검증

```bash
git diff --check
swift test

xcodebuild build \
  -project PlanBase.xcodeproj \
  -scheme PlanBase-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

xcodebuild build \
  -project PlanBase.xcodeproj \
  -scheme PlanBase-macOS \
  -destination 'platform=macOS'
```

접근성 UI test는 전역 회귀 스크립트에 추가하지 않고 직접 실행한다.

```bash
xcodebuild test \
  -project PlanBase.xcodeproj \
  -scheme PlanBase-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PlanBaseLaunchUITests/PlanBaseLaunchUITests/testAccessibilityTextSizeKeepsBoardActionsReachable
```

Xcode project 설정이나 공통 코어 분리를 마친 마지막 단계에서는 전체 회귀 게이트를 실행한다.

```bash
./scripts/verify-platform-builds.sh
```

## 6. 권장 작업·커밋 순서

1. `test: 접근성 글자 크기 회귀 기준 보강`
2. `fix: iPhone 접근성 글자 크기 레이아웃 정리`
3. `fix: 기록 카드 보드 이동 문구 명확화`
4. `docs: AGENTS 작업 지도를 V8 기준으로 갱신`
5. `refactor: iOS 앱 루트 component 분리`
6. `refactor: macOS 앱 chrome component 분리`
7. `refactor: 대형 기능 UI 파일 분리`
8. `refactor: 대형 공통 서비스 파일 분리`
9. `test: 전체 플랫폼 회귀 검증`

각 커밋은 독립적으로 build 또는 test가 가능해야 한다. 현재 진행 중인 Live Activity·테마 변경과
겹치는 파일은 그 변경이 정리된 뒤 해당 refactor batch를 시작한다.

## 7. 전체 완료 기준

- iPhone 접근성 글자 크기에서 보드·캘린더·기록·메모 대표 흐름을 읽고 조작할 수 있다.
- 기록 카드의 가시 문구와 실제 날짜 보드 이동 동작이 일치한다.
- `AGENTS.md`가 현재 V8 구조와 모델을 정확히 설명한다.
- 기준선의 대형 파일을 모두 책임 기준으로 검토하고, 분리 또는 유지 근거를 기록한다.
- SwiftData schema, migration, 백업, CloudKit, 호환 식별자에는 기능 diff가 없다.
- `git diff --check`, 관련 UI test, `swift test`, 양 플랫폼 build, 최종 전체 회귀 게이트가
  모두 통과한다.
- 모든 항목을 완료하면 이 문서를 `docs/plans/completed/`로 이동한다.
