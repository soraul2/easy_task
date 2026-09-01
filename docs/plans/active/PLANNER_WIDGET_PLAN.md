# PlanBase 월간 일정·오늘 작업 결합 플래너 위젯 구현 계획

기준일: 2026-08-31
최종 갱신: 2026-09-01
상태: iOS/macOS TestFlight build 60 서명 업로드 완료 — 실제 gallery·시각·접근성 인수 대기
우선순위: iPhone → iPad → macOS

## 1. 목표

기존 월간 캘린더 위젯과 오늘 작업 요약을 하나의 큰 위젯에서 함께 확인할 수 있는
`PlanBase 플래너`를 추가한다. 사용자는 앱을 열지 않고도 이번 달의 일정 분포와 오늘
실행할 Task를 동시에 파악하고, 필요한 날짜의 캘린더 또는 오늘 보드로 바로 이동할 수
있어야 한다.

첫 버전의 핵심 목표는 다음과 같다.

1. 기존 `PlanBase 캘린더`와 `PlanBase 오늘` 위젯을 대체하지 않고 별도 위젯으로
   제공한다.
2. iPhone `systemLarge`에서 월간 일정과 오늘 Task를 좌우로 읽을 수 있게 한다.
3. iPad `systemExtraLarge`에서는 같은 정보 구조를 유지하면서 일정 제목과 Task 표시량을
   확장한다.
4. macOS는 iPhone과 iPad에서 확정된 공통 레이아웃과 snapshot을 재사용하고 별도 데이터
   경로를 만들지 않는다.
5. 위젯은 기존처럼 SwiftData 또는 CloudKit을 직접 열지 않고 App Group JSON snapshot만
   읽는다.
6. Task 완료·상태 변경은 첫 버전에 넣지 않고 조회와 딥 링크에 집중한다.

## 2. 계획 기준선

### 2.1 현재 구현에서 확인된 기반

- `PlanBaseWidgetExtension`은 iPhone, iPad, macOS를 함께 지원한다.
- 기존 캘린더 위젯은 `systemSmall`, `systemMedium`, `systemLarge`,
  `systemExtraLarge`를 등록한다.
- `CalendarWidgetMonthGrid`는 `GeometryReader`가 전달한 실제 크기로 날짜 셀, row 높이,
  event lane 수를 계산한다.
- iOS와 macOS 앱은 동일한 `CalendarWidgetSnapshotPublisher`를 사용한다.
- publisher는 이미 오늘을 포함한 8일 범위의 예정 Task와 완료 Task를 bounded query로
  조회한다.
- Task 제목, 상태, 날짜, 순서가 바뀌면 `taskFingerprint`가 변하고 snapshot 발행이
  재요청된다.
- snapshot v4에는 월간 CalendarEvent, 날짜별 event count, 8일 Task/Event 개수와 대표
  제목 하나가 들어 있다.
- `PlanBaseDeepLink`는 캘린더 날짜, 오늘 보드, 명시 날짜 보드 route를 이미 지원한다.
- snapshot이 없거나 손상됐거나 coverage가 만료된 상태와 실제 빈 데이터를 구분한다.

### 2.2 2026-08-31 확인 결과

- [x] 작업 시작 시 `git status --short`가 clean이었다.
- [x] iPhone/iPad 공통 iOS Simulator Debug 빌드가 widget extension 포함 상태로 통과했다.
- [x] macOS Debug 빌드가 native widget extension 포함 상태로 통과했다.
- [x] `swift test --filter Widget`으로 선택된 위젯 관련 Swift Testing 테스트 23개가
  통과했다.
- [x] 위젯 target의 `TARGETED_DEVICE_FAMILY`가 `1,2`이고 지원 플랫폼이
  `iphoneos iphonesimulator macosx`임을 확인했다.

이 결과는 계획 수립 시점 기준선이다. 실제 구현 시작 시 worktree와 빌드 결과를 다시
확인한다.

### 2.3 2026-08-31 구현 결과

- [x] 별도 `PlanBase 플래너` 위젯과 planner 전용 kind·월 이동 상태를 추가했다.
- [x] snapshot v5에 8일 범위의 날짜별 Task preview를 추가했다.
- [x] 이월함 작업은 제외하고 사용자가 예정일을 오늘로 옮긴 작업만 오늘 preview에
  포함한다.
- [x] `doing` 우선, `todo` 다음 순서로 최대 6개를 표시하고 초과분은 `+N`으로 표시한다.
- [x] Large는 58/42, Extra Large는 62/38 좌우 분할을 기본으로 실제 폭에 따른 상하
  fallback을 적용했다.
- [x] Large 달력은 일정 색상 막대와 `+N`, 폭이 충분한 Extra Large는 일정 제목을
  표시한다.
- [x] 날짜는 해당 캘린더로, Task pane 전체는 오늘 보드로 이동하며 첫 버전은 읽기
  전용이다.
- [x] SwiftPM Debug 323개·Release 322개 테스트, Xcode snapshot integration 테스트
  3개, iOS/macOS Debug·Release 전체 빌드와 host embed 검증을 통과했다.
- [x] iOS `1.0 (40)` 서명 archive의 App Group·CloudKit entitlement와 planner widget kind를
  확인한 뒤 App Store Connect 업로드에 성공했다.
- [x] build 40 확인 피드백 뒤 가로형 참고 이미지처럼 왼쪽 오늘 Task와 오른쪽 미니 월간
  달력을 얇은 구분선으로 나눈 `systemMedium` 레이아웃을 추가했다.
- [x] iOS와 macOS build 60 서명 archive에서 플래너 kind, host embed와 App Group
  권한을 다시 확인하고 두 플랫폼 모두 App Store Connect에 업로드했다.
- [ ] 실제 iPhone, iPad, Mac의 위젯 gallery와 홈 화면/바탕화면에서 최종 시각·접근성
  인수를 진행한다.

## 3. 확정 제품 결정

### 3.1 별도 위젯으로 추가한다

- gallery 표시 이름은 `PlanBase 플래너`로 한다.
- 기존 캘린더 widget kind와 잠금 화면 widget kind를 변경하지 않는다.
- 새 kind는 `PlanBaseCompatibility`에 추가하고 출시 후 호환 식별자로 취급한다.
- 제안 kind 값은 `com.soraul2.easytask.planner-widget`이다.
- 기존 `calendar-widget-v1.json` snapshot 파일을 공유하고 별도 App Group 파일이나
  persistence stack을 만들지 않는다.
- 기존 캘린더 위젯을 설치한 사용자의 크기·표시·월 이동 상태를 강제로 바꾸지 않는다.

### 3.2 지원 family

| 플랫폼 | 1차 지원 family | 제품 결정 |
|---|---|---|
| iPhone | `systemMedium`, `systemLarge` | Medium은 간결한 가로형, Large는 상세 결합형 |
| iPad | `systemMedium`, `systemLarge`, `systemExtraLarge` | 크기에 따라 표시 밀도 확장 |
| macOS | `systemMedium`, `systemLarge`, `systemExtraLarge` | iOS와 같은 공통 구성 재사용 |

- `systemSmall`은 두 영역을 함께 읽을 수 없으므로 지원하지 않는다.
- `systemMedium`은 5~6개 목록을 억지로 넣지 않고 오늘 Task 최대 2개와 초과 개수,
  일정이 있는 날짜 점 표시가 포함된 미니 월간 달력을 좌우로 보여 준다.
- 실제 gallery 노출은 각 OS와 기기의 WidgetKit 정책을 따른다.
- `systemSmall`을 원하는 사용자는 기존 `PlanBase 캘린더`와 잠금 화면 `PlanBase 오늘`을
  계속 사용한다.

### 3.3 레이아웃은 family 이름보다 실제 가용 폭을 우선한다

기본 방향은 좌우 분할이다. 플랫폼 이름으로 고정 분기하지 않고 `GeometryReader`의 실제
content bounds로 calendar pane과 task pane이 최소 폭을 확보하는지 판단한다.

`systemMedium`은 참고 이미지의 정보 계층을 따라 별도 간결형을 사용한다.

```text
┌──────────────────┬────────────────────┐
│ 8월 31일          │ 일 월 화 수 목 금 토 │
│ 남은 3 · 완료 2   │       1  2  3  4   │
│ ◉ 진행 중 Task    │  5  6  7  8  9 ... │
│ ○ 예정 Task       │       월간 미니 달력 │
│           +1개 더 │      일정 날짜 · 표시 │
└──────────────────┴────────────────────┘
```

```text
┌──────────────────────┬────────────────┐
│ 2026년 8월       ‹ › │ 오늘           │
│ 일  월  화  수  목  금  토 │ 남은 4 · 완료 2 │
│                      │                │
│      월간 달력        │ ◉ 진행 중 Task  │
│   일정 색상 막대·점    │ ○ 예정 Task    │
│                      │ ○ 예정 Task    │
│                 +2  │           +1  │
└──────────────────────┴────────────────┘
```

- iPhone Large 기본 비율은 calendar 58%, task 42%에서 시작한다.
- iPad/macOS Extra Large 기본 비율은 calendar 62%, task 38%에서 시작한다.
- calendar pane이 약 190pt, task pane이 약 120pt 미만이 되는 실제 context에서는 글자를
  계속 줄이지 않고 상하 fallback 또는 정보량 축소를 선택한다.
- 최종 비율과 최소 폭은 preview의 임의 고정 크기가 아니라 지원 기기 실제 bounds와
  Dynamic Type 기본 크기에서 결정한다.
- safe fallback이 필요해도 iPhone Large의 승인 기준은 좌우형이다.

### 3.4 월간 일정 pane

- 기존 연속형 5·6주 월간 표와 공통 `CalendarEventGridLayout`을 재사용한다.
- iPhone Large에서는 날짜, 오늘 표시, 일정 색상 막대와 날짜별 `+N`을 우선한다.
- iPhone Large의 event bar에는 제목을 넣지 않고 색상 막대와 `+N`만 표시한다.
- iPad/macOS Extra Large에서는 실제 calendar pane 폭이 충분할 때 event 제목을 표시한다.
- 날짜·요일은 8pt, `+N`은 7pt, Task 제목과 Extra Large event 제목은 11pt를 가독성
  하한으로 삼고 공간이 부족하면 lane이나 표시 행 수를 줄인다.
- 여러 날 이벤트는 기존처럼 주간 segment로 이어서 표시한다.
- 날짜를 누르면 `planbase://calendar?date=...`로 해당 날짜 캘린더를 연다.
- 월 제목을 누르면 이번 달로 돌아오고 좌우 버튼으로 snapshot coverage 안에서 월을
  이동한다.
- Task pane이 항상 오늘을 뜻한다는 사실과 선택 월을 혼동하지 않도록 `오늘` 헤더를
  독립적으로 유지한다.

### 3.5 오늘 Task pane

- 헤더에는 `오늘`, 날짜, `남은 N · 완료 N`을 표시한다.
- 남은 수는 기존 보드 의미대로 `todo + doing`으로 계산한다.
- 표시 우선순위는 `doing` 다음 `todo`이며, 각 그룹 안에서는 기존 Task order, 제목,
  ID의 결정적 정렬을 사용한다.
- iPhone Large부터 가용 높이에 따라 5~6개 Task 제목을 표시하고 Extra Large는 6개를
  우선한다.
- 공간을 초과한 남은 Task는 `+N`으로 알린다.
- 완료 Task는 목록 공간을 차지하지 않고 완료 개수로만 표시한다.
- Task가 없으면 `오늘 할 일이 없어요`를 표시한다.
- Task query/coverage가 없으면 실제 0개로 표현하지 않고 `PlanBase를 열면 작업을
  갱신해요`를 표시한다.
- Task 제목은 `.privacySensitive()`를 적용하고 VoiceOver에는 상태, 제목, overflow를
  중복 없이 읽어 준다.
- Task pane 전체를 하나의 Link로 만들고 누르면 오늘 보드로 이동한다. 모든 행의 목적지가
  같으므로 행마다 Link를 중첩하지 않는다.
- Task 상세 직접 열기는 별도 task-ID deep link가 없으므로 첫 버전에서 제외한다.

### 3.6 읽기 전용을 유지한다

- 위젯에서 Task 완료, 상태 전환, 순서 변경, 생성, 삭제를 제공하지 않는다.
- CalendarEvent 생성·편집·삭제도 위젯에서 제공하지 않는다.
- 체크 표시처럼 저장으로 오해할 수 있는 버튼 UI를 만들지 않는다.
- AppIntent는 월 이동과 이번 달 복귀에만 사용하고 저장 명령을 추가하지 않는다.

## 4. 데이터와 호환성 설계

### 4.1 SwiftData·CloudKit schema는 변경하지 않는다

이번 기능은 기존 Task와 CalendarEvent 값을 읽어 위젯 cache에 투영하는 작업이다.

- `EasyTaskSchemaV1`부터 현재 schema까지 수정하지 않는다.
- `EasyTaskMigrationPlan`, CloudKit Development/Production schema를 수정하지 않는다.
- 백업 DTO, codec, merge, UTI와 `.easytaskbackup` 형식을 수정하지 않는다.
- `id`, `instanceID`, `supersededAt`, 대표 레코드 선택 규칙을 우회하지 않는다.

### 4.2 widget snapshot v5

계획 당시 snapshot v4의 lock-screen summary에는 날짜별 Task 개수와 대표 제목 하나만 있어
목록을 만들 수 없다. 기존 JSON 파일을 유지하면서 optional 필드를 추가하고 schema를
v5로 올린다.

제안 값 타입:

```text
PlannerWidgetTaskPreview
  id          논리 Task ID
  renderID    대표 물리 레코드 ID
  title
  status      todo | doing
  order

CalendarWidgetSnapshot v5
  ...기존 v4 필드 유지
  plannerTaskPreviewsByDayKey: [String: [PlannerWidgetTaskPreview]]?
```

규칙:

1. 오늘만 저장하지 않고 기존 Task query coverage와 같은 8일을 저장한다.
2. 날짜가 바뀌어 앱이 즉시 실행되지 않아도 timeline이 다음 날 Task 제목을 표시할 수
   있어야 한다.
3. 날짜별 preview는 `doing` 우선, 이후 `todo` 순서로 최대 6개만 저장한다.
4. 이월함에만 남아 있는 이전 날짜의 미완료 Task는 포함하지 않는다. 사용자가 예정일을
   오늘로 변경해 `plannedDayKey == 오늘`이 되면 그때 오늘 preview에 포함한다.
5. 전체 남은 수와 완료 수는 기존 `LockScreenWidgetDaySummary`의 의미를 재사용한다.
6. preview에는 완료·보관·superseded Task를 넣지 않는다.
7. 같은 논리 ID의 transient 중복은 `updatedAt`, `instanceID` 기준 대표 하나만 선택한다.
8. Task query가 성공한 payload는 Task가 없는 날도 포함해 8개 날짜 key를 모두 저장하며,
   빈 날은 빈 배열 `[]`로 표현한다. dictionary key 누락은 빈 날이 아니라 unavailable이다.
9. v1~v4 payload는 `decodeIfPresent`로 preview가 없는 상태로 정상 decode하되 planner
   Task pane은 갱신 필요 상태로 표시한다.
10. `hasSameContent`가 preview dictionary도 비교해 제목·상태·순서 변경을 감지한다.
11. 현재보다 높은 미래 schema를 이전 앱이 덮어쓰지 않는 보호 규칙을 유지한다.
12. snapshot 파일 이름과 App Group 식별자는 바꾸지 않는다.

Task query가 실패했을 때 calendar event snapshot은 계속 발행하되 planner preview와 Task
coverage는 `nil`로 둔다. 이를 빈 Task 목록으로 정규화하지 않는다.

### 4.3 공통 Task 규칙

- planner preview 생성은 UI 파일이 아니라 `shared/Core/Services`의 순수 규칙으로 둔다.
- `LockScreenWidgetRules`의 대표 Task 선택과 정렬을 복제하지 않는다.
- 필요하면 대표 Task 선택·정렬 helper를 WidgetKit에 의존하지 않는 공통 내부 규칙으로
  추출하고 lock-screen summary와 planner preview가 함께 사용한다.
- Task status raw string을 UI가 직접 해석하지 않도록 snapshot 전용 안전 enum 또는
  validated initializer를 사용한다.
- preview 생성, 중복 수렴, 정렬, 날짜 경계, 최대 개수는 SwiftPM 단위 테스트로 고정한다.

### 4.4 성능 예산

- 날짜별 최대 6개, 8일 최대 48개 Task preview로 제한한다.
- 기존 CalendarEvent 최대 256개와 월별 count map 상한을 변경하지 않는다.
- 일반 fixture에서 App Group JSON 전체 크기 150KB 이하 목표를 유지한다.
- snapshot encode/decode 20회 반복 기준 20ms 이내 목표를 유지한다.
- widget body는 snapshot 외 파일이나 SwiftData를 추가 조회하지 않는다.
- 긴 Task 제목, 이모지, 조합 문자에서도 encode와 한 줄 truncation이 안전해야 한다.

## 5. WidgetKit 구조 설계

### 5.1 새 widget configuration

`PlanBasePlannerWidget`을 기존 `PlanBaseWidgetBundle`에 추가한다.

- `StaticConfiguration`을 사용한다.
- 새 planner kind를 사용한다.
- 지원 family는 `.systemLarge`, `.systemExtraLarge`다.
- `.contentMarginsDisabled()`와 기존 removable container background 정책을 유지한다.
- full-color에서는 앱 theme와 Light/Dark appearance를 사용한다.
- accented/vibrant에서는 색만으로 Task 상태와 이벤트 유무를 전달하지 않는다.

### 5.2 provider와 timeline

- 기존 calendar snapshot store를 읽되 planner 전용 entry/provider를 둔다.
- calendar availability와 Task availability를 분리해 한쪽 오류가 다른 쪽 정상 정보를
  가리지 않게 한다.
- timeline은 현재 시각 entry와 coverage에 포함된 이후 7개 날짜의 자정 entry를 만들고,
  각 entry가 해당 날짜의 preview와 summary를 선택한다.
- coverage 밖이거나 Task preview가 없는 날은 작업 갱신 안내를 표시한다.
- snapshot missing/corrupt/future-schema 메시지는 기존 문구와 의미를 재사용한다.

### 5.3 월 이동 상태 분리

현재 캘린더 위젯의 월 선택 key는 같은 App Group UserDefaults에 저장된다. planner가 이를
그대로 사용하면 기존 캘린더의 월 이동과 새 planner의 월 이동이 서로 영향을 준다.

- planner 전용 key `plannerWidget.selectedMonthDayKey`를 사용한다.
- planner 전용 이전 달·다음 달·이번 달 AppIntent를 둔다.
- planner intent는 planner kind timeline만 reload한다.
- 기존 calendar key와 intent의 동작을 바꾸지 않는다.
- 같은 kind의 planner 위젯 여러 개는 첫 버전에서 선택 월을 공유할 수 있다. 인스턴스별
  설정이 필요하면 향후 `AppIntentConfiguration` 전환을 별도 계획으로 검토한다.

### 5.4 snapshot reload

`CalendarWidgetSnapshotPublicationService.publish`가 내용 변경 또는 강제 갱신 시 아래
kind를 reload한다.

1. 기존 calendar kind
2. 새 planner kind
3. iOS에서만 기존 lock-screen kind

새 planner reload 실패가 calendar snapshot 쓰기 성공을 되돌리지 않게 하고, macOS에서
존재하지 않는 lock-screen kind는 계속 조건부로 제외한다.

## 6. 컴포넌트 재사용 경계

현재 `CalendarWidgetViews.swift`의 월 header, grid style, weekday header, month grid와
day cell은 `private`라 별도 planner view 파일에서 직접 사용할 수 없다.

구현 원칙:

- 월 배치 규칙을 planner view에 복사하지 않는다.
- 재사용할 월간 구성 요소의 접근 수준을 target 내부로 조정하거나 공통 파일로 추출한다.
- 기존 calendar widget의 픽셀 결과가 의도 없이 바뀌지 않도록 기존 style 값은 유지한다.
- planner 전용 `plannerCompact`/`plannerExpanded` metric을 별도로 둔다.
- `#if os(macOS)` 분기는 font metric처럼 실제 플랫폼 차이가 있을 때만 사용한다.
- orientation은 플랫폼 enum이 아니라 실제 가용 크기와 pane 최소 폭으로 결정한다.

## 7. 단계별 구현 계획

### Phase 0 — 기준점과 작업 경계 재확인

- [x] `git status --short`로 사용자 변경과 다른 작업 세션 변경을 확인한다.
- [ ] `CALENDAR_WIDGET_DENSITY_PLAN.md`, `LOCK_SCREEN_WIDGET_PLAN.md`,
  `MACOS_DESKTOP_WIDGET_PLAN.md`의 최신 상태와 충돌 파일을 다시 확인한다.
- [x] `PlanBase.xcodeproj/project.pbxproj`, `CalendarWidgetSnapshot.swift`,
  `CalendarWidgetViews.swift`, `CalendarWidgetSnapshotPublisher.swift`는 한 세션에서만
  편집한다.
- [x] 기존 `swift test --filter Widget` 결과를 기록한다.
- [x] iOS Simulator Debug와 macOS Debug scheme을 서명 없이 빌드한다.
- [ ] 기존 calendar/lock-screen gallery configuration의 preview 또는 캡처를 회귀
  기준으로 남긴다.

완료 조건:

- clean 기준점 또는 소유권이 명확한 변경 집합에서 구현을 시작한다.
- 기존 위젯 테스트와 양 플랫폼 Debug 빌드가 통과한다.

### Phase 1 — snapshot v5와 planner Task 규칙

- [x] `PlannerWidgetTaskPreview`와 안전한 status 표현을 추가한다.
- [x] 8일 날짜별 preview 생성 규칙을 공통 Core에 추가한다.
- [x] doing 우선, todo 다음, order/title/ID 결정 정렬을 테스트한다.
- [x] archived, completed, superseded, 잘못된 status Task를 preview에서 제외한다.
- [x] 같은 논리 Task의 transient 중복이 최신 대표 하나로 수렴하는지 테스트한다.
- [x] 날짜별 preview cap과 전체 remaining count가 서로 다른 의미를 유지하는지 테스트한다.
- [x] `CalendarWidgetSnapshot`을 v5로 올리고 optional preview dictionary를 추가한다.
- [x] v1~v4 decode, v5 round-trip, future-schema overwrite 보호를 테스트한다.
- [x] `hasSameContent`가 Task 제목·상태·순서·preview 증감을 감지하는지 테스트한다.
- [x] publication integration test가 실제 ModelContext의 Task를 v5 preview로 발행하는지
  확인한다.
- [x] Task query 실패 시 event snapshot은 유지되고 planner coverage는 unavailable인지
  테스트 가능한 경계로 분리한다.

완료 조건:

- SwiftData/CloudKit schema diff 없이 snapshot v5가 이전 payload를 읽는다.
- UI 없이도 오늘과 다음 날의 preview, count, 정렬 결과가 테스트로 고정된다.

### Phase 2 — iPhone systemLarge 우선 구현

- [x] `PlanBaseCompatibility.plannerWidgetKind`와 `CalendarWidgetConstants.plannerKind`, 새
  `PlanBasePlannerWidget`을 추가한다.
- [x] `PlanBaseWidgetBundle`에 planner를 등록한다.
- [x] planner provider, entry, availability, timeline을 추가한다.
- [x] calendar와 planner 월 선택 key/AppIntent/reload를 분리한다.
- [x] 기존 월간 grid 구성 요소를 복제 없이 재사용할 수 있게 정리한다.
- [x] 참고 이미지형 `systemMedium`을 추가해 왼쪽에 오늘 Task 최대 2개와 초과 개수,
  오른쪽에 현재 월의 미니 달력과 일정 날짜 점을 표시한다.
- [x] iPhone Large 좌우 58/42 layout과 최소 pane 폭 규칙을 구현한다.
- [x] planner compact calendar style은 제목 없는 event bar, 오늘, `+N`을 표시한다.
- [x] Task pane은 counts, doing/todo 행 5~6개, overflow, empty, unavailable을 표시한다.
- [x] 날짜는 각 캘린더 날짜 Link, Task pane은 하나의 오늘 보드 Link로 만들며 위젯 루트
  `widgetURL`과 중첩 Link/AppIntent control은 사용하지 않는다.
- [x] 제목과 접근성 레이블에 privacy 처리를 적용한다.
- [x] populated와 refresh 상태의 Medium/Large/Extra Large preview를 추가한다.
- [ ] 최소 지원 iPhone과 큰 화면 iPhone 시뮬레이터에서 한글·영문·이모지 긴 제목을
  확인한다.
- [ ] 기존 calendar Small/Medium/Large와 lock-screen 세 family에 시각 회귀가 없는지
  확인한다.

완료 조건:

- iPhone Medium에서 얇은 구분선 기준으로 오늘 Task와 현재 월 달력을 즉시 구분한다.
- iPhone Large에서 두 pane이 잘리지 않고 날짜·Task 제목·overflow를 읽을 수 있다.
- calendar는 선택 월, Task pane은 항상 오늘이라는 의미가 명확하다.
- 기존 위젯의 표시와 interaction이 유지된다.

### Phase 3 — iPad 적응형 확장

iPhone 완료 조건을 통과한 뒤 시작한다.

- [x] iPad Large는 iPhone과 같은 정보 우선순위와 compact style을 유지한다.
- [x] iPad Extra Large는 calendar 62%/task 38%를 기준으로 expanded style을 적용한다.
- [x] 충분한 폭에서만 event 제목과 Task 5~6개를 표시한다.
- [ ] iPad 세로·가로 홈 화면에서 WidgetKit이 제공하는 실제 family bounds를 확인한다.
- [x] pane 최소 폭 아래에서는 글자 축소보다 lane/Task 행 수 감소 또는 상하 fallback을
  적용한다.
- [ ] pointer, VoiceOver, accented/vibrant appearance에서 두 pane interaction을 확인한다.
- [ ] iPhone Large preview와 실제 표시가 iPad metric 변경으로 달라지지 않는지 확인한다.

완료 조건:

- iPad Large와 Extra Large가 같은 정보 구조를 유지하면서 가용 공간만큼 밀도를 높인다.
- iPad 대응을 위해 iPhone의 글자 크기나 pane 폭을 희생하지 않는다.

### Phase 4 — macOS 적용

iPhone과 iPad의 layout·snapshot 계약이 확정된 뒤 시작한다. 기존 native Mac calendar
widget의 서명 설치·gallery 인수 상태도 함께 확인한다.

- [x] 같은 planner widget configuration이 macOS SDK에서 조건부 복제 없이 컴파일된다.
- [x] macOS Medium은 간결형, Large/Extra Large는 실제 bounds 기반 공통 적응형 layout을
  사용한다.
- [ ] native Mac widget gallery에서 iPhone widget이 아닌 Mac 앱의 planner로 노출되는지
  확인한다.
- [ ] 바탕화면과 OS가 제공하는 알림 센터 family에서 표시를 확인한다.
- [ ] Mac 앱의 Task/Event/테마 변경과 CloudKit import가 planner timeline에 수렴하는지
  확인한다.
- [ ] 날짜와 오늘 Task Link가 native Mac 앱의 캘린더/보드 탭을 연다.
- [ ] full-color, accented, vibrant, Light/Dark에서 정보 계층과 대비를 확인한다.
- [ ] 앱 종료 상태, 자정 전환, 시간대 변경, missing/corrupt/future-schema 상태를 확인한다.

완료 조건:

- macOS 전용 데이터 또는 레이아웃 복제 없이 native planner widget이 동작한다.
- 기존 Mac calendar widget 출시 인수 항목과 충돌하거나 완료를 잘못 추정하지 않는다.

### Phase 5 — 자동 검증과 출시 인수

- [x] snapshot v5, planner rules, deep link, month navigation 테스트를 모두 통과한다.
- [x] `PlanBaseWidgetSnapshotIntegrationTests`에 Task preview publication을 추가한다.
- [x] `swift test --filter Widget`과 별도로 `PlanBaseMobileTests`의
  `PlanBaseWidgetSnapshotIntegrationTests`를 Xcode test로 실행한다.
- [x] 기존 calendar/lock-screen snapshot 테스트를 유지한다.
- [x] iOS/macOS extension 직접 Debug 빌드와 host embed 검증을 통과한다.
- [x] `swift test`와 `swift test -c release`를 통과한다.
- [x] `./scripts/verify-platform-builds.sh`를 통과한다.
- [x] `git diff --check`와 plist/entitlement lint를 통과한다.
- [x] iOS TestFlight build 40을 App Store Connect에 업로드한다.
- [x] `systemMedium` 추가본을 iOS TestFlight build 41로 업로드한다.
- [ ] 실제 iPhone에서 gallery 등록, 추가, 자정 갱신, cold/warm link를 확인한다.
- [ ] 실제 iPad에서 Large/Extra Large와 세로·가로 배치를 확인한다.
- [ ] 실제 Mac에서 native gallery, 바탕화면, 알림 센터 노출을 확인한다.
- [ ] Task 0개/1개/다수, doing/todo 혼합, 완료 다수, 긴 제목, CloudKit transient 중복,
  event lane overflow fixture를 확인한다.
- [ ] TestFlight/App Store Connect 빌드에서 기존 위젯과 planner가 함께 노출되는지 확인한다.

완료 조건:

- iPhone → iPad → macOS 순서의 인수 결과가 모두 기록된다.
- 기존 캘린더·잠금 화면 위젯과 데이터 호환성에 회귀가 없다.
- 실제 배포 빌드의 widget gallery에서 세 위젯을 구분해 선택할 수 있다.

## 8. 예상 변경 파일

### 새 파일 후보

- `shared/Core/Services/PlannerWidgetRules.swift`
  - 날짜별 Task preview, 대표 선택과 정렬 규칙
- `shared/Tests/PlannerWidgetRulesTests.swift`
  - preview 생성·정렬·중복·coverage 단위 테스트
- `mobile/Widget/PlanBasePlannerWidget.swift`
  - gallery configuration과 supported family
- `mobile/Widget/PlannerWidgetTimeline.swift`
  - entry, provider, availability와 timeline
- `mobile/Widget/PlannerWidgetViews.swift`
  - 적응형 pane layout과 Task pane
- `mobile/Widget/PlannerWidgetIntent.swift`
  - planner 전용 월 이동과 이번 달 복귀

파일 수는 구현 과정에서 책임이 작으면 합칠 수 있지만 기존 calendar/lock-screen 파일에
모든 planner 코드를 몰아넣지 않는다.

### 수정 파일

- `shared/Core/Persistence/PlanBaseCompatibility.swift`
  - 새 planner widget kind 추가, 기존 식별자 유지
- `shared/Core/Services/CalendarWidgetSnapshot.swift`
  - snapshot v5, Task preview optional field, content equality
- `shared/Core/Services/LockScreenWidgetRules.swift`
  - 대표 Task helper를 공통화할 때만 최소 수정
- `shared/WidgetSupport/CalendarWidgetSnapshotPublisher.swift`
  - preview 발행과 planner timeline reload
- `mobile/Widget/PlanBaseWidgetBundle.swift`
  - planner configuration 등록
- `mobile/Widget/CalendarWidgetViews.swift`
  - 월간 구성 요소 재사용 경계와 planner 전용 style 지원
- `mobile/Widget/CalendarWidgetIntent.swift`
  - 기존 calendar intent를 유지하며 공통 helper만 필요할 때 수정
- `PlanBase.xcodeproj/project.pbxproj`
  - 새 Swift 파일의 widget target membership
- `shared/Tests/CalendarWidgetSnapshotTests.swift`
  - v5 호환성과 equality
- `shared/Tests/LockScreenWidgetRulesTests.swift`
  - 공통 대표 선택 refactor 회귀가 있을 때 수정
- `mobile/Tests/PlanBaseWidgetSnapshotIntegrationTests.swift`
  - 실제 Task publication
- `scripts/verify-platform-builds.sh`
  - 필요 시 새 widget kind metadata/embed 검사
- `docs/ARCHITECTURE.md`
  - 세 widget이 공유하는 snapshot과 발행 흐름
- `AGENTS.md`
  - 위젯 기능 지도와 snapshot v5 반영
- `docs/README.md`
  - active/completed 계획 위치 갱신

## 9. 위험과 대응

| 위험 | 대응 |
|---|---|
| iPhone Large 좌측 7열 달력이 너무 좁음 | event 제목을 제거한 planner compact style, 최소 pane 폭, 실제 bounds 인수 |
| Task 제목 영역이 좁아 의미가 사라짐 | 11pt·1행 truncation, 상태 symbol, 5~6개 cap, calendar/task 비율 실측 조정 |
| 글자를 줄여 정보량만 늘림 | iPhone/iPad 최소 가독 크기 유지, 공간 부족 시 lane/행 수 감소 |
| 기존 calendar component refactor로 시각 회귀 | 기존 style metric 고정, planner style 분리, family별 before/after 캡처 |
| calendar와 planner 월 이동이 함께 바뀜 | planner 전용 UserDefaults key와 AppIntent, kind별 reload |
| Task query 실패가 `할 일 0개`로 보임 | Task coverage/preview optional 유지, pane 단위 refresh 상태 |
| 자정 뒤 전날 Task 제목이 남음 | 8일 preview 저장, 날짜별 timeline entry, day/time-zone 테스트 |
| snapshot v5가 이전 payload를 깨뜨림 | optional decode, v1~v4 fixture, future-schema 보호 유지 |
| snapshot 파일이 커짐 | 날짜별 6개·8일 cap, 150KB/20ms 성능 예산 |
| CloudKit transient 중복 Task가 두 번 보임 | 논리 ID 대표 선택과 `updatedAt`/`instanceID` 수렴 테스트 |
| 새 kind reload 누락 | publication service의 세 kind reload와 integration test |
| macOS 작업이 기존 native widget 출시 인수와 충돌 | iPhone/iPad 완료 후 Phase 4, Mac 계획의 미완료 release gate 병행 확인 |
| Task 완료 UI로 오해 | 첫 버전은 읽기 전용, 저장 가능한 control을 배치하지 않음 |
| 개인정보 설정에서 제목 노출 | 모든 Task/Event title에 privacySensitive와 잠금 상태 수동 검증 |

## 10. 완료 기준

다음 항목이 모두 충족돼야 계획을 `plans/completed/`로 옮긴다.

1. 기존 widget kind를 변경하지 않고 별도 `PlanBase 플래너`가 gallery에 등록된다.
2. iPhone `systemLarge` 좌우형에서 월간 일정과 오늘 Task를 동시에 읽을 수 있다.
3. iPad Large/Extra Large가 가용 폭에 따라 정보 밀도를 확장한다.
4. macOS native Large/Extra Large가 동일 snapshot과 공통 view 구조를 사용한다.
5. 월간 pane은 여러 날 이벤트, overflow, 월 이동과 날짜 딥 링크를 정확히 유지한다.
6. Task pane은 doing/todo 우선순위, 남은/완료 count, overflow와 unavailable을 정확히
   구분한다.
7. 자정과 시간대 변경 뒤 앱을 즉시 열지 않아도 8일 coverage 안에서 새 오늘 preview를
   선택한다.
8. snapshot v1~v4 decode와 미래 schema 보호가 유지되고 v5가 Task 변경을 감지한다.
9. SwiftData, CloudKit, 백업 형식과 기존 호환 식별자에는 변경이 없다.
10. 기존 calendar와 lock-screen 위젯의 UI, timeline, 딥 링크에 회귀가 없다.
11. 개인정보 보호, VoiceOver, Light/Dark, full-color/accented/vibrant 검증을 통과한다.
12. SwiftPM Debug/Release 테스트와 iOS/macOS Debug/Release build가 통과한다.
13. 실제 iPhone, iPad, Mac과 배포 빌드의 widget gallery 인수를 완료한다.

## 11. 제외 범위와 후속 후보

이번 작업에서 제외:

- 위젯 안에서 Task 완료 또는 상태 변경
- Task 생성·삭제·재정렬
- CalendarEvent 생성·편집·삭제
- 개별 Task 상세 deep link
- `systemSmall` 결합형
- 사용자별 pane 비율, Task 필터, 표시 개수 설정
- SwiftData/CloudKit을 직접 여는 widget extension
- 기존 캘린더·잠금 화면 위젯 제거 또는 자동 교체

후속 후보:

- Task ID 기반 상세 화면 딥 링크
- 인증과 rollback을 포함한 interactive Task 완료 AppIntent
- `AppIntentConfiguration`을 이용한 위젯 인스턴스별 선택 월·Task 필터
- 활동 스트릭·오늘 진행률을 Task pane에 선택적으로 표시

후속 기능은 읽기 전용 planner의 갱신 신뢰성, 사용 빈도, 개인정보 피드백을 확인한 뒤
별도 계획으로 설계한다.

이 계획의 snapshot v5는 `MACOS_DESKTOP_WIDGET_PLAN.md`의 기존 구현 범위를 소급해
변경하는 것이 아니라, 그 위에 추가되는 별도 후속 기능이다.

## 12. 권장 구현·커밋 순서

```text
1. test(widget): add planner task preview rules and v5 compatibility fixtures
2. feat(widget): publish bounded planner task previews in snapshot v5
3. refactor(widget): share month grid primitives without calendar regressions
4. feat(widget): add the iPhone large PlanBase planner configuration
5. feat(widget): adapt planner density for iPad extra large
6. feat(widget): enable and verify the native macOS planner
7. test(widget): verify cross-platform timelines, links, privacy and embedding
8. docs(widget): document planner snapshot and release operations
```
