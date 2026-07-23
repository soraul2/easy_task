# PlanBase 잠금 화면 위젯 구현 계획

## 구현 체크 결과 (2026-07-23)

- [x] 캘린더 위젯 밀도 v3 위에 snapshot v4 호환 계약을 추가했다.
- [x] 8일 Task/Event 요약 규칙, bounded query, 이전 JSON 호환과 미래 schema 보호를 구현했다.
- [x] DataIntegrity readiness 이후 발행하고 내용 변경 시 두 widget kind를 reload한다.
- [x] `scope=today`/명시 날짜 보드 딥링크와 iPhone 앱 라우팅을 구현했다.
- [x] Inline/Circular/Rectangular UI, 개인정보 표시, 접근성, 배경과 timeline을 구현했다.
- [x] WidgetBundle·Xcode target·모바일 통합 테스트에 새 소스를 등록했다.
- [x] 관련 테스트, 전체 SwiftPM Debug/Release 테스트, iOS/macOS Debug/Release 빌드가 통과했다.
- [ ] 출시 전 실기기에서 widget gallery, 잠금 상태 제목 redaction, Always On/저휘도, cold/warm tap을 수동 확인한다.

코드 체크리스트와 자동 검증은 완료했다. 마지막 항목은 simulator나 정적 검사로 대체할 수 없는 실기기 출시 승인 단계이며, 읽기 전용 1차 범위 밖의 Task 직접 완료는 계획대로 구현하지 않았다.

## 1. 목적

PlanBase의 오늘 보드와 캘린더 요약을 iPhone 일반 잠금 화면에서 빠르게 확인하게 한다. 기존 홈 화면 캘린더 위젯은 그대로 유지하고, 같은 Widget Extension과 App Group 스냅샷을 재사용해 잠금 화면 전용 위젯을 추가한다.

이 계획의 1차 목표는 안전한 읽기 전용 위젯과 앱 딥링크다. 잠금 상태에서 Task를 직접 완료하거나 생성하는 기능은 인증과 저장소 경계가 추가로 필요하므로 2차 범위로 분리한다.

## 2. Apple 플랫폼 기준

- iPhone 일반 잠금 화면은 `accessoryInline`, `accessoryCircular`, `accessoryRectangular` family를 지원한다.
- 현재 PlanBase가 지원하는 `systemSmall`, `systemMedium`, `systemLarge`는 iPhone 홈 화면용이며, `systemSmall`은 StandBy에도 표시될 수 있지만 일반 잠금 화면의 accessory 영역에는 나타나지 않는다.
- 잠금 화면 accessory 위젯은 주로 단색 `vibrant` 렌더링을 사용한다. 이벤트 색상만으로 의미를 전달하지 않고 텍스트, SF Symbol, 게이지 형태를 함께 사용해야 한다.
- WidgetKit은 실시간 화면이 아니다. Timeline과 앱의 명시적 reload 요청으로 갱신되며 시스템이 실제 갱신 시점을 조정할 수 있다.
- `Button`과 `Toggle`을 사용하는 인터랙티브 위젯은 iPhone의 `accessoryCircular`, `accessoryRectangular`에서 지원하지만, 기기가 잠긴 상태에서는 인증과 잠금 해제가 필요하다.
- Task 제목과 CalendarEvent 제목은 개인 정보일 수 있으므로 제목을 표시하는 view에 `privacySensitive()`를 적용한다.

공식 문서:

- [Widgets Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/widgets)
- [Developing a WidgetKit strategy](https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy)
- [Preparing widgets for additional contexts and appearances](https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-contexts-and-appearances)
- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [Controls](https://developer.apple.com/documentation/widgetkit/controls-collection)

## 3. 현재 상태

### 위젯 구성

- `PlanBaseCalendarWidget` 하나가 `systemSmall`, `systemMedium`, `systemLarge`를 지원한다.
- `PlanBaseWidgetBundle`에는 현재 캘린더 위젯 하나만 등록되어 있다.
- 위젯은 SwiftData나 CloudKit을 직접 열지 않고 App Group의 `calendar-widget-v1.json`만 읽는다.
- 앱의 `CalendarWidgetSnapshotPublisher`가 이벤트와 테마를 JSON으로 쓰고 내용이 달라졌을 때만 WidgetKit timeline을 다시 요청한다.
- timeline은 현재 entry 하나를 만들고 다음 날 시작 이후 다시 요청하도록 설정되어 있다.

### 데이터와 이동

- 현재 `CalendarWidgetSnapshot`은 CalendarEvent와 테마만 포함하고 Task는 포함하지 않는다.
- 날짜 탭은 `planbase://calendar?date=yyyy-MM-dd`를 사용하며 앱의 캘린더 탭으로 이동한다.
- 보드용 widget deep link는 아직 없다.
- 실제 SwiftData 저장소는 iPhone 앱의 Application Support에 있다. App Group에는 읽기용 JSON snapshot만 있으므로 Widget Extension에서 앱 저장소를 직접 수정할 수 없다.

관련 파일:

- `mobile/Widget/PlanBaseCalendarWidget.swift`
- `mobile/App/CalendarWidgetSnapshotPublisher.swift`
- `mobile/App/PlanBaseMobileApp.swift`
- `shared/Core/Services/CalendarWidgetSnapshot.swift`
- `shared/Core/Persistence/PlanBaseContainerFactory.swift`
- `shared/Tests/CalendarWidgetSnapshotTests.swift`

## 4. 범위 결정

### 4.1 1차 범위: 읽기 전용 오늘 요약

별도의 `PlanBaseLockScreenWidget`을 같은 Widget Extension에 추가한다.

별도 widget kind를 사용하는 이유는 다음과 같다.

1. 기존 `PlanBase 캘린더` 홈 화면 위젯의 이름, 설명, 지원 family와 설치 상태를 바꾸지 않는다.
2. 잠금 화면 위젯은 캘린더뿐 아니라 Task 상태를 함께 보여주므로 독립적인 `PlanBase 오늘` 항목이 더 정확하다.
3. 홈 화면과 잠금 화면의 layout, margin, 렌더링 규칙을 서로 독립적으로 발전시킬 수 있다.

새 kind는 `PlanBaseCompatibility`에 추가하고 배포 후에는 호환 식별자로 취급한다. 기존 calendar widget kind, App Group, snapshot 파일 이름은 변경하지 않는다.

### 4.2 2차 범위: 빠른 실행과 인터랙션

1차 검증이 끝난 뒤 아래 기능을 별도 결정으로 진행한다.

- `ControlWidget`: 잠금 화면 하단이나 제어 센터에서 오늘 보드 또는 새 Task 화면 열기
- `AppIntent` 버튼: 선택 Task 완료 또는 상태 변경
- 사용자 설정형 위젯: Task 중심/일정 중심 표시 선택

Task 직접 완료는 1차 범위에 포함하지 않는다. Widget Extension은 현재 앱의 SwiftData 저장소를 열 수 없고, 잠금 화면 상호작용은 인증도 필요하다. 구현 전에 다음 선택지를 별도 검토한다.

1. `openAppWhenRun`으로 인증 후 앱 프로세스를 열어 기존 완료 요청 흐름을 실행한다. 미래 `reminderAt`이 있으면 [`TASK_REMINDER_COMPLETION_RETENTION_PLAN.md`](TASK_REMINDER_COMPLETION_RETENTION_PLAN.md)의 확인 alert를 반드시 거친다.
2. App Group command queue는 잠금 화면에서 필요한 미래 알림 경고와 즉시 결과를 보장할 수 없으므로 Task 완료에는 사용하지 않는다.
3. SwiftData 저장소 자체를 App Group으로 이전하는 방식은 기존 설치 데이터와 CloudKit migration 위험이 크므로 이 기능만을 위해 선택하지 않는다.

### 4.3 이번 계획에서 제외

- SwiftData `EasyTaskSchemaV7` 추가
- CloudKit schema 변경
- macOS 잠금 화면 또는 Apple Watch complication
- 초 단위 countdown이나 실시간 상태 표시
- Live Activity
- 잠금 상태에서 인증 없이 Task 내용 수정

PlanBase CalendarEvent는 현재 일 단위 모델이며 시간 정보를 보존하지 않으므로 `다음 일정 14:00` 같은 표시는 제공하지 않는다.

## 5. 확정 표시 설계

### 5.1 공통 데이터 의미

잠금 화면의 기준일은 `DayKey.key(for: entry.date)`로 계산한다. 임의 DateFormatter나 별도 날짜 문자열 비교는 사용하지 않는다.

Task 요약은 `BoardQueryRules`의 의미를 따른다.

- `할 일`: 기준일에 계획된 활성 `todo` Task
- `진행`: 기준일에 계획된 활성 `doing` Task
- `완료`: `completedDayKey`가 기준일인 활성 `done` Task
- archive 또는 `supersededAt` 처리된 Task는 제외
- 이월 Task는 기존 오늘 보드의 기본 정책과 맞춰 자동 포함하지 않는다.

CalendarEvent는 기존 snapshot의 `events(onDayKey:)` 결과를 사용한다. 시작일·종료일이 기준일을 포함하는 여러 날 이벤트도 오늘 일정에 포함한다.

### 5.2 Accessory Inline

표시 예시:

```text
PlanBase · 할 일 3 · 일정 2
```

- 한 줄에서 안정적으로 잘리도록 제목은 표시하지 않고 개수만 표시한다.
- 정상 snapshot에서 Task와 Event가 모두 없을 때만 `PlanBase · 오늘 계획 없음`을 표시한다.
- 탭하면 오늘 보드로 이동한다.

### 5.3 Accessory Circular

- 완료율 분모가 이월·완료 날짜에 따라 달라지는 혼동을 피하기 위해 비율 대신 오늘 남은 Task 수(`todo + doing`)를 표시한다.
- 중앙에는 남은 Task 수를 표시하고 접근성 레이블은 `오늘 남은 작업 N개`로 제공한다.
- 남은 Task가 없으면 checkmark를 표시하되 snapshot 갱신 실패를 완료 상태로 오해하지 않도록 가용성 상태를 먼저 검사한다.
- event는 원형 family에 함께 넣지 않는다.
- 탭하면 오늘 보드로 이동한다.

### 5.4 Accessory Rectangular

두 줄 요약을 기본으로 하고 사용자 제목은 하나만 표시한다.

```text
남음 4 · 완료 2 · 일정 2
제품 출시
```

- `남음`은 오늘의 `todo + doing`이다.
- 첫 줄은 남은 Task, 오늘 완료 Task, CalendarEvent 개수다.
- 둘째 줄은 대표 제목 하나만 표시한다. 우선순위는 진행 중 Task, 첫 CalendarEvent, 첫 `todo` Task 순이다.
- 사용자 제목은 한 줄로 제한하고 `privacySensitive()`를 적용한다.
- 색상 점은 보조 표현으로만 사용한다. `vibrant` 모드에서 색이 사라져도 정보가 유지되어야 한다.
- 탭하면 오늘 보드로 이동한다. 위젯 내부의 여러 개 `Link`는 1차 범위에서 사용하지 않아 작은 터치 영역의 모호함을 피한다.

### 5.5 렌더링과 접근성

- `widgetRenderingMode`의 `vibrant`, `accented`, `fullColor`를 preview와 실제 기기에서 확인한다.
- 잠금 화면에서는 시스템 font와 SF Symbol을 사용하고 사용자 테마 색에 의존하지 않는다.
- `widgetAccentable()`은 강조 요소에만 적용한다.
- `isLuminanceReduced` 상태에서도 핵심 숫자와 레이블이 읽혀야 한다.
- 별도 잠금 화면 widget configuration에는 기본 content margin을 우선 사용한다. 홈 화면 위젯의 `contentMarginsDisabled()`를 그대로 복사하지 않는다.
- 모든 accessory root에 `containerBackground(for: .widget)`을 적용하고 제거 가능한 배경을 유지한다.
- `accessoryCircular`은 `AccessoryWidgetBackground`를 사용해 시스템 표준 원형 배경에 맞춘다.
- 본문 글자는 11pt 이상을 목표로 하고 공간이 부족하면 제목을 더 줄이지 않고 생략한다.
- VoiceOver 레이블은 표시된 개수가 아니라 실제 오늘 Task/Event 개수를 읽는다.
- 개수는 잠금 상태에서도 표시하고 사용자 작성 제목만 `privacySensitive()`로 가린다.
- 제목 view와 제목을 포함하는 접근성 표현의 privacy redaction을 실제 잠금 상태에서 확인한다.

### 5.6 가용성 상태와 TimelineProvider

별도 `PlanBaseLockScreenEntry`와 `PlanBaseLockScreenProvider`를 `PlanBaseLockScreenWidget.swift`에 둔다. 기존 캘린더 provider는 `private`이므로 암묵적으로 재사용하지 않는다. 캘린더 밀도 개선에서 도입한 private 가용성 enum은 `PlanBaseWidgetSnapshotAvailability.swift`의 Widget Extension 내부 공통 타입으로 추출한 뒤 두 provider가 재사용한다.

잠금 화면 표현 상태는 다음과 같다.

```text
availableContent
availableEmpty
needsRefresh
requiresAppUpdate
```

- `availableContent`: 유효 coverage의 날짜별 요약에 한 개 이상의 Task 또는 Event가 있음
- `availableEmpty`: 유효 coverage의 날짜별 요약이 모두 0이며 이때만 `오늘 계획 없음` 표시
- `needsRefresh`: snapshot 누락·손상·Task 요약 없음·Task coverage 만료·최초 잠금 해제 전 파일 접근 불가
- `requiresAppUpdate`: 현재 위젯보다 높은 미래 schema
- `needsRefresh`는 `PlanBase를 열어 갱신하세요`, `requiresAppUpdate`는 `PlanBase를 업데이트해 주세요`로 표시한다.
- 오류 상태도 오늘 board deep link를 유지해 앱 실행으로 복구할 수 있게 한다.

provider는 Task 요약 coverage 안의 오늘과 이후 날짜별 entry를 가능한 범위에서 미리 생성한다. 마지막 entry 이후에 새 timeline을 요청하고, 앱에서 snapshot 내용이 바뀌면 두 widget kind를 reload한다. 시스템이 자정 갱신을 늦추더라도 tap destination은 앱이 실행 시점의 오늘을 다시 계산한다.

## 6. App Group snapshot 계약 확장

### 6.1 호환 원칙

현재 파일 이름 `calendar-widget-v1.json`과 기존 `CalendarWidgetSnapshot` 타입 이름은 배포 호환성을 위해 유지한다. 타입 이름이 캘린더 중심이더라도 이 작업에서 대규모 rename을 하지 않는다.

snapshot에는 Task 원본 배열 대신 날짜별 최소 요약을 추가한다.

```text
LockScreenWidgetDaySummary
  dayKey
  todoCount
  doingCount
  doneCount
  eventCount
  focusTitle?
  focusKind?
```

`focusKind`는 `doingTask`, `event`, `todoTask` 중 하나이며 대표 제목이 없으면 두 값 모두 `nil`이다.

추가 계약:

- `lockScreenCoveredStartDayKey`
- `lockScreenCoveredEndDayKey`
- `lockScreenDaySummaries`

lock-screen coverage는 발행 기준일을 포함해 8일로 고정한다. writer는 실제 데이터가 없는 날짜도 개수 0인 summary를 기록해 정상 빈 상태와 누락을 구분한다. 앱을 며칠 열지 않아도 WidgetKit이 미래 날짜 entry를 이미 저장된 bounded 요약으로 렌더링할 수 있어야 한다. coverage 밖 날짜에는 빈 계획이 아니라 `needsRefresh`를 표시한다.

`LockScreenWidgetRules`는 bounded Task와 CalendarEvent 입력에서 8일 summary를 결정적으로 만든다. Task 전체 제목·메모·태그·알림 시각은 App Group에 추가하지 않고 대표 제목 하나만 날짜별로 저장한다. view는 저장된 summary만 읽고 필터·정렬 규칙을 다시 구현하지 않는다.

App Group 파일은 기존 원자적 write에 최초 사용자 인증 이후 접근 가능한 파일 보호 옵션을 함께 적용한다. 제목만 `privacySensitive()`로 redaction하고 개수는 표시하므로 Widget Extension 전체에 `NSFileProtectionComplete`를 적용해 잠금 중 모든 내용을 숨기는 방식은 사용하지 않는다. 재부팅 후 최초 잠금 해제 전 읽을 수 없으면 `needsRefresh` 또는 시스템 placeholder로 안전하게 처리한다.

### 6.2 JSON 이전 호환

- 캘린더 위젯 밀도 개선의 v3가 안정화된 뒤 이 계획은 v4로 구현한다.
- v1/v2/v3 및 lock-screen summary가 없는 payload는 캘린더 데이터는 기존대로 읽되 Task 요약 가용성은 `needsRefresh`로 판단한다.
- 앱 업데이트 직후 App Group에 남아 있는 구버전 파일도 위젯이 실패 없이 읽어야 한다.
- `hasSameContent`는 lock-screen coverage와 day summary를 비교한다. `generatedAt`만 달라진 경우에는 불필요한 reload를 하지 않는다.
- `.empty`와 `.preview` fixture에도 날짜별 summary와 가용성 상태를 추가한다.
- 손상 JSON 복구 정책은 캘린더 위젯 밀도 계획의 원자적 교체 규칙을 따른다.
- 현재보다 높은 미래 schema는 이전 writer가 덮어쓰지 않고 `requiresAppUpdate`로 전달한다.

### 6.3 캘린더 위젯 밀도 계획과의 병합 규칙

[`CALENDAR_WIDGET_DENSITY_PLAN.md`](CALENDAR_WIDGET_DENSITY_PLAN.md)의 v3 snapshot과 가용성 상태 구현을 이 계획의 선행 작업으로 둔다. 현재 작업 트리에서도 해당 구현이 진행 중이므로 같은 파일을 병렬 수정하지 않는다.

- 먼저 밀도 개선의 event coverage/count, 미래 schema 보호, snapshot 가용성 상태, bounded publisher를 통합하고 테스트를 통과시킨다.
- 그다음 v4에서 lock-screen coverage와 day summary만 추가한다.
- v4 decoder는 v1~v3을 읽고, v3 writer는 v4 파일을 덮어쓰지 않는다.
- lock-screen 작업은 밀도 개선이 수정 중인 `CalendarWidgetSnapshot.swift`와 publisher가 안정화되기 전 시작하지 않는다.

## 7. 발행 및 갱신 경로

`CalendarWidgetSnapshotPublisher`는 장기적으로 이름을 유지해도 되지만 역할은 CalendarEvent와 lock-screen 날짜별 요약을 함께 발행하는 PlanBase widget snapshot publisher로 확장한다. 캘린더 밀도 개선에서 만드는 bounded fetch·coalescing·복구 경로를 그대로 확장하고 별도 publisher를 중복 생성하지 않는다.

필수 동작:

1. lock-screen coverage에 해당하는 Task만 `BoundedQueryService` descriptor로 조회한다.
2. `plannedDayKey`가 coverage에 있는 Task와 `completedDayKey`가 coverage에 있는 Task를 모두 확보해 날짜별 summary를 만든다.
3. `MobileAppRootView.start()`의 DataIntegrity reconciliation이 성공한 뒤 publisher readiness를 활성화하고 최초 snapshot을 발행한다. 루트와 background view의 `.task` 실행 순서에 암묵적으로 의존하지 않는다.
4. Task 저장, 상태 변경, 이월, 완료, CloudKit import 후 수렴, 날짜 변경, 시간대 변경, 앱 active 전환 때 snapshot을 다시 평가한다.
5. 알림 보존 계획의 모든 완료 저장도 `PersistenceCommandService.dataChangedNotification`을 발생시키므로 같은 coalescing 경로에서 summary를 갱신한다.
6. 내용이 달라졌을 때 기존 calendar kind와 새 lock-screen kind의 timeline을 각각 reload한다.
7. Widget Extension은 snapshot만 읽으며 SwiftData/CloudKit을 직접 열지 않는다.

WidgetKit의 시스템 예산 때문에 분 단위 polling은 추가하지 않는다. 날짜가 바뀌는 시점과 저장 변경 신호를 중심으로 갱신한다. 다른 기기에서 CloudKit으로 변경한 내용은 iPhone 앱이 import하고 snapshot을 다시 발행한 이후 잠금 화면에 반영되는 현재 구조의 한계를 명시한다.

## 8. 딥링크 계획

공통 코어에 오늘 보드와 명시적 날짜 보드 deep link를 추가한다. 잠금 화면 위젯은 자정 timeline 지연에도 실제 오늘을 열도록 의미 기반 route를 사용한다.

```text
planbase://board?scope=today
planbase://board?date=yyyy-MM-dd
```

호환 규칙:

- `planbase://`와 기존 `easytask://` scheme을 모두 파싱한다.
- `scope=today`는 URL 생성 시점이 아니라 앱이 route를 처리하는 시점의 `DayKey.today`로 해석한다.
- `scope=today`와 `date`가 함께 있으면 모호한 route로 거부한다.
- day key가 유효하지 않으면 route를 무시한다.
- 기존 calendar deep link 동작은 변경하지 않는다.
- `PlanBaseMobileApp.handleDeepLink`는 route 종류를 구분해 보드 또는 캘린더 탭을 선택한다.
- 앱 cold launch, background 복귀, foreground 상태에서 `scope=today`가 항상 처리 시점의 오늘로 이동해야 한다.

향후 ControlWidget의 새 Task route가 필요하면 `board?scope=today&action=new-task`처럼 확장하되 1차 구현에는 포함하지 않는다.

## 9. 변경 파일 계획

### 새 파일

- `shared/Core/Services/LockScreenWidgetRules.swift`
  - 날짜별 Task/Event 최소 요약과 대표 제목 우선순위를 계산하는 순수 규칙
- `shared/Tests/LockScreenWidgetRulesTests.swift`
  - 상태 개수, 완료 날짜, coverage, 대표 제목 정렬 테스트
- `mobile/Widget/PlanBaseLockScreenWidget.swift`
  - accessory 세 family의 entry, provider, view와 widget configuration
- `mobile/Widget/PlanBaseWidgetSnapshotAvailability.swift`
  - 홈 화면과 잠금 화면 provider가 공유하는 snapshot read 상태
- `mobile/Tests/PlanBaseWidgetSnapshotIntegrationTests.swift`
  - iOS 파일 보호와 App Group snapshot 읽기 검증

새 mobile source는 `PlanBase.xcodeproj/project.pbxproj`의 Widget Extension target membership에 반드시 등록한다.

### 수정 파일

- `shared/Core/Persistence/PlanBaseCompatibility.swift`
  - 새 lock-screen widget kind 추가
- `shared/Core/Services/CalendarWidgetSnapshot.swift`
  - lock-screen day summary, coverage, 이전 JSON decode, 파일 보호, board deep link
- `shared/Core/Services/BoundedQueryService.swift`
  - bounded widget Task descriptor
- `shared/Tests/CalendarWidgetSnapshotTests.swift`
  - summary round-trip, legacy decode, 가용성, content 비교, board deep link
- `mobile/App/CalendarWidgetSnapshotPublisher.swift`
  - day summary 발행, readiness gate 및 두 widget kind reload
- `mobile/App/PlanBaseMobileApp.swift`
  - publisher readiness와 board today deep link 처리
- `mobile/Widget/PlanBaseCalendarWidget.swift`
  - private 가용성 enum을 공통 타입으로 교체하고 `WidgetBundle`에 새 widget 등록
- `PlanBase.xcodeproj/project.pbxproj`
  - 새 widget source target membership
- `docs/ARCHITECTURE.md`
  - 홈 화면/잠금 화면 family, lock-screen day summary 계약, deep link 설명

SwiftData schema, migration plan, backup codec, CloudKit schema, entitlement, 기존 widget kind와 App Group ID는 수정하지 않는다.

## 10. 단계별 구현 순서

### Phase 0. 기준 계약과 preview fixture

- 캘린더 위젯 밀도 계획의 v3 snapshot, 가용성 상태, bounded publisher 구현과 테스트가 안정화됐는지 확인한다.
- 밀도 개선 구현의 private 가용성 enum을 공통 Widget Extension 타입으로 추출할 경계를 확인한다.
- accessory 세 family의 preview fixture를 만든다.
- fixture는 정상 빈 상태, 갱신 필요, 앱 업데이트 필요, Task 상태 혼합, 일정 다수, 긴 한글·영문 제목, 구버전 snapshot을 포함한다.
- 기존 홈 화면 위젯의 Light/Dark preview를 기준 화면으로 보존한다.

완료 조건:

- family별 표시 정보와 tap destination이 이 문서와 일치한다.
- 밀도 개선 v3가 통합되고 lock-screen 확장이 v4를 사용한다.

### Phase 1. 공통 순수 규칙과 snapshot 호환

- `LockScreenWidgetRules`와 8일 day summary를 구현한다.
- lock-screen coverage, 이전 payload 가용성, 파일 보호를 구현한다.
- board today/date deep link 생성·파싱을 추가한다.
- 공통 단위 테스트를 먼저 통과시킨다.

완료 조건:

- v1~v3을 읽되 lock-screen summary가 없으면 정상 빈 상태가 아닌 `needsRefresh`로 판단한다.
- 같은 입력은 항상 같은 Task 요약과 표시 우선순위를 만든다.
- v3 writer가 미래 v4 snapshot을 덮어쓰지 않는다.
- SwiftData schema 변경이 없다.

### Phase 2. bounded publisher 확장

- coverage 범위의 Task/Event를 fetch해 최소 day summary를 event snapshot과 함께 원자적으로 쓴다.
- DataIntegrity reconciliation 성공 뒤 readiness를 열고 최초 발행한다.
- 앱의 데이터 변경 및 CloudKit 수렴 신호에 연결한다.
- 기존 calendar kind와 새 lock-screen kind를 내용 변경 시 reload한다.
- 전체 Task 테이블을 상시 관찰하지 않는지 확인한다.

완료 조건:

- Task 추가·상태 변경·완료 후 잠금 화면 snapshot 내용이 갱신된다.
- 동일 내용 재발행은 파일 write와 timeline reload를 생략한다.
- 구버전 또는 손상 snapshot이 안전하게 수렴한다.
- reminder 보존 완료 저장 뒤에도 같은 변경 알림으로 summary가 갱신된다.

### Phase 3. accessory UI와 WidgetBundle 등록

- `PlanBaseLockScreenWidget`을 만들고 세 accessory family만 선언한다.
- `PlanBaseWidgetBundle`에 기존 calendar widget과 함께 등록한다.
- family별 provider 상태, SwiftUI view, privacy, 접근성, `containerBackground`, rendering mode를 적용한다.
- 새 source를 Widget Extension target에 등록한다.

완료 조건:

- 잠금 화면 widget gallery에 `PlanBase 오늘`이 나타난다.
- 기존 `PlanBase 캘린더` 홈 화면 위젯의 family와 표시가 유지된다.
- 잠금 화면 테마·배경색에 관계없이 핵심 내용이 읽힌다.
- 정상 빈 상태와 갱신 필요·앱 업데이트 필요가 서로 다른 문구로 표시된다.

### Phase 4. 앱 이동과 수명주기 검증

- 세 family의 tap을 `scope=today` board deep link에 연결한다.
- 앱 cold/warm/background 상태의 route를 검증한다.
- 날짜 변경, 시간대 변경, 앱 재실행, CloudKit import 후 snapshot 갱신을 검증한다.

완료 조건:

- 위젯 탭이 timeline entry 날짜가 오래됐어도 앱 처리 시점의 오늘 보드를 연다.
- 날짜가 바뀐 뒤 전날 Task를 오늘 Task처럼 표시하지 않는다.
- coverage 밖, 구버전 summary 없음, 읽기 실패가 실제 빈 상태와 구분된다.

### Phase 5. 선택적 인터랙션 설계 결정

- 실제 기기에서 읽기 전용 위젯 사용성을 확인한 뒤 완료 버튼 또는 ControlWidget의 필요성을 평가한다.
- 직접 완료가 필요하면 AppIntent 실행 프로세스, 인증 정책, rollback, CloudKit 수렴, widget reload를 별도 설계 문서로 확정한다.
- 미래 알림 Task는 위젯에서 바로 완료하지 않고 앱의 확인 alert를 연다.
- 데이터 저장 경계를 바꾸는 구현은 데이터 안전 검토 없이 진행하지 않는다.

## 11. 테스트 계획

### 공통 단위 테스트

1. 오늘 `todo`, `doing`, `done` 개수를 정확히 계산한다.
2. 과거에 계획됐지만 오늘 완료한 Task는 오늘 완료 수에 포함한다.
3. 오늘 계획됐지만 다른 날 완료한 Task는 오늘 완료 수에 포함하지 않는다.
4. archive 및 superseded Task를 제외한다.
5. 이월 Task를 기본 오늘 개수에 포함하지 않는다.
6. 대표 제목은 진행 중 Task, 첫 CalendarEvent, 첫 todo Task 순으로 선택한다.
7. 같은 상태에서는 `order`, 제목, ID 순으로 결과가 결정적이다.
8. 여러 날 CalendarEvent가 오늘 eventCount에 한 번 포함된다.
9. coverage의 데이터 없는 날짜에도 개수 0인 summary가 생성된다.
10. coverage 밖 날짜는 `availableEmpty`가 아니라 `needsRefresh`다.
11. v1~v3 JSON은 캘린더 데이터를 읽되 lock-screen summary 가용성은 `needsRefresh`다.
12. 미래 schema는 덮어쓰지 않고 `requiresAppUpdate`로 판단한다.
13. summary 내용이 같고 `generatedAt`만 다른 snapshot은 같은 content로 판단한다.
14. summary 또는 coverage가 바뀌면 다른 content로 판단한다.
15. board today/date와 calendar deep link가 두 scheme에서 round-trip한다.
16. `scope=today`와 `date`가 함께 있거나 날짜·host·scheme이 잘못된 route를 거부한다.

### iOS 통합 테스트

알림 보존 계획에서 추가하는 `PlanBaseMobileTests` 타겟을 재사용한다.

1. App Group snapshot 파일이 원자적으로 기록되고 파일 보호 수준이 최초 사용자 인증 이후 접근 가능으로 설정된다.
2. 재부팅 후 최초 잠금 해제 전과 유사한 파일 접근 오류가 `availableEmpty`로 바뀌지 않는다.
3. provider의 미래 entry 날짜가 8일 coverage를 벗어나지 않고 마지막 entry 이후 새 timeline을 요청한다.

### Widget preview 및 수동 검증

1. Inline/Circular/Rectangular가 widget gallery와 실제 잠금 화면에 나타난다.
2. 정상 빈 상태만 `오늘 계획 없음`으로 표시한다.
3. snapshot 누락·손상·coverage 만료·구버전 summary 없음은 `앱을 열어 갱신`으로 표시한다.
4. 미래 schema는 `앱을 업데이트`로 표시하고 파일을 덮어쓰지 않는다.
5. Rectangular는 11pt 이상에서 개수 한 줄과 대표 제목 하나만 표시한다.
6. 긴 제목, 이모지, 한글·영문 혼합 제목이 layout을 깨뜨리지 않는다.
7. 다양한 밝기와 wallpaper tint에서 대비가 유지되고 container background 경고가 없다.
8. Always On 또는 luminance reduced 상태에서 핵심 숫자가 읽힌다.
9. `설정 > Face ID 및 암호 > 잠겨 있는 동안 접근 허용` 설정에서 개수는 유지되고 제목만 redaction된다.
10. 재부팅 후 최초 잠금 해제 전 snapshot 접근 실패가 빈 계획으로 표시되지 않는다.
11. VoiceOver가 Task/Event 실제 개수와 제목을 중복 없이 읽는다.
12. 위젯 탭이 cold/warm/background 앱에서 처리 시점의 오늘 보드를 연다.
13. 앱에서 Task를 추가·이동·완료하면 잠금 화면이 갱신된다.
14. 미래 알림 Task 완료도 저장 후 dataChangedNotification을 통해 갱신된다.
15. 다른 기기 변경은 CloudKit import와 reconciliation 이후 반영된다.
16. 자정과 시간대 변경 뒤 day key와 표시가 맞다.
17. 기존 소형·중형·대형 홈 화면 캘린더 위젯에 회귀가 없다.

### 검증 명령

공통 테스트:

```bash
swift test
```

Xcode target과 공통 API를 함께 수정하므로 최종 전체 회귀 게이트를 실행한다.

```bash
./scripts/verify-platform-builds.sh
```

추가로 `PlanBase-iOS` scheme을 실제 iOS 18 이상 기기에 설치해 잠금 화면 widget gallery, privacy, Always On, deep link를 검증한다. 일반 simulator build만으로 잠금·인증 동작을 완료로 판단하지 않는다.

## 12. 완료 기준

1. iPhone 잠금 화면에서 세 accessory family를 추가할 수 있다.
2. 오늘 Task 상태와 CalendarEvent가 공통 규칙에 따라 정확히 표시된다.
3. 실제 빈 상태, 갱신 필요, 앱 업데이트 필요가 구분된다.
4. 탭하면 timeline 지연과 관계없이 처리 시점의 오늘 보드가 열린다.
5. snapshot에는 8일간 최소 day summary와 대표 제목 하나만 추가된다.
6. 개수는 표시되고 제목은 잠금 화면 개인정보 설정에 따라 redaction된다.
7. App Group 파일은 최초 사용자 인증 이후 접근 가능한 보호 수준으로 기록된다.
8. accessory root는 제거 가능한 container background를 제공하고 원형은 시스템 표준 배경을 사용한다.
9. Rectangular는 개수 한 줄과 대표 제목 하나만 표시한다.
10. vibrant/Always On 환경에서도 색상 없이 의미를 이해할 수 있다.
11. DataIntegrity reconciliation 이후 최초 발행하며 데이터 변경 시 App Group snapshot과 두 widget timeline이 수렴한다.
12. v1~v3 snapshot을 안전하게 읽고 기존 홈 화면 위젯을 깨뜨리지 않는다.
13. Widget Extension은 SwiftData와 CloudKit을 직접 열지 않는다.
14. SwiftData/CloudKit schema 및 기존 호환 식별자를 변경하지 않는다.
15. `swift test`와 전체 플랫폼 빌드 검증이 통과한다.

## 13. 권장 출시 순서

첫 릴리스에는 읽기 전용 `PlanBase 오늘`과 board deep link만 포함한다. 실제 사용에서 가장 자주 보는 family와 정보 밀도를 확인한 뒤, 다음 릴리스에서 사용자 설정 또는 ControlWidget을 검토한다. Task 직접 완료는 인증 후 앱 프로세스에서 기존 `PersistenceCommandService.perform` 경계를 지키는 방식이 확정된 경우에만 진행한다.
