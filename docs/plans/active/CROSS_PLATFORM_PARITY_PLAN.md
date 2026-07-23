# PlanBase macOS·iPhone 기능 정합성 개선 계획

기준일: 2026-07-24

## 1. 목표

macOS와 iPhone 앱이 같은 SwiftData·CloudKit 데이터를 같은 의미로 표시하고,
한 플랫폼에서 만든 값을 다른 플랫폼에서도 손실 없이 확인·수정할 수 있게 한다.
화면 배치와 입력 방식은 각 플랫폼에 맞게 유지하며 외형을 강제로 동일하게 만들지 않는다.

우선순위는 다음과 같다.

1. 같은 데이터가 플랫폼마다 다르게 보이는 문제를 제거한다.
2. 한 플랫폼에서 만든 값을 다른 플랫폼에서 수정할 수 없는 왕복 편집 결손을 제거한다.
3. 삭제·복원처럼 데이터 수명주기에 영향을 주는 기능을 양 플랫폼에서 같은 규칙으로 제공한다.
4. 위젯, 키보드, 드래그 앤 드롭처럼 플랫폼에 종속된 UX는 의도된 차이로 유지한다.

## 2. 변경 경계

- `EasyTaskSchemaV1`~`V6`와 `EasyTaskMigrationPlan`을 변경하지 않는다.
- bundle ID, CloudKit container, App Group, 백업 UTI와 확장자를 변경하지 않는다.
- 기존 `PlanBaseCore` 서비스와 `PersistenceCommandService.perform` 경계를 재사용한다.
- CloudKit 중복 수렴, `instanceID`, `supersededAt` 규칙을 우회하지 않는다.
- 백업 가져오기는 교체가 아니라 기존 병합·검증·rollback 정책을 그대로 사용한다.
- 위젯은 계속 App Group snapshot만 읽고 SwiftData 또는 CloudKit을 직접 열지 않는다.
- 현재 진행 중인 모바일 보드·캘린더·위젯 디자인 변경을 먼저 독립적으로 정리한 뒤
  clean `main`에서 정합성 작업을 시작한다.

## 3. 현재 판정

### 공통 기반이 이미 일치하는 영역

- 칸반, 캘린더, 기록, 메모의 네 가지 최상위 기능
- 현재 SwiftData schema와 CloudKit private database
- Task, CalendarEvent, TemplatePlacement, DailyReview, Memo의 모델 의미
- 데이터 무결성 수렴, lazy archive, 백업 codec과 병합 규칙
- 템플릿 생성·편집·적용과 메모 자동 저장

### 유지할 플랫폼 전용 차이

| macOS | iPhone |
|---|---|
| 세 개 칸반 열 동시 표시 | 선택한 상태 중심의 단일 목록 |
| 오늘 보드와 이월함을 분리 | 오늘 보드에 이월 작업도 함께 표시 |
| 마우스 드래그 앤 드롭 | 터치·스와이프·상태 슬라이더 |
| 키보드 단축키와 파일 패널 | 홈/잠금 화면 위젯과 딥링크 |
| 넓은 화면의 목록·편집기 동시 표시 | NavigationStack 기반 단계 이동 |

이 항목은 기능 결손으로 취급하지 않는다. 공통 Rules/Service의 결과만 같으면
플랫폼별 화면 구성은 유지한다.

### 해결할 정합성 차이

1. 모바일 일정 메모를 macOS에서 생성·수정할 수 없다.
2. iPhone 이월함의 후보 기준일이 선택한 보드 날짜를 따라가지만 모든 실행 동작은
   오늘을 대상으로 한다.
3. iPhone은 날짜별 작업·이벤트·템플릿 배치와 배치 삭제를 제공하지만 macOS는
   배치 이후의 수명주기 UI가 없다.
4. 백업 package 가져오기·내보내기가 macOS에만 있다.
5. 회고 작성 프롬프트는 iPhone에만 있다.
6. macOS 캘린더는 공통 이벤트 배치 엔진을 사용하지 않아 CloudKit 중복 대표 선택과
   숨겨진 이벤트 개수 표시가 모바일·위젯과 다르다.

### 의도된 정책으로 유지할 차이

Task의 `reminderAt`은 두 앱이 공유하지만 실제 로컬 알림 예약과 편집은 현재
iPhone 책임이다. 기존 알림 계획에서 macOS 읽기 전용을 명시적으로 선택했으므로
이번 정합성 작업에서 바로 macOS 알림 예약을 추가하지 않는다.

- macOS는 동기화된 알림 시각과 완료 경고를 계속 표시한다.
- macOS UI에는 알림이 iPhone에서 설정·실행된다는 설명을 명확히 표시한다.
- macOS 로컬 알림은 중복 알림 방지를 위한 기기별 opt-in 정책을 먼저 확정한 뒤
  별도 계획으로 진행한다.

### 코드 재대조로 보정한 전제

- `TaskBoardRulesTests`가 macOS와 iPhone의 오늘 보드 이월 표시 차이를 의도된 정책으로
  고정하고 있다. 따라서 오늘 보드의 표시 목록을 강제로 같게 만들지 않는다.
- iPhone 이월함은 `selectedDayKey` 이전 작업을 조회하지만 버튼은 항상
  `오늘로 이월`을 실행한다. 미래 보드에서는 오늘 작업까지 후보가 될 수 있으므로
  이월함 후보 기준은 양 플랫폼 모두 `DayKey.today`로 고정해야 한다.
- `CalendarEventRules`의 메모 공백 정규화 테스트는 이미 존재한다. 이 단계에서 필요한
  것은 새 코어 규칙이 아니라 macOS UI의 입력 전달과 왕복 편집 검증이다.
- 템플릿 배치의 `작업 삭제`는 일부 todo만 삭제하지 않는다. 연결 작업 전체가
  `todo`이고 보관되지 않았을 때만 전체 삭제하며, doing/done이 하나라도 있으면
  모든 작업을 유지하고 배치 연결만 해제할 수 있다.
- iOS Info.plist에는 백업 UTI export 선언이 이미 있고 `PlanBaseMobileTests` 타깃도
  존재한다. 새 식별자나 테스트 타깃을 만들지 않고 기존 설정을 확장한다.
- `verify-platform-builds.sh`는 SwiftPM 테스트와 양 플랫폼 빌드만 실행한다.
  `PlanBaseMobileTests`와 `PlanBaseLaunchUITests`는 별도 `xcodebuild test`가 필요하다.

## 4. 확정 제품 결정

### 이월 작업

- iPhone 오늘 보드는 이전 날짜의 활성 미완료 작업을 함께 표시하고, macOS는 오늘
  보드와 이월함을 분리하는 현재 플랫폼별 표현을 유지한다.
- 양 플랫폼 이월함은 현재 선택 날짜와 무관하게 `DayKey.today` 이전의 활성 미완료
  작업만 후보로 사용한다.
- 완료·보관·대체 레코드는 기존 `BoardQueryRules`와 `TaskRules`대로 제외한다.
- 이월함은 작업을 오늘로 명시적으로 옮기거나 원래 날짜에서 완료하는 도구로 유지한다.
- 과거 또는 미래 날짜를 직접 보고 있어도 이월함의 후보 집합은 바뀌지 않는다.

### 일정 메모

- 제목, 시작일, 종료일, 색상, 메모를 양 플랫폼 모두 생성·수정할 수 있다.
- 빈 메모는 `nil` 또는 기존 공통 정규화 규칙으로 저장한다.
- macOS에서 메모를 제외한 필드만 수정해도 기존 메모가 사라지지 않아야 한다.

### 캘린더 날짜 상세

- 양 플랫폼 모두 선택 날짜의 이벤트, 템플릿 배치, 작업을 확인할 수 있다.
- 템플릿 배치 삭제 시 `작업 유지`와 `연결 작업 전체 삭제`를 같은 공통 서비스로 처리한다.
- 연결 작업 전체 삭제는 모든 연결 작업이 todo이고 보관되지 않았을 때만 제공한다.
  doing/done/archived 작업이 하나라도 있으면 부분 삭제하지 않고 `작업 유지`만 제공한다.
- 날짜 상세에서 해당 날짜 칸반보드로 이동할 수 있다.
- macOS는 큰 월간 화면의 직접 편집 장점을 유지하고 날짜 상세를 별도 inspector/sheet로 제공한다.
- macOS 날짜 셀의 한 번 클릭은 현재처럼 선택만 하고, 상세는 명시적 toolbar 행동,
  두 번 클릭 또는 키보드 행동으로 연다. 템플릿 배치 중 클릭 동작은 바꾸지 않는다.

### 캘린더 이벤트 배치

- macOS와 iPhone은 같은 `CalendarEventGridLayout`으로 대표 이벤트, lane, overflow를 계산한다.
- macOS의 6주 고정 레이아웃과 iPhone의 5주/6주 적응형 레이아웃은 플랫폼 표현 차이로 유지할 수 있다.
- SwiftUI 식별에는 논리 `event.id`가 아니라 물리 `instanceID` 기반 `renderID`를 사용한다.
- lane을 넘는 이벤트는 조용히 숨기지 않고 날짜별 `+N` 또는 동등한 접근 가능한 표시를 제공한다.

### 백업

- `.easytaskbackup` package는 macOS와 iPhone에서 같은 codec으로 내보내고 가져온다.
- iPhone도 레거시 JSON을 읽을 수 있지만 새 백업은 package 형식으로만 쓴다.
- 가져오기 전에 package 전체를 검증하고 성공한 병합만 저장한다.
- 결과 화면에는 삽입·갱신 레코드와 첨부 이미지 수를 표시한다.

## 5. 단계별 실행 체크리스트

### Phase 0 — 기준점 고정

- [ ] 진행 중인 모바일 보드·캘린더·기록·위젯 변경을 별도 커밋으로 정리한다.
- [ ] `main`과 `origin/main`이 일치하고 정합성 작업 파일에 미커밋 변경이 없는지 확인한다.
- [ ] 현재 `swift test` 결과와 iOS/macOS Debug 빌드를 기준점으로 기록한다.
- [ ] 현재 미커밋 디자인 변경을 완료된 UX 계획과 다시 대조한다.
- 카드 상태 badge 제거 후에도 색 없이 현재 상태를 즉시 식별할 수 있는지 확인한다.
  - 모바일 단일 날짜 이벤트 제목의 `minimumScaleFactor(0.7)`이 확정 최소 글자 기준을
    침범하지 않는지 확인한다.
  - 대형 위젯 이벤트 제목 7pt는 active density 계획의 8pt 목표보다 작고, 더 최근
    캘린더 경험 계획의 11pt 기준과도 충돌한다. 11pt를 현재 승인 기준으로 적용하며,
    다른 크기를 채택하려면 실기기 근거와 함께 계획을 먼저 개정한다.
  - 기록 카드의 `상세보기`가 실제로는 날짜 칸반보드를 여는 동작임을 문구에서 명확히 한다.
- [ ] 아래 수동 fixture를 양 플랫폼에 준비한다.
  - 일정 메모 있음/없음
  - 오늘 작업과 이전 날짜 미완료 작업
  - 템플릿 배치와 todo/doing/done 연결 작업
  - 이미지가 포함된 회고와 메모
  - 미래·과거·완료 Task 알림
- [ ] 변경 전 화면과 동작을 캡처해 회귀 비교 기준으로 남긴다.

완료 조건:

- clean `main`에서 작업을 시작할 수 있다.
- 공통 테스트와 양 플랫폼 Debug 빌드가 통과한다.
- fixture의 논리 ID가 플랫폼별로 중복 생성되지 않는다.

### Phase 1 — P0 데이터 의미와 왕복 편집 정합성

#### 1.1 macOS 일정 메모 편집

- [x] `AddEventSheet`에 메모 입력을 추가한다.
- [x] `EventEditorSheet`에 기존 메모 초깃값과 편집 상태를 추가한다.
- [x] 추가·수정 모두 `CalendarEventRules.makeEvent/update`에 메모를 전달한다.
- [x] 기존 `calendarEventRulesNormalizeDraftAndUpdateEvent` 테스트가 공백 메모 정규화를
  이미 보장하는지 확인하고 중복 코어 테스트를 만들지 않는다.
- [x] macOS Debug 빌드로 추가·편집 binding의 컴파일 smoke test를 통과한다.
- [ ] iPhone에서 만든 메모를 macOS에서 수정하고 다시 iPhone에서 확인한다.

예상 파일:

- `desktop/App/Features/Calendar/DesktopEventEditorSheets.swift`
- `desktop/App/Features/Calendar/CalendarView.swift`
- `shared/Tests/CalendarRulesTests.swift`

#### 1.2 이월함 후보 기준일 통일

- [x] 기존 `boardQueryRulesPreserveDesktopAndMobileCarryoverPolicies` 테스트를 유지한다.
- [x] iPhone 이월 query와 `TaskRules.carryoverTasks`의 cutoff를 `DayKey.today`로 바꾼다.
- [x] macOS와 iPhone 이월함의 후보 Task ID 집합이 같은지 확인한다.
- [x] 미래 보드에서 오늘 작업이 이월 후보로 들어가지 않는 회귀 테스트를 추가한다.
- [x] 과거 보드에서도 오늘 이전의 전체 미완료 후보 집합이 유지되는지 확인한다.
- [x] `오늘로 이월`과 `원래 날짜에 완료`가 양 플랫폼에서 같은 Task 상태·날짜 결과를 만드는지 확인한다.

예상 파일:

- `shared/Tests/TaskBoardRulesTests.swift`
- `mobile/App/Features/Board/MobileBoardView.swift`

완료 조건:

- 같은 Task 집합으로 양 플랫폼 이월함의 후보 ID와 실행 결과가 같다.
- iPhone 인라인 표시와 macOS 별도 이월함이라는 플랫폼별 표현은 유지된다.
- 모바일에서 작성한 일정 메모를 macOS에서 손실 없이 수정할 수 있다.
- schema와 백업 format에는 diff가 없다.

### Phase 2 — P1 캘린더 수명주기 정합성

- [x] macOS 월 query host가 현재 범위의 이벤트와 템플릿 배치를 bounded descriptor로 함께 조회한다.
- [x] macOS에 선택 날짜 상세 inspector 또는 sheet를 추가한다.
- [x] 날짜 상세에 이벤트, 템플릿 배치, 작업 요약을 표시한다.
- [x] 날짜 셀 한 번 클릭은 선택, 두 번 클릭/toolbar/키보드는 상세 열기로 역할을 분리한다.
- [x] 템플릿 배치 모드에서는 기존 날짜 선택 동작이 우선하도록 한다.
- [x] 이벤트 추가·편집·삭제는 기존 macOS editor를 재사용한다.
- [x] 템플릿 배치 요약 계산과 삭제 사전 판단은 공통 서비스 결과를 사용한다.
- [x] 배치 삭제 시 `작업 유지`와 조건부 `연결 작업 전체 삭제`를 제공한다.
- [x] doing/done/archived가 하나라도 있으면 todo 일부만 삭제하지 않고 작업 삭제 전체를 막는다.
- [x] 작업 삭제 가능 범위를 실행 직전에 ID로 다시 조회한다.
- [x] 저장 실패 시 rollback하고 상세 화면을 유지한다.
- [x] `CalendarView`에 날짜 보드 이동 callback을 추가한다.
- [x] `AppRootView`가 선택 날짜를 보드 탭으로 전달하게 한다.
- [x] iPhone과 macOS가 같은 `TemplateService.deletePlacement` 결과를 사용함을 단위 테스트로 확인한다.
- [x] macOS의 private `CalendarEventSegment/eventSegments`를 공통 `CalendarEventGridLayout`으로 교체한다.
- [x] transient CloudKit 중복은 `updatedAt`, `instanceID` 규칙으로 대표 이벤트 하나만 렌더링한다.
- [x] 이벤트 편집·삭제 대상도 논리 `event.id`의 첫 레코드가 아니라 선택한
  `renderID/instanceID`의 대표 물리 레코드로 다시 확인한다.
- [x] 양 앱에서 lane 초과 이벤트 수를 숨기지 않고 `+N`과 접근성 정보로 표시한다.

예상 파일:

- `desktop/App/Features/Calendar/CalendarView.swift`
- `desktop/App/Features/Calendar/DesktopCalendarGrid.swift`
- `desktop/App/Features/Calendar/DesktopCalendarDayInspector.swift`
- `desktop/App/AppRootView.swift`
- `shared/Core/Services/BoundedQueryService.swift`
- `shared/Core/Services/CalendarEventGridLayout.swift`
- `shared/Core/Services/TemplateService.swift`
- `shared/Tests/BoundedQueryServiceTests.swift`
- `shared/Tests/CalendarEventGridLayoutTests.swift`
- `shared/Tests/TemplateServiceTests.swift`

새 Swift 파일은 `PlanBase.xcodeproj`의 macOS target membership과 실제 Xcode group에
함께 등록한다.

완료 조건:

- 양 플랫폼에서 같은 배치를 조회하고 같은 두 가지 삭제 정책을 실행할 수 있다.
- 날짜 상세에서 같은 날짜의 이벤트와 활성 Task 수가 일치한다.
- 캘린더에서 보드로 이동했을 때 선택 날짜가 유지된다.

### Phase 3 — P1 iPhone 백업 이동성

- [x] macOS `BackupService`는 이미 AppKit adapter 역할만 하므로 불필요하게 리팩터링하지 않는다.
- [x] package 생성·검증·병합은 기존 `BackupPackageCodec`을 그대로 사용한다.
- [x] iPhone 전용 import/export coordinator와 document picker adapter를
  `mobile/App/Infrastructure`에 추가한다.
- [x] package 디렉터리를 안전하게 가져오고 내보낼 수 있도록
  `UIDocumentPickerViewController` 또는 동등한 package 지원 API를 사용한다.
- [x] 기록 탭의 기존 테마·필터 버튼을 유지하고 백업 행동은 overflow `Menu`로 제공한다.
- [x] 외부 파일 접근은 security-scoped URL의 접근 성공 여부를 확인한다.
- [x] import package는 앱이 관리하는 임시 위치에 복사한 뒤 전체 검증한다.
- [x] export package는 작업별 임시 디렉터리에 만들고 사용자 선택이 끝난 뒤 해당 디렉터리만 정리한다.
- [x] 파일 복사·package 읽기와 checksum 검사는 가능한 범위에서 메인 스레드 밖에서 실행하고,
  SwiftData 병합만 `MainActor`에서 실행한다.
- [x] 진행 중 상태에서는 중복 실행을 막고 큰 package에서도 앱이 멈춘 것으로 보이지 않게 한다.
- [x] 취소는 오류로 표시하지 않고 저장소를 변경하지 않는다.
- [x] 성공 결과에 삽입·갱신 데이터와 이미지 수를 표시한다.
- [x] `restoreMerging`은 자체적으로 data changed notification을 보내지 않으므로 성공한 뒤
  `PersistenceCommandService.dataChangedNotification`을 같은 `ModelContext`로 한 번만 게시한다.
- [x] 이 알림으로 기록 query refresh, 위젯 snapshot, Task 알림 reconcile이 실행되는지 확인한다.
- [x] 레거시 JSON은 이미지 원본을 포함하지 않는다는 경고와 누락 이미지 수를 표시한다.
- [x] package 내보내기와 레거시 JSON 가져오기를 모두 확인한다.
- [x] 기존 iOS UTI export 선언을 재사용하고, Files 앱에서 직접 열기까지 지원할 경우에만
  같은 식별자의 `CFBundleDocumentTypes` import 역할을 추가한다.
- [x] 새 앱 소스와 테스트 파일을 각각 `PlanBase-iOS`, `PlanBaseMobileTests` target과
  실제 Xcode group에 등록한다.
- [x] 파일 adapter는 protocol 뒤로 감싸 취소, 접근 실패, 복사 실패, 성공 notification을
  `PlanBaseMobileTests`에서 실제 document picker 없이 검증한다.
- [x] 손상·과대·checksum 불일치 package가 저장소를 변경하지 않는지 재검증한다.

예상 파일:

- `mobile/App/Infrastructure/MobileBackupService.swift`
- `mobile/App/Features/Archive/MobileArchiveView.swift`
- `mobile/Configuration/PlanBase-iOS-Info.plist`
- `mobile/Tests/MobileBackupServiceTests.swift`
- `PlanBase.xcodeproj/project.pbxproj`
- `shared/Core/Services/BackupPackageCodec.swift`
- `shared/Tests/BackupPackageTests.swift`

완료 조건:

- macOS에서 만든 package를 iPhone이 가져오고 그 반대도 가능하다.
- 이미지가 포함된 회고가 양방향 round trip 후 동일하게 열린다.
- 잘못된 package의 가져오기 전후 레코드와 첨부 checksum이 같다.
- iPhone 백업 가져오기 후 위젯과 pending Task 알림이 최종 저장 상태에 수렴한다.

### Phase 4 — P2 회고와 정책 문구 정리

- [x] 공통 `DailyReviewWritingRules`를 사용해 macOS 회고에도 작성 프롬프트를 제공한다.
- [x] 기존 `DailyReviewWritingRulesTests`의 append·중복 방지 규칙을 재사용하고 중복 테스트를 만들지 않는다.
- [x] macOS Task 상세의 알림 영역에 `iPhone에서 설정한 알림` 정책을 명확히 표시한다.
- [x] 빈 상태, 삭제 확인, 저장 실패 문구의 용어를 양 플랫폼에서 맞춘다.
- [x] 접근성 레이블은 플랫폼별 조작 방식에 맞게 유지한다.

완료 조건:

- 회고 프롬프트가 양 플랫폼에서 같은 텍스트 규칙을 사용한다.
- macOS 사용자가 알림 시각 표시를 Mac에서 울리는 알림으로 오해하지 않는다.

### Phase 5 — 전체 회귀와 출시 승인

- [x] `git diff --check`
- [x] `swift test`
- [x] `swift test -c release`
- [x] iOS Debug/Release simulator build
- [x] macOS Debug/Release build
- [x] `./scripts/verify-platform-builds.sh`
- [x] simulator UDID를 지정한 `PlanBase-iOS` scheme의 `xcodebuild test`
  - `PlanBaseMobileTests`
  - `PlanBaseLaunchUITests`
- [ ] macOS 수동 smoke test
- [ ] iPhone 실기기 백업 import/export와 알림 재수렴 확인
- [ ] iPhone ↔ Mac CloudKit 왕복 검증
- [x] 기존 홈/잠금 화면 위젯 snapshot과 딥링크 회귀 확인

자동 검증 기록(2026-07-24):

- Debug SwiftPM 235건, Release SwiftPM 234건 통과
- `PlanBaseMobileTests` 11건 통과
- `PlanBaseLaunchUITests` 10건 통과
- iOS·macOS Debug/Release 빌드 통과

모든 자동 검증과 실기기 승인 항목이 끝난 뒤에만 TestFlight와 macOS 배포용 archive를
생성한다.

`verify-platform-builds.sh`가 포함하지 않는 iOS 테스트는 별도로 실행한다.

```bash
xcodebuild -quiet \
  -project PlanBase.xcodeproj \
  -scheme PlanBase-iOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<simulator-udid>' \
  -derivedDataPath "${TMPDIR:-/tmp}/PlanBaseCrossPlatformParityTests" \
  test
```

## 6. 양방향 검증 행렬

| 시나리오 | 기대 결과 |
|---|---|
| iPhone에서 일정 메모 생성 → Mac CloudKit import | Mac에서 같은 메모를 표시·편집 |
| Mac에서 일정 메모 수정 → iPhone CloudKit import | 다른 필드와 메모가 함께 수렴 |
| 과거 미완료 Task 생성 → 양쪽 이월함 | 같은 후보 Task ID, 인라인 표현은 플랫폼 정책 유지 |
| 미래 날짜 보드에서 iPhone 이월함 열기 | 오늘 작업은 후보에서 제외 |
| iPhone에서 템플릿 다중 날짜 배치 → Mac CloudKit import | Mac 날짜 상세에 같은 배치와 작업 수 |
| Mac에서 배치만 삭제 | 양쪽에서 Task는 유지되고 placement만 제거 |
| 연결 작업이 모두 todo인 배치 삭제 | 연결 Task 전체와 placement 삭제 |
| 연결 작업에 doing/done이 섞인 배치 삭제 | 부분 삭제 없이 작업 유지와 연결 해제만 허용 |
| Mac package → iPhone import | 데이터·이미지·메모·알림 기록 유지 |
| iPhone package → Mac import | 동일한 merge report와 활성 대표 레코드 |
| Mac에서 미래 알림 Task 완료 | iPhone import 후 pending 알림 제거, 기록 유지 |
| 백업 import 후 앱 재실행 | 무결성 수렴, 위젯 갱신, 크래시 없음 |

## 7. Git 진행 단위

진행 중 디자인 변경과 충돌을 줄이기 위해 한 브랜치에서 모든 작업을 섞지 않는다.

권장 브랜치와 커밋:

1. `fix/cross-platform-data-parity`
   - `fix(calendar): support event notes on macOS`
   - `fix(board): align carryover candidate cutoff`
   - `test: cover cross-platform board and event parity`
2. `feat/desktop-calendar-day-detail`
   - `feat(macos): add calendar day inspector`
   - `feat(calendar): share event layout and overflow rules`
   - `feat(macos): manage template placement lifecycle`
3. `feat/ios-backup-portability`
   - `refactor(backup): separate platform file adapters`
   - `feat(ios): import and export backup packages`
   - `test: verify cross-platform backup round trips`
4. `chore/cross-platform-ux-policy`
   - `feat(macos): add review writing prompts`
   - `docs: clarify platform notification ownership`

각 브랜치는 관련 테스트와 해당 플랫폼 Debug 빌드가 통과한 뒤 병합한다. 공통 코어,
Xcode 설정 또는 persistence 경계를 변경한 브랜치는 양 플랫폼 전체 회귀 게이트까지
통과해야 한다.

## 8. 보류 항목: macOS 로컬 알림

다음 조건이 확정되기 전에는 이번 계획에 포함하지 않는다.

- 기기별 `Mac에서도 알림` opt-in의 저장 위치와 기본값
- iPhone과 Mac의 중복 알림을 사용자가 이해할 수 있는 UI
- macOS 권한 거절·집중 모드·앱 종료 상태의 동작
- CloudKit import와 시간대 변경 이후 macOS pending 요청 재수렴
- 시스템 notification center를 감싼 테스트 가능한 adapter

진행할 경우 `reminderAt` schema는 그대로 사용하고 macOS 전용 scheduler와 로컬
설정만 추가하는 별도 계획으로 작성한다.

## 9. 최종 완료 기준

- 같은 공통 데이터 집합에서 양 플랫폼의 Task·Event·Placement 의미가 같다.
- 일정 메모가 양방향 생성·수정에서 손실되지 않는다.
- 이월함의 후보 Task ID와 실행 결과가 양 플랫폼에서 같고 인라인 표시 차이는 의도대로 유지된다.
- 템플릿 배치 조회와 원자적인 두 가지 삭제 정책을 양 플랫폼에서 수행할 수 있다.
- 캘린더 대표 이벤트, lane과 overflow 개수가 공통 엔진 결과와 일치한다.
- 백업 package가 macOS와 iPhone 사이에서 이미지까지 포함해 왕복한다.
- 의도된 플랫폼 전용 기능과 실제 기능 결손이 문서와 UI에서 명확히 구분된다.
- 기존 CloudKit, 위젯, 알림 기록, 백업 호환성에 회귀가 없다.
- 전체 자동 검증과 양 플랫폼 수동 검증이 완료된다.
