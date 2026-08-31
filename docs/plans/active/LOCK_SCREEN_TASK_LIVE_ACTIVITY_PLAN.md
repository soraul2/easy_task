# PlanBase Task 중심 잠금 화면·Live Activity 확장 계획

기준일: 2026-08-31
상태: 실시간 누적 진행 시간 포함 iOS TestFlight build 45 업로드 완료, Apple 처리·실기기 인수 대기
우선순위: iPhone → iPad → macOS

## 구현 결과 (2026-08-31)

- 잠금 화면 family별 구성을 구현했다: Inline은 오늘 CalendarEvent, Rectangular는 현재/다음
  Task와 완료 수치, Circular는 오늘 Task 빠른 추가를 담당한다.
- 오늘 `doing` Task가 있을 때만 하나를 유지하는 Live Activity와 잠금 화면·Dynamic Island
  표현, `완료/전체`, 큰 완료·다음 Task 버튼을 구현했다.
- 상태 변경 App Intent는 앱 프로세스의 기존 SwiftData container와
  `PersistenceCommandService.perform`을 사용하고, Widget Extension은 계속 App Group
  snapshot만 읽도록 경계를 유지했다.
- 이월 Task 제외, 오늘 이동 시 포함, 결정적 대표 Task 선택, 딥링크 규칙을 공통 서비스와
  단위 테스트로 고정했다.
- Debug 328개와 Release 327개 Swift Package 테스트 및 iOS/macOS Debug·Release 전체 빌드
  회귀 게이트를 통과했다.
- Live Activity의 진행 막대를 제거하고 좌측 제목·완료 수치, 우측 58×48pt 완료·다음 버튼
  구조로 개선했다. 앱·위젯 build 43, 기존 App Group·CloudKit 권한,
  `NSSupportsLiveActivities=true`를 서명 archive에서 검증한 뒤 App Store Connect 업로드에
  성공했다.
- Dynamic Island 개선판을 iOS TestFlight build 44로 archive했다. Release 테스트 327개와
  iOS Release 빌드, 앱·위젯 build number, App Group·CloudKit entitlement,
  `NSSupportsLiveActivities=true`, RunCat 5프레임 및 라이선스 포함 여부를 검증한 뒤 App Store
  Connect 업로드에 성공했다.
- build 44 실기기 확인에서 Cat이 정지 프레임으로만 보였다. Apple의 Live Activity는
  timeline 기반으로 계속 실행되지 않고, 콘텐츠 변경 애니메이션도 최대 2초로 제한되므로
  프레임 애니메이션을 안정적으로 지속할 수 없다고 결론 내렸다. Cat 코드·자산·라이선스는
  제거했다.
- Cat을 대신해 SwiftUI 시스템 timer text를 최소형·축소형·확장형과 잠금 화면에 배치했다.
  과거에 끝난 진행 구간의 `recordedDuration`과 현재 세션 경과 시간을 합산한 기준 시각을
  전달하므로 앱이 실행 중이지 않아도 누적 진행 시간이 실시간으로 증가한다.
- 실시간 누적 진행 시간과 Cat 자산 제거를 포함한 iOS TestFlight build 45는 Release 패키지
  테스트와 서명 archive 생성을 통과했다. 앱·위젯 build number, App Group·CloudKit
  entitlement, `NSSupportsLiveActivities=true`, 캘린더·플래너·잠금 화면 widget kind와
  Activity 타입 포함 여부를 검증한 뒤 App Store Connect 업로드에 성공했고 패키지 처리가
  시작됐다.
- 실제 iPhone의 잠금 인증·Always On·Dynamic Island와 iPad 잠금 화면, macOS 시스템 표현은
  Apple 처리 완료 후 실기기 인수 항목으로 남긴다.

## 1. 목표

기존 읽기 전용 `PlanBase 오늘` 잠금 화면 위젯을 Task 실행 흐름 중심으로 개편하고,
오늘 이벤트 인라인 위젯과 진행 중 Task 전용 Live Activity를 추가한다.

사용자는 잠금 화면에서 다음 흐름을 수행할 수 있어야 한다.

1. 오늘 CalendarEvent 제목을 한 줄로 확인한다.
2. 오늘 진행 중인 Task를 확인한다.
3. 진행 중인 Task가 없으면 첫 번째 계획 Task를 진행 상태로 전환한다.
4. 진행 중인 Task가 있을 때만 Live Activity로 진행률을 확인하고 완료하거나 다음 Task로
   전환한다.
5. `+` 버튼으로 앱의 오늘 Task 빠른 입력 위치를 바로 연다.

## 2. 확정 제품 결정

### 2.1 잠금 화면 구성

같은 `PlanBase 오늘` widget configuration이 family에 따라 서로 다른 역할을 맡는다.

```text
       📅 팀 미팅 · +1          accessoryInline

            10:21

┌─────────────────────────┐  ┌─────┐
│ ● 기획서 작성       3/4 │  │  ＋ │
└─────────────────────────┘  └─────┘
 accessoryRectangular       accessoryCircular

┌──────────────────────────────┐
│ 기획서 작성       [✓ 완료] [→ 다음] │
│ 3/4                          │
└──────────────────────────────┘
 진행 중 Task가 있을 때만 나타나는 Live Activity
```

- 월간 캘린더는 잠금 화면에 표시하지 않는다.
- 일정 시각과 Task 타이머는 표시하지 않는다.
- 배경화면 이미지 생성과 단축어 자동화는 사용하지 않는다.
- `3/4`는 오늘 대상 Task 중 완료 Task 수/전체 Task 수다.
- 정적 위젯과 Live Activity가 동시에 보일 때 같은 진행 수치를 표시한다.
- Task 제목은 한 줄 말줄임 처리하고, 숫자보다 제목에 우선적으로 폭을 배정한다.

### 2.2 오늘 이벤트 인라인 위젯

시계 위 `accessoryInline`은 CalendarEvent 전용으로 사용한다.

```text
이벤트 1개:   📅 팀 미팅
이벤트 여러 개: 📅 팀 미팅 · +2
이벤트 없음:   일정 없음
```

- 일정 시각은 표시하지 않는다.
- 여러 날 이벤트도 오늘 날짜가 범위에 포함되면 오늘 이벤트로 계산한다.
- 첫 이벤트는 기존 CalendarEvent 결정적 정렬을 따른다.
- 추가 개수는 `totalEventCount(onDayKey:)`를 기준으로 계산한다. count는 있지만 제한된
  snapshot에 제목이 없으면 잘못된 빈 상태 대신 `일정 N개`를 표시한다.
- 탭하면 `planbase://calendar?scope=today`로 캘린더의 오늘 화면을 연다. snapshot의 날짜를
  URL에 고정하지 않고 앱이 route를 처리하는 시점의 오늘로 해석해 자정 timeline 지연에도
  전날을 열지 않는다.
- 이벤트 제목에는 `privacySensitive()`를 적용하고 VoiceOver에는 전체 이벤트 수를 함께
  제공한다.
- privacy redaction 상태에서는 제목 대신 `일정 N개`처럼 개수만 남긴다.

### 2.3 Task 직사각형 위젯

`accessoryRectangular`은 오늘의 현재 Task 또는 다음 계획 Task 하나만 표시한다.

진행 중 Task가 있을 때:

```text
● 기획서 작성       3/4
```

진행 중 Task가 없고 계획 Task가 있을 때:

```text
▶ 기획서 작성       3/4
```

오늘 대상 Task가 없을 때:

```text
오늘 할 일 없음
```

오늘 Task를 모두 완료했을 때:

```text
✓ 오늘 완료          4/4
```

- `●`는 현재 진행 중인 Task를 뜻한다.
- `▶`는 해당 계획 Task를 `todo → doing`으로 변경하는 App Intent 버튼이다.
- 진행 중 Task가 여러 개면 기존 order, 제목, ID 정렬의 첫 Task 하나만 대표로 표시한다.
- 진행 중 Task가 없으면 같은 정렬의 첫 `todo` Task를 표시한다.
- `todo`와 `doing`은 없지만 오늘 `done`이 있으면 완료 상태와 `전체/전체`를 표시한다.
- 제목은 `.privacySensitive()`를 적용한다.
- 제목 영역을 탭하면 오늘 보드로 이동한다.
- root의 `widgetURL`은 하나만 두고 `▶`만 별도 App Intent `Button`으로 구성한다. 갱신 대기
  중인 제목과 상태에는 `invalidatableContent(_:)`를 제한적으로 적용한다.
- `▶` 실행은 잠금 상태에서 시스템 인증이 필요할 수 있으며, 인증 실패나 저장 실패 때
  snapshot을 성공 상태로 미리 바꾸지 않는다.
- privacy redaction 상태에서는 제목 대신 `진행 중` 또는 `시작 가능`을 표시하고 진행
  수치는 유지한다.

### 2.4 원형 빠른 추가 위젯

`accessoryCircular`은 숫자 요약 대신 `plus` 심볼 하나만 표시한다.

- 탭하면 `planbase://board?scope=today&action=new-task`를 연다.
- snapshot이 누락·손상·만료돼도 생성 동작은 데이터 표시와 무관하므로 `+`를 유지한다.
- 앱은 오늘 보드로 이동하고 기존 `BoardQuickAdd` 입력란에 포커스를 준다.
- 잠금 화면 안에서 직접 텍스트를 입력하거나 빈 Task를 미리 생성하지 않는다.
- 실제 저장은 사용자가 제목을 입력하고 기존 추가 동작을 실행할 때
  `PersistenceCommandService.perform`을 사용한다.

### 2.5 진행 중 Task 전용 Live Activity

Live Activity는 오늘 대상 `doing` Task가 있을 때만 존재한다.

```text
┌──────────────────────────────┐
│ 기획서 작성       [✓ 완료] [→ 다음] │
│ 3/4                          │
└──────────────────────────────┘
```

- 왼쪽: 현재 대표 `doing` Task 제목과 오늘 Task `완료/전체`
- 오른쪽: 각각 약 58×48pt의 텍스트가 포함된 완료, 다음 Task 버튼
- 작은 아이콘과 진행 막대는 제거하고 제목·진행 수치와 직접 조작 영역을 분리한다.
- 일정, 월간 캘린더, 시작 시각, 경과 시간, 남은 시간은 넣지 않는다.
- 높이는 최소 표현인 약 84~96pt를 목표로 하고 내용 때문에 160pt까지 불필요하게 늘리지
  않는다.
- 제목과 상태는 잠금 화면, Always On, 저휘도에서 읽을 수 있어야 한다.
- 제목에는 `privacySensitive()`를 적용하고 redaction 상태에서는 `진행 중인 작업`으로
  대체한다.
- 버튼은 각각 `현재 작업 완료`, `다음 작업 시작` 접근성 레이블을 제공한다.

상태별 수명주기는 다음과 같다.

```text
오늘 doing 없음
  → Live Activity 없음

앱 또는 위젯에서 todo → doing
  → Live Activity 시작

doing Task 제목·진행률 변경
  → 기존 Live Activity 갱신

✓ 완료 후 다른 doing 존재
  → 대표 doing Task로 Live Activity 갱신

✓ 완료 후 doing 없음
  → Live Activity 종료

doing → todo, 삭제, 보관, 다른 날짜로 이동 후 doing 없음
  → Live Activity 종료
```

하나의 PlanBase Live Activity만 유지한다. 중복 Activity가 발견되면 대표 하나를 남기고
나머지를 종료한다.

#### Dynamic Island 적응형 표현

```text
최소형:  12:34
축소형:  12:34  기획서 작성
확장형:  ▶ 12:34  기획서 작성              3/4
                              [✓ 완료] [→ 다음]
```

- 최소형은 제한된 폭에서 경과 시간만 표시한다.
- 축소형은 기존 `3/4` 대신 현재 Task 제목을 보여준다. 제목은 한 줄, 최대 84pt,
  privacy redaction 상태에서는 `진행 중`으로 대체한다.
- 확장형은 진행 아이콘·누적 경과 시간·제목·완료 수치와 기존 완료·다음 버튼의 의미를
  유지한다.
- 임의 이미지의 지속 프레임 애니메이션은 사용하지 않는다. Always On의 저휘도 상태에서도
  시스템이 허용하는 주기로 경과 시간과 Task 제목이 남는다.

### 2.6 Live Activity 버튼 의미

- `✓`: 현재 Task를 `done`으로 변경한다.
- `→`: 현재 Task를 `todo`로 되돌린다. 다른 오늘 `doing` Task가 이미 있으면 그것을 다음
  대표로 사용하고, 없을 때만 첫 오늘 `todo` Task를 `doing`으로 변경한다.
- 다른 `doing`과 `todo`가 모두 없으면 `→`를 숨긴다.
- `✓` 후 계획 Task를 자동으로 진행시키지는 않는다. 사용자가 `▶` 또는 `→`로 명시적으로
  시작해야 한다.
- 예정된 `reminderAt`이 남은 Task는 기존 완료 확인을 우회하지 않는다. 이 경우 `✓`는
  App Intent 버튼 대신
  `planbase://board?scope=today&action=confirm-completion&task=<UUID>`를 여는 `Link`로
  렌더링한다. 앱은 현재 Task를 다시 fetch한 뒤 기존 완료 확인 alert를 표시한다.
- 두 저장 동작은 모두 앱 프로세스의 `PersistenceCommandService.perform` 안에서
  `TaskLifecycleService.applyStatus`를 사용한다.
- `✓` 저장이 성공한 뒤에만 기존 `TaskNotificationScheduler`의 해당 Task pending 알림을
  취소한다.

## 3. 오늘 Task 집계 규칙

이월함 제외 원칙을 정적 위젯과 Live Activity에 동일하게 적용한다.

오늘 대상 Task 조건:

1. `supersededAt == nil`
2. `archivedAt == nil`
3. `plannedDayKey == 오늘`
4. 상태가 `todo`, `doing`, `done` 중 하나

따라서 과거 날짜에 남아 있는 이월 Task는 표시·집계·Live Activity 대상에서 제외한다.
사용자가 이월 Task를 오늘로 옮겨 `plannedDayKey == 오늘`이 되면 즉시 포함한다.

진행률 계산:

```text
전체 = 오늘 todo + doing + done
완료 = 오늘 done
진행률 = 완료 / 전체
```

- 전체가 0이면 진행 수치를 숨긴다.
- 완료 수는 오늘 대상 Task 기준으로 계산해 과거 이월 Task를 오늘 완료했다는 이유만으로
  분모 없이 완료 수에 추가하지 않는다.
- 같은 논리 ID의 CloudKit transient 중복은 기존 `updatedAt`, `instanceID` 대표 선택 규칙을
  유지한다.

## 4. 데이터·저장 경계

### 4.1 SwiftData와 snapshot

- 현재 `EasyTaskSchemaV8` 모델을 그대로 사용하고 새 schema나 migration을 추가하지 않는다.
- App Group 파일 이름, App Group ID, CloudKit container와 기존 widget kind를 변경하지
  않는다.
- 정적 위젯은 계속 App Group의 `CalendarWidgetSnapshot`만 읽고 SwiftData/CloudKit을 직접
  열지 않는다.
- 현재 snapshot v5의 `LockScreenWidgetDaySummary`,
  `plannerTaskPreviewsByDayKey`, CalendarEvent snapshot으로 필요한 읽기 데이터를 구성할 수
  있으므로 JSON schema version은 올리지 않는 것을 기본으로 한다.
- `LockScreenWidgetRules.doneCount`는 이월 제외 원칙과 진행률 분모가 일치하도록 오늘 계획
  Task 기준으로 재정의하고 테스트를 갱신한다.

가용성은 하나의 공통 화면 상태로 묶지 않고 family별로 판단한다.

- Inline: CalendarEvent snapshot coverage가 유효하면 Task summary 실패와 무관하게 표시
- Rectangular: Task summary와 planner preview coverage가 모두 유효할 때 표시
- Circular: snapshot 상태와 무관하게 항상 빠른 추가 표시
- 미래 snapshot schema는 데이터를 해석하는 Inline/Rectangular에서 업데이트 필요 표시

### 4.2 App Intent 저장 경계

위젯과 Live Activity 버튼은 원본 저장소를 Widget Extension에서 직접 수정하지 않는다.

1. 상태를 변경하는 `▶`, `✓`, `→`는 `LiveActivityIntent`로 정의해 앱 프로세스에서
   실행한다.
2. 논리 Task ID로 활성 후보를 bounded fetch하고 `updatedAt`, `instanceID` 순서로 현재 대표
   레코드를 선택한다. 기존 `fetchLimit = 1` descriptor의 unique 가정에 의존하지 않는다.
3. 현재 상태와 오늘 대상 여부를 다시 검증한다.
4. `PersistenceCommandService.perform`에서 상태 전환과 진행 이벤트 기록을 함께 저장한다.
5. 성공 후 widget snapshot을 다시 발행하고 timeline과 Live Activity를 갱신한다.
6. 실패하면 rollback하고 기존 UI 상태를 유지한다.

앱 프로세스 intent가 현재 `ModelContainer`를 안전하게 재사용할 수 있도록 앱 시작 시
container를 등록하는 작은 runtime/coordinator 경계를 둔다. 별도 App Group 저장소나 command
queue는 만들지 않는다.

Intent 실행 시 SwiftUI root observer가 활성 상태라고 가정하지 않는다. intent의
`perform()`이 저장 완료 후 snapshot 발행과 Live Activity coordinator 호출을 직접 await한
뒤 반환한다.

앱과 extension이 함께 컴파일하는 Intent 타입은 parameter와 명령 프로토콜만 포함한다.
SwiftData, `ModelContainer`, snapshot publisher와 Activity coordinator를 사용하는 concrete
executor는 iPhone 앱 타겟에만 두고 앱 프로세스 dependency로 등록한다. Widget Extension에는
원본 저장소 접근 코드가 링크되지 않게 한다.

`→`의 다음 후보는 current Task 상태를 바꾸기 전에 결정하고 current logical ID를 제외한다.
Intent 실행 시 상태가 달라졌으면 후보를 다시 계산하며, stale payload의 Task를 임의로
전환하지 않는다.

### 4.3 Live Activity 상태 payload

Activity attributes는 Activity 동안 변하지 않는 값만 보관한다. `→` 동작이나 여러 doing
Task의 대표 교체로 현재 Task와 Task 진행 세션이 바뀔 수 있으므로 두 값 모두 immutable
attributes에 넣지 않고 갱신 가능한 ContentState에 둔다.

```text
PlanBaseTaskActivityAttributes
  activityID
  dayKey

ContentState
  taskSessionID
  taskID
  title
  completedCount
  totalCount
  hasNextTask
  requiresCompletionConfirmation
  elapsedTimerStartedAt (wire key: updatedAt)
```

- 원본 Task 배열, 메모, 태그, 체크리스트 제목은 payload에 넣지 않는다.
- `elapsedTimerStartedAt`은 과거 완료 구간과 현재 진행 구간을 합친 누적 시간을 시스템 timer
  text로 표시하기 위한 기준 시각이다. build 44 진행 중 Activity와의 decode 호환성을 위해
  wire key는 기존 `updatedAt`을 유지한다.
- 서버/APNs push 업데이트는 첫 버전에서 제외하고 로컬 앱/intent 변경으로만 갱신한다.
- 사용자가 Live Activities를 비활성화했거나 시스템이 표시하지 못해도 정적 위젯과 앱 기능은
  그대로 동작해야 한다.

Task 세션은 현재 `TaskProgressEvent.started`의 Task ID와 시작 시각으로 식별한다. 기존
데이터의 doing Task처럼 started event가 없는 경우에는 논리 Task ID 기반 `legacy-doing`
세션 ID를 한 번만 사용한다. Activity 시작에 성공했거나 사용자가 표시를 거부·종료한 세션
ID는 기기 로컬의 bounded receipt store에 기록한다.

- 새 `todo → doing` 전환은 새 Task 세션이므로 Activity를 시작할 수 있다.
- 이미 처리한 세션의 Activity가 시스템 종료 또는 사용자 제거로 사라지면 generic app
  launch, `scenePhase.active`, snapshot refresh가 같은 Activity를 다시 만들지 않는다.
- 활성 Activity가 남아 있으면 app launch와 data change에서 내용만 update/end한다.
- `→`로 Task 세션이 바뀌어도 오늘 Activity 하나의 ContentState만 교체한다.
- receipt는 CloudKit에 동기화하지 않는 기기별 UI 상태이며 최근 세션만 bounded하게
  보관한다.

## 5. 플랫폼별 표현

### 5.1 iPhone 우선

- 잠금 화면: 위 확정 레이아웃 전체를 구현한다.
- Dynamic Island compact: leading에 누적 진행 시간, trailing에 현재 Task 제목을 표시한다.
- Dynamic Island minimal: 누적 진행 시간만 표시한다.
- Dynamic Island expanded: 진행 아이콘·누적 진행 시간·제목·진행 수치와 큰 완료·다음 버튼을
  표시한다.
- Dynamic Island가 없는 기기도 잠금 화면 Live Activity가 동일 의미를 유지해야 한다.

### 5.2 iPad

- iOS 공통 accessory family와 Live Activity state를 재사용한다.
- 더 넓은 폭에서도 정보를 추가하지 않고 제목의 말줄임 여유만 늘린다.
- Stage Manager, 가로·세로, 잠금 화면 preview를 확인한다.

### 5.3 macOS

- iPhone과 iPad 승인 뒤 ActivityKit이 제공하는 macOS 표현을 검증한다.
- macOS 때문에 iPhone payload나 정보 계층을 확장하지 않는다.
- 네이티브 macOS에서 지원되지 않는 잠금 화면 accessory UI를 별도로 흉내 내지 않는다.
- macOS 지원이 시스템 전달 범위에 한정되면 그 사실을 출시 문서에 명시한다.

## 6. 구현 단계

### Phase 1. 공통 표시 규칙과 테스트

- 오늘 대상 Task, 완료/전체 진행률, 대표 doing/todo, 다음 Task 선택 규칙을 공통 서비스로
  고정한다.
- 이월함 제외와 오늘 이동 포함 규칙을 기존 planner preview와 일치시킨다.
- 오늘 이벤트의 첫 제목과 `+N` 표시 규칙을 테스트한다.

완료 조건:

- 위젯과 Live Activity가 같은 fixture에서 같은 `3/4`를 만든다.
- 이월 Task는 오늘로 이동하기 전까지 집계되지 않는다.
- 여러 doing Task와 CloudKit transient 중복에서도 대표 결과가 결정적이다.

### Phase 2. 딥링크와 오늘 Task 빠른 입력

- `calendar?scope=today` 생성·파싱과 처리 시점 오늘 해석을 추가한다.
- Calendar route는 `.today`와 `.day(dayKey)`를 구분하는 타입으로 확장하고 기존
  `calendar?date=yyyy-MM-dd` 링크 동작을 유지한다.
- `board?scope=today&action=new-task` 생성·파싱을 추가한다.
- reminder 완료 확인용
  `board?scope=today&action=confirm-completion&task=<UUID>`를 추가한다.
- 앱 root가 오늘 보드 선택과 quick-add 포커스 요청을 전달한다.
- 완료 확인 route는 오늘 보드에서 현재 Task를 다시 fetch하고 기존
  `requestTaskStatusChange` 확인 흐름으로 전달한다.
- cold/warm/background 상태에서 같은 결과를 검증한다.

완료 조건:

- 원형 `+` 탭 후 빈 Task가 생성되지 않고 입력란만 활성화된다.
- Inline은 entry 생성 날짜가 지나도 처리 시점의 오늘 캘린더를 연다.
- 잘못되거나 모호한 scope/action/task/date 조합은 거부된다.

### Phase 3. 잠금 화면 accessory UI 개편

- Inline을 오늘 CalendarEvent 제목 전용으로 변경한다.
- Rectangular를 한 줄 Task 제목·진행률·`▶` 상태로 변경한다.
- Circular를 `+` 전용으로 변경한다.
- 기존 entry의 단일 availability 판단을 event/task/action family별 상태로 분리한다.
- 정상 빈 상태, 갱신 필요, 앱 업데이트 필요 표현을 family별로 유지한다.

완료 조건:

- 일반 iPhone 약 160×72pt rectangular와 72×72pt circular에서 잘리지 않는다.
- 기본 글자 크기를 기존 11~12pt보다 키우고 제목은 한 줄 말줄임 처리한다.
- wallpaper tint, vibrant, Always On, privacy redaction에서 읽을 수 있다.
- Task query 실패가 정상 CalendarEvent Inline을 가리지 않고, snapshot 실패가 Circular `+`를
  가리지 않는다.

### Phase 4. Task 상태 App Intent

- `▶`, `✓`, `→` intent와 앱 프로세스 persistence runtime을 구현한다.
- 기존 Task 수명주기·알림 확인·진행 이벤트 기록을 재사용한다.
- 성공 후 snapshot/timeline reload, 실패 시 rollback을 검증한다.

완료 조건:

- Widget Extension이 SwiftData/CloudKit을 열지 않는다.
- 잠금 상태 인증 취소가 Task 상태를 변경하지 않는다.
- reminder가 남은 Task를 확인 없이 완료하지 않는다.

### Phase 5. ActivityKit 수명주기

- Activity attributes와 `ActivityConfiguration`을 추가한다.
- 앱 Info.plist에 Live Activity 지원 키를 추가한다.
- app start, dataChanged, scene active, CloudKit import 후 대표 doing Task를 재평가한다.
- 시작·갱신·종료·중복 정리 coordinator를 구현한다.
- Task 세션 receipt를 사용해 app start와 scene active는 기존 Activity의 update/end만
  수행하고 이미 처리한 세션을 재시작하지 않는다.

완료 조건:

- 오늘 doing Task가 없으면 Live Activity가 존재하지 않는다.
- 앱 또는 `▶`에서 doing이 시작되면 Live Activity가 시작된다.
- 현재 Task와 진행률 변경이 기존 Activity에 반영된다.
- 마지막 doing이 사라지면 Activity가 종료된다.
- 사용자가 제거했거나 시스템이 끝낸 같은 Task 세션을 앱 활성화만으로 다시 시작하지
  않는다.

### Phase 6. 플랫폼·출시 검증

- iPhone 실기기에서 잠금, 인증, Always On, Dynamic Island, cold/warm route를 확인한다.
- iPad 레이아웃을 확인하고 macOS 시스템 표현의 지원 범위를 기록한다.
- 전체 회귀 게이트 후 TestFlight 빌드를 업로드한다.

## 7. 예상 변경 파일

### 공통 코어

- `shared/Core/Services/LockScreenWidgetRules.swift`
  - 오늘 대상 완료율과 대표 Task 규칙 보완
- `shared/Core/Services/CalendarWidgetSnapshot.swift`
  - 기존 날짜 route를 보존한 calendar today, new-task, confirm-completion deep link
    생성·파싱
- `shared/Tests/LockScreenWidgetRulesTests.swift`
  - 이월 제외, 대표 Task, 진행률 테스트
- `shared/Tests/CalendarWidgetSnapshotTests.swift`
  - deep link action round-trip/거부 테스트

### iPhone 앱

- `mobile/App/PlanBaseMobileApp.swift`
  - calendar today/new-task/confirm-completion route, quick-add 포커스, Live Activity
    reconciliation 연결
- `mobile/App/Features/Board/MobileBoardView.swift`
- `mobile/App/Features/Board/MobileBoardComponents.swift`
  - 외부 quick-add 포커스 요청 수용
- `mobile/App/Infrastructure/TaskLiveActivityCoordinator.swift` 신규
  - Activity 시작·갱신·종료·중복 정리와 Task 세션 receipt
- `mobile/App/Infrastructure/PlanBaseTaskIntentRuntime.swift` 신규
  - 앱 프로세스 저장 명령과 container 경계
- `mobile/Configuration/PlanBase-iOS-Info.plist`
  - Live Activity 지원 선언

### Widget Extension

- `mobile/Widget/PlanBaseLockScreenWidget.swift`
  - Inline/Rectangular/Circular 역할과 family별 가용성 개편
- `mobile/Widget/PlanBaseTaskActivityAttributes.swift` 신규
  - 앱과 extension 양쪽 target membership
- `mobile/Widget/PlanBaseTaskLiveActivity.swift` 신규
  - Lock Screen/Dynamic Island ActivityConfiguration
- `mobile/Widget/PlanBaseTaskWidgetIntents.swift` 신규
  - `▶`, `✓`, `→` intent 정의
- `mobile/Widget/PlanBaseWidgetBundle.swift`
  - Live Activity configuration 등록
- `PlanBase.xcodeproj/project.pbxproj`
  - 신규 파일과 app/widget target membership

파일명과 분리는 구현 시 현재 Xcode target dependency를 확인해 조정할 수 있지만, app
process 저장과 extension 렌더링 경계는 유지한다.

## 8. 테스트 계획

### 공통 단위 테스트

1. 오늘 `todo`, `doing`, `done`으로 `3/4`를 정확히 만든다.
2. 과거 이월 Task는 제외하고 오늘로 옮기면 포함한다.
3. 대표 Task는 doing 우선, 없으면 todo이며 정렬이 결정적이다.
4. 완료 후 다음 doing이 있으면 대표 Task가 교체된다.
5. 전체 0일 때 ratio와 progress를 표시하지 않는다.
6. 오늘 Task가 전부 완료되면 `오늘 완료 4/4`를 표시한다.
7. 오늘 CalendarEvent 1개/여러 개/0개와 여러 날 이벤트 문구를 만든다.
8. event count는 있지만 제목이 제한된 snapshot에 없으면 `일정 N개`를 표시한다.
9. calendar today, new-task, confirm-completion deep link가 두 지원 scheme에서
   round-trip한다.
10. 모호하거나 잘못된 scope/action/task/date 조합을 거부한다.

### 저장·Intent 테스트

1. `▶`가 선택 Task만 `doing`으로 바꾸고 progress started event를 기록한다.
2. `✓`가 완료·완료 활동·progress stopped event를 하나의 transaction으로 저장한다.
3. reminder가 남은 Task는 직접 완료하지 않는다.
4. `→`가 현재 Task를 todo로 바꾸고, 기존 다른 doing을 우선하며 없을 때만 다음 todo를
   doing으로 원자적으로 바꾼다.
5. stale/superseded/다른 날짜 Task ID 요청을 거부한다.
6. 같은 논리 ID의 transient 중복에서 현재 대표만 결정적으로 선택한다.
7. 저장 실패가 rollback되고 성공 snapshot을 발행하지 않는다.

### Live Activity 테스트

ActivityKit 호출을 adapter protocol로 감싸 fake 구현으로 아래를 검증한다.

1. doing 없음 → 시작하지 않음
2. 첫 doing 생성 → 하나 시작
3. 같은 상태 재평가 → 중복 시작하지 않음
4. 제목·진행률 변경 → update
5. 대표 doing 변경 → 같은 Activity ContentState 교체
6. 마지막 doing 종료 → end
7. 중복 Activity 발견 → 대표 하나 외 종료
8. Live Activity 권한 비활성 → 정적 위젯과 저장 동작 유지
9. 이미 처리·제거된 Task 세션 + scene active → 재시작하지 않음
10. 새 todo → doing 세션 → 새 Activity 시작 가능

### Preview·실기기 인수

1. 긴 한글/영문/이모지 제목과 기본·큰 글자 크기
2. Inline/Rectangular/Circular gallery와 실제 잠금 화면
3. Dynamic Island compact/minimal/expanded
4. 잠금 인증 성공·취소와 reminder 완료 확인
5. privacy redaction, Always On, 저휘도, Light/Dark
6. 자정·시간대 변경과 App Group coverage 만료
7. CloudKit import 뒤 앱이 활성화됐을 때 snapshot/Activity 수렴
8. iPhone 우선 인수 후 iPad, 마지막으로 macOS 표현 확인
9. Task snapshot 오류 중에도 Inline event와 Circular `+`의 독립 동작 확인

검증 명령:

```bash
swift test
./scripts/verify-platform-builds.sh
```

ActivityKit과 잠금 인증은 simulator 빌드만으로 완료 처리하지 않고 실제 iOS 18 이상 기기
검증을 필수로 한다.

## 9. 알려진 제약

- 잠긴 기기에서 위젯/Live Activity 버튼은 시스템 인증이 필요할 수 있다.
- CloudKit에서 다른 기기가 상태를 바꿔도 iPhone 앱이 import하고 실행 기회를 얻기 전에는
  로컬 Live Activity를 즉시 시작하거나 갱신할 수 없다. 첫 버전에는 서버 push-to-start를
  넣지 않는다.
- WidgetKit timeline 갱신 시점은 시스템이 조정하므로 intent 성공 직후 짧은 표시 지연이
  있을 수 있다.
- 사용자가 Live Activities를 비활성화하면 Live Activity는 표시하지 않으며 Task 위젯만
  사용한다.
- `doing` Task가 시스템의 Live Activity 권장 지속 시간보다 오래 유지돼도 Activity를
  반복 재시작해 상시 고정하지 않는다. 시스템이 종료한 뒤에는 정적 Task 위젯이 상태를
  계속 보여 주고, 다음 명시적 상태 전환 때 새 Activity를 시작한다.
- 제목은 잠금 화면에 노출될 수 있으므로 privacy 설정과 redaction을 실기기에서 확인해야
  한다.

## 10. 완료 기준

1. Inline에서 오늘 이벤트 제목과 추가 개수를 확인하고 오늘 캘린더로 이동한다.
2. Rectangular에서 대표 doing Task 또는 시작 가능한 첫 todo Task와 오늘 진행률을 본다.
3. Circular `+`가 오늘 보드 quick-add를 정확히 연다.
4. `▶`가 오늘 계획 Task를 진행 상태로 안전하게 변경한다.
5. Live Activity는 오늘 doing Task가 있을 때만 하나 존재한다.
6. Live Activity에 제목, 완료/전체, 큰 완료·다음 버튼이 표시된다.
7. `✓`, `→`가 기존 저장·알림·progress event 규칙을 우회하지 않는다.
8. 이월 Task는 오늘로 옮기기 전까지 모든 잠금 화면 집계에서 제외된다.
9. 정적 위젯은 App Group snapshot만 읽고 원본 저장소를 열지 않는다.
10. SwiftData/CloudKit schema와 배포 호환 식별자를 변경하지 않는다.
11. 관련 단위·통합 테스트와 전체 플랫폼 빌드가 통과한다.
12. iPhone 실기기 인수 후 iPad, macOS 순으로 확인하고 TestFlight 빌드를 업로드한다.

## 11. 공식 구현 기준

- [Widgets HIG](https://developer.apple.com/design/human-interface-guidelines/widgets)
- [Live Activities HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent)
- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [Linking to specific app scenes](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity)
