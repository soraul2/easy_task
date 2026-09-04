# PlanBase Focus 모드·집중 타이머 구현 계획

기준일: 2026-09-03
최종 검토: 2026-09-03, V10/backup package V9/Live Activity/Watch/알림 액션 구현 및 회귀 검증 완료
상태: Phase 0~7·9, V10 Production, Focus 진입점과 종료 알림 TestFlight build 65 완료 — 실기기 인수 대기
우선순위: 공통 코어 → iPhone/iPad → macOS 플로팅 패널 → Apple Watch

## 1. 목표

PlanBase의 진행 중 Task를 화면 앞에 유지하면서 정해진 시간 동안 집중할 수 있는 Focus
모드를 추가한다. 첫 출시의 핵심 경험은 다음과 같다.

1. 보드나 Task 상세에서 작업을 선택하고 `집중 시작`을 누른다.
2. 앱 안의 Focus 화면, iPhone 잠금 화면·Dynamic Island, macOS 플로팅 패널에서 같은
   작업 제목과 남은 시간을 확인한다.
3. 실행 중인 타이머를 일시 정지·재개·조기 종료할 수 있다.
4. 집중 시간이 끝나면 알림을 받고 휴식을 직접 시작하거나 작업을 계속한다.
5. 종료된 집중 구간은 Task의 일반 진행 시간과 구분된 기록으로 저장되어 오늘 집중 횟수와
   집중 시간을 계산할 수 있다.

Focus는 포모도로 방식을 기본값으로 제공하지만 제품 이름과 데이터 모델을 `Pomodoro`로
고정하지 않는다. 이후 자유 시간, 긴 집중 세션, 반복 루틴으로 확장할 수 있도록 사용자에게는
`Focus` 또는 `집중`으로 표현한다.

## 2. 현재 기반과 변경 경계

### 2.1 재사용할 수 있는 현재 기반

- `TaskLifecycleService`는 Task 상태 변경과 `TaskProgressEvent` 기록을 같은
  `PersistenceCommandService.perform` 경계에서 처리한다.
- `TaskProgressEventRules`는 과거 진행 구간과 현재 `doing` 구간의 누적 시간을 계산한다.
- iPhone의 `TaskLiveActivityCoordinator`는 오늘 대표 `doing` Task 하나를 Live Activity로
  유지하고 잠금 화면·Dynamic Island에 누적 진행 시간을 표시한다.
- 앱 root는 앱 시작, scene 활성화, 저장 알림, CloudKit import 뒤 알림·위젯·Live Activity를
  수렴시킨다.
- iOS/macOS 앱과 Watch 앱은 각각 App Group snapshot을 쓰는 기반이 있다.
- 현재 영속 스키마는 `EasyTaskSchemaV10`, backup package는 V9이다.
- 현재 backup package 지원 범위는 V2...V9이고 legacy JSON backup은 V1과 V2를 허용한다.
- iOS notification delegate와 `UNUserNotificationCenter` client는 Task reminder 경로에 이미
  존재하므로 Focus가 별도 delegate를 설치하면 안 된다.

### 2.2 그대로 유지할 의미

`TaskProgressEvent`와 Focus 타이머는 서로 다른 사실을 나타낸다.

| 데이터 | 의미 | Focus 일시 정지·휴식의 영향 |
|---|---|---|
| `Task.status == doing` | 사용자가 이 Task를 현재 진행 상태로 분류함 | 자동으로 변경하지 않음 |
| `TaskProgressEvent` | Task가 `doing` 상태였던 누적 시간 | Focus가 멈춰도 계속 누적될 수 있음 |
| `FocusSession` | 실제 Focus 타이머로 집중한 종료 구간 | 일시 정지와 휴식은 집중 시간에서 제외 |

Focus 시작·정지·휴식 때문에 `TaskProgressEvent.started/stopped`를 직접 만들지 않는다. Task
상태를 바꿔야 할 때만 기존 `TaskLifecycleService`를 사용한다. 이 경계로 기존 기록 화면의
진행 시간 의미와 Focus 통계의 의미가 섞이는 것을 막는다.

### 2.3 첫 출시에서 하지 않는 것

- 활성 타이머의 CloudKit 실시간 동기화 또는 기기 간 원격 제어
- 서버 push-to-start, 원격 Live Activity 갱신
- 자동으로 다음 집중·휴식 구간 시작
- 긴 휴식과 4회 반복 포모도로 루틴
- Focus 종료 시 Task 자동 완료 또는 `todo` 자동 복귀
- Focus 시간으로 기존 완료 스트릭·히트맵 점수 변경
- 앱 사용 차단, 방해 금지 모드 강제 변경, 웹사이트 차단
- 팀 공유 타이머, 순위, 점수화

## 3. 권장 제품 결정

### 3.1 기본 시간과 설정

- 기본 집중 시간은 25분, 기본 휴식 시간은 5분이다.
- 2026-09-04 화면 개선부터 작업 예상 시간이 있으면 새 집중의 기본값으로 사용한다.
  5~120분 밖 예상 값은 범위 안으로 제안하고 원래 예상 값과 제한을 화면에 설명한다.
  사용자가 바꾼 집중 시간이 우선이며, 작업의 일반 진행 시간을 예상 값에서 차감하지 않는다.
  실행 중 세션과 계속 집중·알림 action은 이미 확정한 세션 시간을 유지한다.
- 집중 시간은 5~120분, 휴식 시간은 1~30분 범위에서 1분 단위로 설정한다.
- 첫 출시에서는 설정이 기기 로컬이며 새 세션 시작 시 값이 snapshot에 복사된다.
- 이미 실행 중인 세션은 설정 변경의 영향을 받지 않는다.
- 자주 쓰는 15분, 25분, 50분 preset과 사용자 지정 값을 제공한다.
- 집중이 끝나면 알림과 완료 화면을 표시하지만 휴식은 사용자가 직접 시작한다.

### 3.2 Task 선택과 상태 변경

- Focus는 반드시 하나의 Task를 대상으로 시작한다. Task 없는 자유 타이머는 후속 범위다.
- 대상은 `supersededAt == nil`, `archivedAt == nil`인 대표 `todo` 또는 `doing` Task다.
- 계획일이 과거·오늘·미래인지와 관계없이 사용자가 명시적으로 선택한 Task에는 Focus를 시작할
  수 있다. 계획일을 오늘로 자동 이동하지 않는다.
- `todo` Task에서 시작하면 먼저 `TaskLifecycleService.applyStatus(.doing, ...)`을 성공시킨 뒤
  Focus를 시작한다.
- 이미 `doing`인 Task는 상태를 다시 쓰지 않고 Focus만 시작한다.
- `done`, archived, superseded Task에서는 바로 시작하지 않는다.
- 다른 `doing` Task가 있어도 이를 중지하지 않는다. 다만 활성 Focus는 기기당 하나만 둔다.
- 실행 중인 Focus가 있을 때 다른 Task의 Focus를 시작하면 현재 세션을 종료할지 확인한다.
  확인 없이 활성 세션을 교체하지 않는다.
- 기존 세션 terminal 저장이 실패하면 새 Task 세션을 시작하지 않는다. deadline이 이미 지난
  세션은 먼저 `completed`로 reconcile한 뒤 새 세션을 시작한다.
- Focus 완료·조기 종료·휴식 시작은 Task 상태를 바꾸지 않는다.
- Focus 실행 중 Task를 완료하면 현재 Focus를 `taskCompleted` 결과로 끝낸다.
- 이 Task 완료 동작은 예정 reminder 확인 규칙을 포함한 기존 Task 완료 경로를 그대로 사용한다.
  Focus 완료 화면이 확인 절차를 우회하지 않는다.
- 다른 기기에서 Task가 완료되어 CloudKit import로 `done`이 되면 같은 `taskCompleted` 결과로
  끝낸다.
- 외부 변경이나 CloudKit import로 Task가 `todo`, archived, superseded 상태가 되면 Focus를
  `interrupted`로 종료한다.
- Task가 명시적으로 삭제되어도 이미 종료된 FocusSession은 활동 기록처럼 보존한다. 활성
  세션만 다음 reconcile에서 `interrupted`로 확정하며 Task 부재만으로 과거 FocusSession을
  cascade delete하지 않는다.

### 3.3 기기당 하나의 활성 세션

첫 출시에서는 각 기기가 활성 타이머 하나를 로컬로 소유한다.

```text
iPhone 활성 Focus ── 기기 로컬 App Group JSON
macOS 활성 Focus  ── 기기 로컬 App Group JSON
Watch 활성 Focus  ── Watch 로컬 App Group JSON

종료된 FocusSession ── SwiftData ── CloudKit private database
```

- 활성 상태는 CloudKit 모델에 저장하지 않는다.
- iPhone에서 시작한 남은 시간을 Mac이나 Watch가 실시간 표시·제어하지 않는다.
- 각 기기가 같은 Task에 Focus를 동시에 시작하는 상황은 첫 출시에서 막을 수 없다. 이 경우
  서로 다른 실제 세션으로 저장하며 시간대가 겹친다는 이유만으로 자동 병합하지 않는다.
- 기기 간 인계는 별도 동기화 프로토콜을 설계한 뒤 후속 버전에서 추가한다.

### 3.4 집중과 휴식의 관계

- 영속 `FocusSession`은 집중 구간만 기록한다. 휴식 시간은 첫 출시 통계에 포함하지 않는다.
- 집중 타이머가 0에 도달하면 해당 구간을 `completed`로 확정하고 휴식 시작 선택지를 보여준다.
- 휴식 타이머도 로컬 active snapshot으로 복원할 수 있지만 `FocusSession` 레코드는 만들지
  않는다.
- 휴식이 끝나면 이전 Task의 새 Focus를 시작할 수 있다. 새 Focus는 새 논리 session ID를
  가진다.
- 휴식 중 Task가 완료·삭제되어도 휴식 타이머 자체는 계속할 수 있지만, 같은 Task의 다음
  Focus를 자동 시작하지 않는다.
- 집중 타이머는 0에서 멈추며 초과 집중 시간을 자동 합산하지 않는다. 계속 집중하려면 새
  세션을 시작하거나 후속 버전의 자유 타이머를 사용한다.

### 3.5 저장할 조기 종료 결과

1초 이상 진행된 집중 구간은 조기 종료되어도 기록한다. 결과는 다음 네 가지로 제한한다.

| 결과 | 의미 |
|---|---|
| `completed` | 계획 시간이 0에 도달함 |
| `stopped` | 사용자가 완료 전에 Focus만 종료함 |
| `taskCompleted` | Focus 중 Task 완료로 세션이 종료됨 |
| `interrupted` | Task 무효화나 정상화 가능한 비정상 로컬 상태 때문에 종료됨 |

0초 세션과 시작 snapshot 저장에 실패한 세션은 기록하지 않는다. `stopped`와 `interrupted`도
사용자 기록에는 남기되, 기본 `완료한 집중 횟수`에는 `completed`만 포함한다. `오늘 집중
시간`에는 결과와 관계없이 실제 `focusedDurationSeconds > 0`인 모든 세션을 포함한다.

## 4. 사용자 흐름과 화면

### 4.1 진입점

- 보드 Task 카드 context menu: `집중 시작`
- 모바일 Task 상세의 상태/시간 영역: `집중 시작`
- macOS Task 상세와 보드 카드 hover/context menu: `집중 시작`
- 현재 `doing` 영역의 첫 행: 작업이 하나면 즉시 시작하고 여러 개면 메뉴에서 선택하는
  `집중 시작` 패널
- 전역 플로팅 영역에는 비활성 시작 버튼을 두지 않고, 실행 중인 Focus의 남은 시간과 복귀
  버튼만 표시
- Focus 종료 후 완료 화면: `같은 작업 다시 집중`

보드의 일반 `진행 시작`과 `집중 시작`은 구분한다. 전자는 Task 상태만 바꾸고, 후자는 필요할
때 상태를 `doing`으로 바꾼 뒤 타이머까지 시작한다.

### 4.2 앱 내부 Focus 화면

```text
┌──────────────────────────────────┐
│ 집중                         ⋯   │
│                                  │
│ 기획서 작성                      │
│                                  │
│              24:36               │
│          집중 중 · 25분           │
│                                  │
│        [일시 정지] [종료]          │
│                                  │
│ 오늘 2회 · 42분                   │
└──────────────────────────────────┘
```

- 남은 시간이 첫 번째 시각 우선순위이고 Task 제목이 두 번째다.
- Task 제목은 최대 두 줄이며 지나치게 긴 제목은 말줄임한다.
- running, paused, focus completed, break running을 색만으로 구분하지 않고 문구와 아이콘을
  함께 사용한다.
- 화면을 닫아도 타이머는 종료되지 않는다.
- paused 상태에는 남은 시간이 고정되고 `재개`, `종료`를 제공한다.
- 집중 완료 상태에는 `휴식 시작`, `같은 작업 다시 집중`, `작업 완료`를 제공한다.
- 휴식 화면은 Task 제목을 보조 정보로 유지하되 `휴식`과 남은 시간을 가장 크게 표시한다.

### 4.3 iPhone과 iPad

- iPhone은 Focus를 전체 화면 cover로 열고 최소 제어만 표시한다.
- iPad는 compact width에서는 iPhone과 같고 regular width에서는 가운데 제한 폭 panel을
  사용한다.
- 앱이 background로 가도 deadline과 로컬 알림으로 계속 동작한다.
- 잠금 화면·Dynamic Island는 기존 Task Live Activity 하나를 Focus 표현으로 전환한다.
- Live Activities가 비활성화되어도 앱 타이머와 알림은 정상 동작한다.

### 4.4 iOS Live Activity 표현

기존 `PlanBaseTaskActivityAttributes`를 별도 Activity와 경쟁시키지 않고 호환 확장한다.

- 기존 in-flight Activity가 decode될 수 있도록 새 ContentState 필드는 optional 또는 기본값을
  가진 custom decoding으로 추가한다.
- `presentationMode`가 없으면 기존 누적 진행 시간 count-up 표현으로 해석한다.
- Focus 실행 중에는 선택한 Focus Task가 기존 대표 `doing` Task보다 우선한다.
- Focus 대상은 현재 `widgetPlannedTasksDescriptor`의 오늘 범위에서 찾지 않고
  `taskCandidatesDescriptor(id:)`와 기존 대표 선택 규칙으로 직접 찾는다. 이로써 과거·미래
  계획일의 명시적 Focus도 유효하게 유지한다.
- active Focus 분기는 오늘 Task fetch와 기존 `maximumSessionAge` 8시간 generic progress
  guard보다 먼저 평가한다. 오래 전부터 `doing`이던 Task에 새 25분 Focus를 시작했을 때
  Task progress 시작 시각 때문에 Focus Activity가 즉시 종료되어서는 안 된다.
- coordinator는 active Focus가 있을 때 Activity를 immutable `dayKey`만으로 찾지 않고
  ContentState의 `focusSessionID`로 우선 매칭한다. 자정이 지나도 같은 Focus Activity를
  불필요하게 종료·재생성하지 않는다.
- Focus가 끝나고 Task가 계속 `doing`이면 기존 count-up 표현으로 돌아간다.
- Focus가 시작된 날과 끝난 날이 다르면 이전 `dayKey` attributes의 Activity는 종료한 뒤 현재
  날짜의 기존 generic reconciliation을 수행한다. 이전 날짜 attributes를 오늘 count-up
  Activity로 계속 재사용하지 않는다.
- 사용자가 기존 일반 Task Activity를 제거했더라도 명시적인 Focus 시작은 새 사용자 행동이므로
  Focus session ID 기준으로 Activity를 다시 시작할 수 있다.
- 앱이나 Intent가 deadline 뒤 실행 기회를 얻기 전에는 시스템 countdown이 `0:00`에서 멈출
  수 있다. `집중 완료` ContentState와 terminal 저장은 다음 reconcile에서 확정한다.
- Focus 실행 중 `ActivityContent.staleDate`는 자정이 아니라 Focus deadline을 기준으로 한다.
  일반 count-up 표현으로 복귀할 때는 기존 오늘 범위 stale 정책을 다시 적용한다.

표현은 다음을 기준으로 한다.

| 위치 | Focus 실행 중 | 일시 정지 | Focus 완료 |
|---|---|---|---|
| 잠금 화면 | Task 제목, 남은 시간, pause, stop | 고정 시간, resume, stop | `집중 완료`, 앱 열기 |
| Dynamic Island compact | 짧은 제목, `MM:SS` | pause 표시, 고정 시간 | 완료 표시 |
| Dynamic Island minimal | `MM:SS` | pause 아이콘 | 완료 아이콘 |
| expanded | 제목, 남은 시간, 상태, pause/resume·stop | 동일 | 완료 상태와 앱 열기 |

잠금 화면에서 `stop`은 Focus만 종료한다. Task 완료와 혼동하지 않도록 Focus 표현 중에는
기존 `✓` Task 완료 버튼을 노출하지 않고, Task 완료는 앱의 Focus 완료 화면이나 Task 화면에서
수행한다. Focus가 아닌 기존 count-up 표현은 현재 완료·다음 동작을 유지한다.

### 4.5 macOS 플로팅 패널

- Focus 시작과 함께 작은 플로팅 패널을 열되 사용자가 닫을 수 있다.
- 패널을 닫아도 타이머는 계속되고 메뉴/보드의 `Focus 보기`로 다시 연다.
- 기본 compact 상태에는 Task 제목, 남은 시간, pause/resume, stop만 표시한다.
- 확장 상태에는 오늘 집중 횟수·시간과 `작업 완료`를 추가한다.
- 패널은 항상 위 표시를 끌 수 있어야 하고 마지막 위치를 기기 로컬에 보존한다.
- 사용자가 요청한 `띄워두기` 경험을 위해 첫 실행의 always-on-top 기본값은 켬이다.
- 전체 화면 앱, Space 이동, 다중 모니터, 앱 재실행에서 panel이 화면 밖에 복원되지 않게 한다.
- SwiftUI window API로 요구사항을 충족하지 못할 때만 얇은 `NSPanel` coordinator를
  `desktop/App`에 둔다. 타이머 규칙과 저장은 AppKit 타입에 의존하지 않는다.

### 4.6 Apple Watch 범위

Watch 구현은 iPhone/macOS와 같은 기기 로컬 소유권 정책을 사용하되, 실제 출시는 Release A의
실기기 안정화 뒤 별도 단계로 진행한다.

- Watch에서 시작한 Focus만 Watch 앱과 complication에서 실시간 제어한다.
- iPhone 활성 Focus 미러링은 첫 Watch 단계에 포함하지 않는다.
- Watch Focus 화면은 Task 제목, 남은 시간, pause/resume, stop만 제공한다.
- complication snapshot은 남은 시간의 정확한 초 단위 갱신을 보장하지 않으므로 현재 phase와
  Task 제목을 우선하고 탭하면 Watch Focus 화면을 연다.
- Watch에서 종료된 `FocusSession`은 기존 SwiftData/CloudKit 경로로 다른 기기에 동기화한다.

## 5. 타이머 상태 머신과 시간 계산

### 5.1 상태 머신

```text
                     pause
idle ── start ──> focusRunning ─────> focusPaused
  ^                    │   ^              │
  │                    │   └── resume ────┘
  │                    │
  │             deadline / stop / task completion
  │                    ▼
  │              focusFinished
  │               │         │
  │          dismiss     start break
  │               │         ▼
  │               └──── breakRunning ── pause ──> breakPaused
  │                          │   ^                    │
  └──────────────────────────┴───┴──── finish/resume ┘
```

`focusFinished`는 영속 모델의 active 상태가 아니라, FocusSession 저장을 마친 뒤 다음 행동을
고르는 로컬 UI 상태다. 앱 재실행 때 이 상태를 잃어도 완료 기록은 보존된다.

### 5.2 순수 계산 규칙

- running 남은 시간: `max(0, deadline.timeIntervalSince(now))`
- paused 남은 시간: snapshot의 `remainingSecondsAtPause`
- running 집중 시간: `accumulatedFocusedSeconds + now - segmentStartedAt`
- 저장 집중 시간: `0...plannedDurationSeconds` 범위로 clamp
- pause와 break 구간은 `focusedDurationSeconds`에 포함하지 않는다.
- deadline이 지난 snapshot은 UI timer callback 유무와 관계없이 다음 reconcile에서 정확히 한
  번 `completed`로 확정한다.
- terminal 원인이 경쟁하면 시간 순서를 우선한다. running deadline이 command 시각보다 먼저거나
  같으면 `completed`가 stop, taskCompleted, interrupted보다 우선하고, deadline 전 command는
  해당 command 결과를 사용한다.
- timezone과 DST 변경은 절대 `Date` 간격 계산에 영향을 주지 않아야 한다.
- 수동 시스템 시각 변경으로 음수 또는 비정상적으로 큰 간격이 생기면 0과 계획 시간 사이로
  clamp하고 진단 가능한 결과를 남긴다. 임의의 누락 시간을 합성하지 않는다.

iOS background에서는 일반 `Timer`가 정확히 실행된다고 가정하지 않는다. UI는 deadline 기반
시스템/Timeline 표현을 사용하고, 종료 알림을 예약하며, 앱이나 Intent가 다시 실행될 때
snapshot을 reconcile한다.

## 6. 활성 세션 로컬 snapshot

활성 상태는 기존 호환 App Group container의 `Focus/focus-active-v1.json`에 원자적으로
저장한다. Widget snapshot 폴더와 파일명은 재사용하지 않으며 새 App Group ID를 만들거나 기존
ID를 바꾸지 않는다.

```text
FocusActiveSessionSnapshot
  formatVersion
  revision
  sessionID
  instanceID
  taskID
  taskTitleSnapshot
  phaseRawValue              // focus | break
  runStateRawValue           // running | paused
  phaseStartedAt
  segmentStartedAt?
  deadline?
  remainingSecondsAtPause?
  accumulatedFocusedSeconds
  plannedFocusSeconds
  plannedBreakSeconds
  updatedAt
```

- 매초 저장하지 않는다. start, pause, resume, phase 전환, stop에서만 쓴다.
- 남은 시간은 snapshot timestamp와 현재 시각에서 계산한다.
- 쓰기는 temporary file 생성 후 atomic replace 방식으로 수행한다.
- iOS에서는 기존 widget snapshot과 같은
  `.completeFileProtectionUntilFirstUserAuthentication` 보호 수준을 적용해 첫 잠금 해제 뒤
  Live Activity Intent가 읽을 수 있게 한다. 다른 플랫폼은 현재 snapshot store의 원자 쓰기
  정책을 따른다.
- decode 실패나 지원하지 않는 `formatVersion`은 무시하지 않고 안전 종료 후보로 분류한다.
- 식별자와 시간조차 복구할 수 없는 손상 snapshot은 별도 진단 대상으로 격리하고 영속
  FocusSession을 임의 생성하지 않는다.
- `instanceID`는 시작 시 한 번 생성해 terminal 저장 재시도에서도 같은 물리 레코드 identity를
  사용한다.
- `sessionID + revision`을 command precondition으로 사용해 오래된 Live Activity 버튼이 새
  세션을 조작하지 못하게 한다.
- `taskTitleSnapshot`은 원본 Task를 읽을 수 없을 때 표시하기 위한 로컬 fallback일 뿐 영속
  통계의 정규 데이터가 아니다.
- active snapshot은 backup package와 CloudKit에 포함하지 않는다.
- read-modify-write는 프로세스별 공유 coordinator에서 직렬화한다. 파일의 atomic write만으로
  동시 UI·Intent command 경쟁을 해결했다고 간주하지 않는다.

### 6.1 저장 순서와 crash 복구

시작 순서:

1. 대상 Task와 현재 active snapshot을 검증한다.
2. 필요하면 `PersistenceCommandService.perform` 안에서 Task를 `doing`으로 전환한다.
3. Task 저장 성공 후 active snapshot을 쓴다.
4. 알림과 Live Activity를 best-effort로 수렴시킨다.

Task 저장이 성공하고 snapshot 쓰기가 실패하면 Task는 `doing`으로 남을 수 있지만 Focus가
실행 중인 것처럼 표시하지 않는다. 사용자에게 시작 실패를 보여주며 가짜 세션을 만들지 않는다.

종료 순서:

1. snapshot으로 terminal `FocusSession` 값을 결정한다.
   deadline 완료라면 `endedAt`은 늦게 reconcile한 시각이 아니라 원래 deadline을 사용한다.
2. 동일 `sessionID` 저장이 이미 완료됐는지 확인하고 `PersistenceCommandService.perform`으로
   idempotent하게 upsert한다.
3. 영속 저장 성공 후 알림을 취소하고 active snapshot을 지운다.
4. snapshot 삭제가 실패하면 다음 reconcile이 기존 terminal record를 확인한 뒤 정리한다.

이 순서로 앱이 중간에 종료되어도 완료 기록을 잃거나 같은 세션을 이중 집계하지 않는다.

## 7. 영속 데이터와 V10 migration

배포된 V1~V9는 수정하지 않고 `EasyTaskSchemaV10`을 추가한다. V10은 V9 모델 전체와 새
terminal-only `FocusSession`을 포함한다.

```text
FocusSession
  id: UUID
  instanceID: UUID
  taskId: UUID
  startedAt: Date
  endedAt: Date
  plannedDurationSeconds: Int
  focusedDurationSeconds: Int
  outcomeRawValue: String
  createdAt: Date
  updatedAt: Date
  supersededAt: Date?

indexes
  id
  taskId
  startedAt
  endedAt
  taskId + endedAt
```

- CloudKit 호환을 위해 모든 non-optional 필드는 선언 시 기본값을 가진다.
- 활성/paused 여부나 현재 deadline은 이 모델에 저장하지 않는다.
- `taskId`는 논리 Task ID이며 SwiftData relationship을 만들지 않는다.
- Task가 보이지 않아도 FocusSession을 즉시 삭제하지 않는다. CloudKit import 순서 때문에
  일시적으로 참조 대상이 없을 수 있다.
- 종료된 세션은 원칙적으로 immutable이다. duplicate convergence를 위한
  `supersededAt` 처리 외에는 수정하지 않는다.
- V9 → V10은 새 모델 추가만 포함하는 lightweight migration을 우선한다.
- `AppModels.swift`에 `FocusSession` typealias를 추가하고
  `PlanBaseContainerFactory.schema`, migration plan, test schema 구성을 V10으로 올린다.

### 7.1 무결성 규칙

- `id`가 같고 `supersededAt == nil`인 FocusSession record는 하나만 남기고 나머지는
  `supersededAt`으로 수렴한다.
- 같은 `instanceID`가 서로 다른 `taskId` 또는 `startedAt`을 가지면 identity corruption으로
  취급한다.
- `endedAt < startedAt`, 음수 시간, 계획 시간보다 큰 집중 시간, 알 수 없는 outcome은
  무결성 검사 대상이다.
- 안전하게 정규화할 수 있는 duration은 clamp하고, 식별 사실이 충돌하면 임의로 합성하지
  않는다.
- 같은 session ID의 재시도 레코드는 기존 이력 모델처럼 `updatedAt`, `instanceID` 순서의
  결정적 winner 규칙을 따르고 winner의 `createdAt`에는 가장 이른 정상값을 보존한다.
- task 참조 부재만으로 orphan 삭제 또는 supersede하지 않는다.
- 레코드 수가 계속 늘어나는 이력 모델이므로 무결성 서비스는
  `TaskProgressEventIntegrityService`처럼 정렬된 200개 단위 batch와 pending change 별도
  수렴을 사용한다. 앱 시작 때 FocusSession 전체를 한 배열로 올리지 않는다.

### 7.2 조회와 통계

- 첫 출시의 날짜별 Focus 기록은 `endedAt`의 `DayKey`를 기준으로 묶는다. pause 구간의 상세
  timestamp를 저장하지 않으므로 자정을 가로지른 focused duration을 날짜별로 임의 분배하지
  않는다.
- 자정을 가로질러도 실행 중인 Focus를 강제로 종료하지 않는다. 종료된 전체 duration은 종료일
  기록에 포함하고 UI에 `종료일 기준`임을 설명한다.
- 오늘 완료 횟수는 오늘 끝난 `outcome == completed` 세션 수다.
- 실행 중인 Focus 시간은 terminal 저장 전까지 오늘 합계에 더하지 않고 현재 타이머에서만
  보여준다.
- 조회는 현재 날짜 또는 명시한 범위의 bounded descriptor/session을 사용한다.
- Focus 기록은 기존 Task 완료 스트릭과 `TaskCompletionActivity` 통계에 포함하지 않는다.

## 8. 서비스 구조

공통 코어에 다음 책임을 둔다.

- `FocusTimerRules`
  - 상태 전환 가능 여부, 남은 시간, 실제 집중 시간, terminal outcome 계산
- `FocusActiveSessionStore`
  - versioned JSON encode/decode, atomic write, clear
- `FocusSessionService`
  - 시작·일시 정지·재개·종료 orchestration과 idempotent terminal 저장
- `FocusSessionIntegrityService`
  - duplicate convergence, 필드 검증과 정규화
- `FocusSessionQuerySession`
  - 오늘/선택 기간의 bounded Focus 기록과 합계
- `FocusNotificationRequest`
  - 플랫폼 scheduler가 사용할 identifier, title, deadline의 순수 값

각 앱 프로세스는 `FocusSessionCoordinator` 하나를 공유한다. coordinator는 local store,
`ModelContainer`, notification adapter를 조립하고 UI와 App Intent command를 같은 직렬 실행
경계로 보낸다. 화면마다 `FocusSessionService`를 새로 만들어 서로 다른 snapshot을 들고 있지
않는다. iOS에서는 앱 시작 시 기존 `PlanBaseTaskIntentRuntime.install`과 같은 시점에 Focus
dependency를 설치하고 SwiftUI 환경에도 같은 coordinator를 제공한다.

플랫폼 계층은 다음만 담당한다.

- App Group URL과 local notification adapter 제공
- 화면 상태와 SwiftUI composition
- ActivityKit, App Intents, NSPanel, WidgetKit adapter
- scene lifecycle에서 공통 service reconcile 호출

앱 root는 start, scene active, 자정·시간대 변경, CloudKit import,
`PersistenceCommandService.dataChangedNotification`, Focus snapshot 변경 시 다음을 수렴한다.

1. active snapshot과 Task 유효성 확인
2. deadline이 지난 FocusSession terminal 저장
3. Focus 완료 알림 상태 확인
4. Live Activity 또는 macOS panel 표시 갱신
5. 오늘 Focus 요약 bounded query 갱신

## 9. 알림과 백그라운드 동작

- Focus/휴식 종료 알림은 `Task.reminderAt` 기반 알림과 identifier namespace를 분리한다.
- iOS에서는 기존 private `TaskNotificationCenterClient`를 앱 공통
  `PlanBaseNotificationCenterClient`로 추출해 authorization과 system center adapter를
  재사용하되, Task reminder와 Focus의 reconciliation namespace는 분리한다.
- `PlanBaseAppDelegate` 하나가 Task와 Focus notification response를 모두 분기한다. 두 번째
  `UNUserNotificationCenterDelegate`를 설치하지 않는다.
- 예약 identifier에는 session ID와 phase를 포함한다.
- pause, resume, stop, 새 phase 시작 시 이전 요청을 취소하고 새 deadline으로 재예약한다.
- 알림 권한이 없어도 Focus 시작을 막지 않는다. Focus 화면에 조용한 안내를 제공한다.
- 권한은 앱 시작 시 선요청하지 않는다. 첫 Focus 시작 시 용도를 설명한 뒤 요청하고, 거부되면
  타이머·Live Activity·macOS panel은 계속 동작한다.
- 알림 payload에는 `routeKind=focus`, session ID를 넣어 기존 Task reminder payload와
  구분한다. app delegate는 `FocusNotificationRouteStore`에 전달하고 앱 root가 현재 Focus
  화면을 연다.
- 외부 URL과 Live Activity 본문 탭에는
  `planbase://focus?session=<UUID>` deep link를 사용하며 같은 검증 규칙으로 합류시킨다.
- stale session ID, 이미 끝난 session, 잘못된 UUID route는 현재 active 세션을 변경하지 않는다.
- iOS background task 실행을 종료 정확성의 전제로 삼지 않는다.
- macOS에서도 같은 요청 의미를 사용하되 플랫폼 notification adapter를 별도로 둔다.

### 9.1 알림 제품 원칙

- 알림은 사용자의 다음 행동이 필요한 `집중 종료`와 `휴식 종료`에만 보낸다. 시작, 중간,
  일시 정지, 재개, 조기 종료에는 별도 알림을 만들지 않는다.
- 기본 알림은 한 번만 울리는 일반 alert와 짧은 sound/haptic이다. Critical Alert나 반복 경보로
  승격하지 않으며 시스템 집중 모드를 임의로 우회하지 않는다.
- 종료 1분 전 알림은 초기 개선 범위에서 제외한다. 후속 설정으로 제공하더라도 기본값은 끔으로
  두고 사용자가 명시적으로 선택하게 한다.
- 현재 Focus 화면 또는 macOS Focus panel이 전면에 보이면 화면 상태 전환과 한 번의
  sound/haptic만 사용하고 같은 내용의 system banner는 중복 표시하지 않는다. 다른 앱 화면,
  background, 잠금 화면에서는 system notification을 표시한다.
- 알림을 닫은 것은 Task 완료나 다음 구간 자동 시작으로 해석하지 않는다. 집중 기록은 deadline
  reconcile로 완료하되 Task 상태는 그대로 유지한다.

### 9.2 문구와 사용자 동작

| 시점 | 제목 | 본문 | 빠른 동작 |
|---|---|---|---|
| 집중 종료 | `25분 집중을 완료했어요` | `{Task 제목} · 잠시 쉬어갈까요?` | `휴식 시작`, `계속 집중` |
| 휴식 종료 | `휴식이 끝났어요` | `{Task 제목} · 다시 집중할까요?` | `집중 시작`, `5분 더 쉬기` |

- 집중 시간 숫자는 snapshot의 실제 계획 시간을 사용하고, Task 제목은 notification 한 줄에서
  안전하게 잘리도록 snapshot 문자열만 사용한다.
- `휴식 시작`은 snapshot에 복사된 사용자 휴식 시간을 사용한다. 알림 action 제목에는 가변
  숫자를 넣지 않아 category를 안정적으로 재사용한다.
- `계속 집중`과 `집중 시작`은 직전 집중 시간으로 새 Focus를 시작한다. 이전 세션을 재개하거나
  같은 session ID를 재사용하지 않는다.
- `5분 더 쉬기`는 만료된 휴식을 정리한 뒤 5분짜리 새 local break snapshot을 만든다. 후속
  설정에서 연장 시간을 제공하기 전까지 값은 5분으로 고정한다.
- 알림 본문 탭은 유효 token을 해석해 Focus 화면을 연다. 집중 종료는 `휴식 시작`과
  `계속 집중`, 휴식 종료는 `집중 시작`과 `5분 더 쉬기`가 있는 종료 화면을 복원한다.
  active snapshot이 이미 정리됐다는 이유로 일반 작업 선택 화면을 보여주지 않는다.
- 알림 dismiss는 `나중에`와 같은 의미로 Task나 timer 명령을 실행하지 않는다.

### 9.3 알림 action의 안전한 실행

- 집중 종료와 휴식 종료에 서로 다른 `UNNotificationCategory`를 등록하고, action identifier는
  Task reminder 및 Live Activity Intent namespace와 분리한다.
- scheduler는 요청을 예약할 때 같은 App Group의 Focus directory에
  `FocusNotificationActionToken`을 원자적으로 기록한다. token에는 무작위 token ID, request ID,
  session ID, revision, phase, task ID, 제목 snapshot, 집중·휴식 계획 시간, deadline과
  `deadline + 60분`의 만료 시각을 둔다. 이는 기기 로컬 임시 상태이며 SwiftData, CloudKit,
  backup에는 포함하지 않는다.
- notification payload에는 최소 식별자인 `routeKind`, token ID, `sessionID`, `revision`,
  `phase`, `deadline`만 넣는다. payload의 제목이나 시간 값을 명령 근거로 사용하지 않고,
  현재 local token과 모두 일치할 때만 동작한다.
- action handler는 먼저 deadline reconcile을 실행한다. `휴식 시작`은 완료 FocusSession을
  정확히 한 번 저장한 뒤 break를 만들고, `계속 집중`은 같은 terminal 저장 뒤 새 Focus를 만든다.
- 휴식 action은 만료된 break snapshot을 먼저 정리한 뒤 새 Focus 또는 연장 break를 만든다.
- 현재 active snapshot이 같은 session이면 이를 deadline reconcile한 뒤 token을 사용한다.
  snapshot이 이미 정리됐다면 집중 action은 같은 ID의 `completed` FocusSession이 저장됐는지,
  휴식 action은 token의 deadline이 지났는지 확인한다. 다른 active session이 있거나 더 새로운
  token이 있으면 이전 알림 action을 stale로 거부한다.
- 현재 구현은 deadline reconcile 뒤 active snapshot을 즉시 지우고 iOS scheduler가 delivered
  notification도 정리할 수 있다. Phase 9에서는 유효 token이 남아 있는 종료 알림을 즉시
  삭제하지 않고 action 처리, 명시적 dismiss, 새 세션 시작 또는 token 만료 때 제거한다.
- 현재 구현에는 공용 `FocusSessionCoordinator`가 없으므로 Phase 9에서
  `PlanBaseFocusNotificationActionRuntime`을 앱 시작 시 기존 `ModelContainer`와 함께 설치한다.
  이 runtime은 한 번에 하나의 command만 main context에서 처리한다. app delegate,
  Widget Extension 또는 notification extension이 별도 SwiftData/CloudKit container를 열지 않는다.
- terminal-first 상태 전환과 token 소비는 공통 `FocusNotificationActionService`에 두고,
  iOS/macOS/Watch runtime은 각 플랫폼의 notification, Live Activity, panel, complication
  후처리만 담당한다. 플랫폼별 handler가 같은 상태 전환을 복제하지 않는다.
- cold launch에서는 typed action을 작은 local inbox에 원자적으로 보관하고 앱 container와
  coordinator 설치가 끝난 뒤 한 번만 소비한다. 빠른 연속 탭과 재전달은 receipt ID,
  session ID, revision으로 멱등 처리한다.
- notification 본문 탭은 mutation command와 구분된 presentation route로 전달한다. root는
  token과 terminal record를 검증한 뒤 `focusEnded` 또는 `breakEnded` presentation을 만들고,
  사용자가 화면 action을 선택하거나 닫을 때 token을 정리한다.
- background에서 즉시 실행할 기반이 준비되지 않았으면 알림을 누른 상태로 앱을 열어 같은
  command를 처리한다. 준비되지 않은 container에서 성공한 것처럼 알림만 지우지 않는다.
- action 성공 후 snapshot, 다음 종료 알림, Live Activity 또는 panel, Watch complication을
  기존 순서로 수렴시킨다. 실패하면 현재 상태를 유지하고 Focus 화면에 재시도 가능한 오류를
  표시한다.
- category에는 custom dismiss 처리를 등록한다. dismiss는 Task나 timer 명령을 실행하지 않고
  일치하는 delivered notification과 token만 정리한다. callback을 받지 못한 token은 앱 시작과
  scheduler reconcile에서 만료 시각 기준으로 제거한다.

### 9.4 전면 화면 중복 통지 억제

- iOS `willPresent`는 단순 전역 boolean이 아니라 scene active 여부, 현재 보이는 Focus 화면의
  session ID와 notification token의 session ID를 함께 확인한다. 같은 세션의 Focus 화면이
  실제 전면일 때만 banner를 억제하고 sound는 한 번 유지한다.
- 이를 위해 process-local `FocusPresentationVisibilityStore`를 두고 Focus 화면의
  appear/disappear 및 macOS panel key/visible 상태에서 갱신한다. 저장소는 영속화하지 않으며
  notification delegate의 비동기 경쟁을 막을 수 있는 thread-safe 읽기 경계를 제공한다.
- Focus 화면이 아닌 보드·캘린더가 전면이거나 다른 window/scene의 Focus가 보이는 경우에는
  system banner를 유지한다. 화면 상태를 확실히 판별할 수 없으면 알림 누락보다 banner 표시를
  선택한다.
- banner를 억제한 종료는 해당 Focus 화면의 완료 또는 휴식 종료 UI에 같은 빠른 동작을 표시한다.
  화면 action을 사용하면 일치하는 notification token과 delivered notification도 함께 정리한다.

### 9.5 기기별 전달 정책

- 타이머를 시작한 기기가 해당 local session 알림의 유일한 앱 발신 주체다. iPhone 시작은
  iPhone, Mac 시작은 Mac, Watch 시작은 Watch scheduler가 담당한다.
- iPhone 알림이 사용자의 시스템 설정에 따라 Apple Watch로 미러링되는 것은 OS에 맡기며,
  PlanBase가 같은 iPhone session의 Watch local notification을 추가 예약하지 않는다.
- 서로 다른 기기에서 독립 Focus를 실제로 시작한 경우에는 별도 세션이므로 각 기기의 알림을
  유지한다. Task ID가 같다는 이유만으로 다른 기기의 알림을 취소하지 않는다.
- iPhone/iPad와 macOS는 두 개의 빠른 action을 제공한다. Watch는 짧은 문구와 haptic을 우선하고,
  작은 화면에서 두 action의 오조작 가능성을 실기기로 검증해 필요하면 본문 탭만 제공한다.
- 알림 권한이 거부됐거나 OS가 전달하지 않아도 타이머 계산, terminal 저장, 화면 복원은 동일하게
  동작한다.

## 10. Live Activity·Intent 안전성

- Focus Intent는 `sessionID`와 `revision`을 받아 현재 local snapshot과 일치할 때만 수행한다.
- pause/resume/stop은 직렬화된 command executor를 거친다.
- iOS Intent는 기존 `AppDependencyManager` 설치 경로를 확장하고 UI와 같은
  `FocusSessionCoordinator`를 사용한다. 별도의 임시 ModelContainer나 독립 store를 열지
  않는다.
- `stop`의 terminal SwiftData 저장은 기존 앱 프로세스 container를 사용한다. Widget Extension이
  자체적으로 CloudKit container를 열지 않는다.
- 성공한 command 뒤 local snapshot, notification, Activity content를 같은 순서로 수렴한다.
- 빠른 연속 탭과 이전 ContentState의 지연 전달은 두 번째 이후 stale command로 거부한다.
- 기존 Task progress receipt와 Focus receipt는 namespace를 분리한다. Focus의 명시적 시작을
  과거 generic Activity 제거 receipt가 막거나, Focus 종료가 generic Activity를 무한 재시작하게
  해서는 안 된다.
- 기존 count-up Activity의 wire key `updatedAt` 호환을 보존한다.
- Focus ContentState에는 원본 Task 배열, 메모, 태그 또는 체크리스트 내용을 넣지 않는다.

추가 ContentState 후보:

```text
presentationModeRawValue?   // nil = legacy count-up, focus, focusPaused, focusComplete
focusSessionID?
focusRevision?
focusDeadline?
focusRemainingAtPause?
focusPlannedSeconds?
```

## 11. 백업·CloudKit·혼합 버전

### 11.1 백업

- backup export는 active Focus 중에도 허용하되 아직 terminal이 아닌 현재 구간은 포함하지
  않는다고 표시한다.
- backup import, package merge, legacy replace-all은 active Focus 또는 break가 있으면 먼저
  종료할지 확인하고 terminal 저장이 성공하기 전에는 진행하지 않는다. import가 local
  snapshot을 조용히 지우거나 다른 Task에 연결하지 않는다.
- `FocusSessionDTO`와 `BackupPayload.focusSessions`를 optional로 추가한다.
- legacy JSON backup version은 V2로 올리고 새 앱은 V1과 V2를 모두 읽는다.
- V1 restore에는 FocusSession이 없다는 의미를 명시하며 replace-all 정책대로 기존 Focus 기록도
  교체 대상이 된다.
- backup package는 V9로 올리고 현재 하한을 바꾸지 않은 채 V2...V9 읽기를 유지한다.
- package V8 이하의 optional field 부재는 merge 시 로컬 FocusSession 삭제를 뜻하지 않는다.
- package V9 merge는 같은 `instanceID`의 identity를 검증하고 기존 수렴 규칙으로 병합한다.
- 활성 local snapshot과 예약 알림은 백업하지 않는다.
- 새 backup을 구버전 앱이 조용히 일부만 복원하지 않도록 version 거부 동작을 테스트한다.

### 11.2 CloudKit

- `CD_FocusSession` Development schema와 필요한 query index를 먼저 검증한다.
- iPhone ↔ macOS, Watch ↔ iPhone terminal record 왕복 probe를 추가한다.
- active session은 CloudKit record가 아니므로 probe 대상은 종료된 FocusSession뿐이다.
- Production schema 배포와 기록은 `docs/CLOUDKIT_SYNC.md` 절차를 따른다.
- 구버전 V9 앱은 FocusSession을 사용하지 않지만 Task 상태 변경은 기존 규칙대로 이해한다.
- Focus를 사용한 뒤에는 모든 주 사용 기기를 V10 지원 빌드로 올리도록 TestFlight/출시 메모에
  안내한다.

## 12. 단계별 구현 계획

출시 단위는 다음처럼 나눈다.

- Release A: Phase 0~6. V10 데이터 기반, iPhone/iPad Focus, iOS Live Activity, macOS
  플로팅 패널까지를 한 기능 단위로 출시한다.
- Release B: Phase 7의 Watch 독립 Focus 코드와 build 63 archive 업로드를 완료했으며 실제
  Watch 인수는 Release A의 실기기 안정화와 함께 계속한다.
- Release A의 Watch 앱도 공통 `EasyTaskSchemaV10`으로 migration하고 terminal
  FocusSession을 안전하게 동기화할 수 있어야 한다. Release B로 미루는 것은 Watch의 active
  타이머 UI와 로컬 snapshot뿐이다.
- Phase 8 검증과 문서 갱신은 각 release마다 수행한다. Watch 때문에 Release A 문서를 미완료
  상태로 두지 않고, Watch 항목은 Release B 인수표로 명시적으로 넘긴다.

### Phase 0 — 제품 fixture와 경계 고정

- 25/5 기본값, 기기당 하나, Task 필수, 자동 시작 없음 정책을 테스트 fixture로 고정한다.
- iPhone compact/expanded, iPad regular, macOS compact panel 기준 이미지를 만든다.
- 기존 count-up Live Activity 동작과 Activity ContentState decode fixture를 보존한다.
- 과거·미래 계획일 Task Focus와 자정을 가로지르는 Focus fixture를 포함한다.

완료 조건:

- Focus와 Task progress의 의미 차이가 코드 주석과 테스트 이름에 드러난다.
- 첫 출시 제외 범위가 UI에 빈 버튼이나 비활성 설정으로 노출되지 않는다.

### Phase 1 — 순수 타이머 규칙과 local snapshot

- `FocusTimerRules`, snapshot DTO, atomic store를 구현한다.
- start/pause/resume/deadline/stop/relaunch/stale revision 전환을 단위 테스트한다.
- App Group URL을 주입해 메모리·temporary directory 테스트를 가능하게 한다.
- 실제 App Group 경로, 별도 `Focus/` directory, iOS file protection option을 검증한다.

완료 조건:

- 매초 저장 없이 임의 시각에서 같은 남은 시간과 focused duration을 계산한다.
- process 재시작 뒤 running/paused Focus를 복원한다.
- 손상되거나 미래 버전 snapshot이 사용자 데이터 저장소를 건드리지 않는다.

### Phase 2 — V10, 무결성, 백업, CloudKit 기반

- `EasyTaskSchemaV10.FocusSession`과 lightweight migration을 추가한다.
- typealias, container schema, migration tests를 V10으로 갱신한다.
- integrity, DTO, legacy JSON V2, package V9 export/merge를 추가한다.
- `CloudKitDevelopmentSchema`의 V10 모델과 terminal record convergence probe를 준비한다.

완료 조건:

- V1~V9 fixture store가 V10으로 열린다.
- legacy JSON V1...V2와 package V2...V9 호환, 새 버전 거부, merge 보존 규칙이 테스트된다.
- duplicate/import 순서가 달라도 Focus 합계가 수렴한다.

### Phase 3 — Focus orchestration과 알림

- `FocusSessionService`의 시작·일시 정지·재개·종료·deadline reconcile을 구현한다.
- 프로세스별 `FocusSessionCoordinator` 하나를 UI와 Intent dependency에 함께 주입한다.
- Task 상태 전환, terminal 저장, snapshot 정리의 crash-safe 순서를 적용한다.
- iOS 공통 notification client, 기존 app delegate route 분기, macOS adapter와 Focus deep link를
  연결한다.

완료 조건:

- Task 저장 실패 시 Focus가 시작되지 않는다.
- terminal 저장 재시도가 같은 session을 이중 집계하지 않는다.
- pause/stop 뒤 이전 종료 알림이 울리지 않는다.

### Phase 4 — iPhone/iPad 앱 화면

- 보드와 Task 상세 진입점, Focus 전체 화면, 완료·휴식 화면을 구현한다.
- today Focus query summary를 표시한다.
- app root lifecycle과 deep link를 연결한다.
- VoiceOver, Dynamic Type, reduce motion, privacy 문구를 확인한다.

완료 조건:

- cold/warm launch와 background 복귀에서 같은 session을 보여준다.
- 긴 제목, 큰 글자 크기, 1분 미만/1시간 이상 표기가 잘리지 않는다.
- 화면 dismiss가 Focus를 종료하지 않는다.

### Phase 5 — iOS Live Activity 전환

- 기존 Activity ContentState를 backward-compatible하게 확장한다.
- Focus session이 있으면 countdown mode, 없으면 현재 count-up mode를 유지한다.
- pause/resume/stop App Intent와 stale command 보호를 추가한다.
- 기존 generic Task Activity와 중복 Activity를 만들지 않는다.
- non-today Focus는 task ID로 해석하고, 자정 뒤에도 focus session ID로 같은 Activity를
  갱신한다. stale date는 Focus deadline을 따른다.

완료 조건:

- count-up 회귀 없이 Focus countdown이 잠금 화면과 Dynamic Island에서 동작한다.
- 앱이 background여도 남은 시간이 0까지 표시되고 알림이 도착한다.
- 빠른 연속 입력이 하나의 세션만 종료한다.
- 과거·미래 계획일 Task와 자정을 넘긴 Focus가 오늘 대표 Task query 때문에 종료되지 않는다.

### Phase 6 — macOS 플로팅 패널

- 보드/상세 진입점과 compact/expanded panel을 구현한다.
- always-on-top, hide/show, 위치 복원, 다중 모니터 clamp를 추가한다.
- 앱 재실행 후 active snapshot이 있으면 panel 복원 정책을 적용한다.

완료 조건:

- panel close와 앱 window close가 타이머를 암묵적으로 종료하지 않는다.
- Space, 전체 화면, 모니터 분리 후에도 panel을 다시 찾을 수 있다.
- iPhone과 동일한 공통 상태 규칙과 terminal record를 사용한다.

### Phase 7 — Watch 독립 Focus

코드 상태: 완료. 실기기 wrist-down·알림·CloudKit 왕복 인수는 Phase 8에서 진행한다.

- Watch 로컬 snapshot store, Focus 화면, 알림·haptic, complication snapshot을 추가한다.
- Watch에서 저장된 terminal FocusSession의 CloudKit 수렴을 검증한다.

완료 조건:

- iPhone 활성 세션을 잘못 Watch 세션으로 표시하지 않는다.
- Watch 앱 재실행과 wrist down 뒤 상태가 복원된다.
- 작은 화면에서 주요 제어가 실수로 연속 실행되지 않는다.

### Phase 8 — 출시 회귀와 문서 갱신

- 자동 회귀, V10 Production schema 배포, iOS·macOS TestFlight build 63 업로드를 완료했다.
- 비활성 전역 버튼을 제거하고 `doing` 영역에 시작 패널을 둔 build 64의 공통 테스트,
  iOS·macOS Debug 빌드와 iPhone UI 회귀를 완료했다. 이어 iOS·Watch 및 macOS Release
  archive의 서명·권한·포함 구조를 검증하고 App Store Connect 업로드를 완료했다.
- 실제 기기의 background·잠금 화면·알림과 FocusSession 양방향 수렴 인수를 계속한다.
- 전체 플랫폼 빌드, 실기기 background, 잠금 화면, 알림, CloudKit을 검증한다.
- `README.md`, `AGENTS.md`, `docs/ARCHITECTURE.md`, `docs/CLOUDKIT_SYNC.md`,
  `docs/WATCHOS.md`의 현재 스키마와 기능 지도를 갱신한다.
- 모든 인수 항목이 끝나면 이 문서를 `docs/plans/completed/`로 이동한다.

### Phase 9 — 종료 알림 UX와 빠른 action

구현 상태: build 65 구현·자동 검증·TestFlight 업로드 완료. 실제 알림 시각, cold launch,
Watch wrist-down과 iPhone 알림의 OS Watch 미러링은 실기기 인수에서 확인한다.

1. 공통 코어에 phase별 notification presentation, action command, token과 stale/만료 검증 규칙,
   terminal-first `FocusNotificationActionService`를 추가한다.
2. App Group에 atomic `FocusNotificationActionTokenStore`를 추가하고 예약, pause/stop, phase 전환,
   deadline reconcile, 새 세션 시작과 만료 시의 token·pending·delivered 정리 순서를 고정한다.
3. iOS notification category와 action handler를 기존 단일 app delegate에 연결하고 cold-launch
   inbox, 종료 presentation route 및 앱 시작 시 주입되는
   `PlanBaseFocusNotificationActionRuntime` 직렬 실행 경계를 구현한다.
4. `휴식 시작`, `계속 집중`, `집중 시작`, `5분 더 쉬기`의 terminal-first 전환과 멱등성을
   단위·통합 테스트로 고정한다.
5. scene/session-aware visibility store로 foreground 중복 banner를 억제하고 화면 action과
   delivered notification 정리를 연결한다.
6. macOS에 notification delegate, 같은 category와 command 의미를 연결하고 panel이 보이는 동안
   동일한 중복 억제 정책을 적용한다.
7. Watch local notification의 haptic, 짧은 문구와 action 노출을 실기기에서 비교한 뒤 최종 범위를
   확정한다.
8. foreground, background, 잠금 화면, force quit/cold launch, 권한 거부, 시간대 변경과 빠른
   연속 탭을 iPhone·Mac·Watch에서 검증한다.

완료 조건:

- 집중·휴식 종료마다 소유 기기에서 알림이 정확히 한 번 예약되고 pause/stop 뒤에는 울리지 않는다.
- 두 종료 알림의 문구와 action이 9.2 표와 일치하며 dismiss가 Task 상태를 바꾸지 않는다.
- action을 여러 번 누르거나 오래된 알림을 눌러도 FocusSession 중복 저장이나 새 타이머 오염이 없다.
- deadline reconcile로 active snapshot이 사라진 뒤에도 현재 token의 action은 동작하며, 새 세션
  시작 또는 60분 만료 뒤에는 같은 action이 거부된다.
- 알림 본문 탭은 snapshot 유무와 관계없이 유효 token에 맞는 집중 종료 또는 휴식 종료 화면을
  복원한다.
- Focus 화면이 전면인 경우 같은 종료를 화면과 banner로 중복 통지하지 않는다.
- 알림 권한 거부와 전달 실패가 타이머·기록·Live Activity·panel·complication을 막지 않는다.
- 이 단계는 local notification orchestration만 변경하며 V10 schema와 backup package V9는 유지한다.

## 13. 예상 변경 파일

### 공통 코어

- `shared/Core/Persistence/EasyTaskSchemaV10.swift` 신규
- `shared/Core/Persistence/EasyTaskMigrationPlan.swift`
- `shared/Core/Persistence/PlanBaseContainerFactory.swift`
- `shared/Core/Persistence/CloudKitDevelopmentSchema.swift`
- `shared/Core/Models/AppModels.swift`
- `shared/Core/Services/FocusTimerRules.swift` 신규
- `shared/Core/Services/FocusActiveSessionStore.swift` 신규
- `shared/Core/Services/FocusSessionService.swift` 신규
- `shared/Core/Services/FocusSessionCoordinator.swift` 신규 후보
- `shared/Core/Services/FocusSessionIntegrityService.swift` 신규
- `shared/Core/Services/FocusSessionQuerySession.swift` 신규
- `shared/Core/Services/FocusNotificationRules.swift` 신규 후보
- `shared/Core/Services/FocusNotificationActionTokenStore.swift` 신규 후보
- `shared/Core/Services/FocusNotificationActionService.swift` 신규 후보
- `shared/Core/Services/BoundedQueryService+Focus.swift` 신규
- `shared/Core/Services/PlanBaseDeepLink.swift`
- `shared/Core/Services/DataIntegrityRecord.swift`
- `shared/Core/Services/DataIntegrityService.swift`
- `shared/Core/Services/BackupModels.swift`
- `shared/Core/Services/BackupCodec.swift`
- `shared/Core/Services/BackupPackageCodec.swift`
- `shared/Core/Services/BackupPackageMerge*.swift`
- `shared/Core/Services/CloudKitFocusConvergenceProbe.swift` 신규

### iPhone/iPad

- `mobile/App/Features/Focus/MobileFocusView.swift` 신규
- `mobile/App/Features/Focus/MobileFocusComponents.swift` 신규 후보
- `mobile/App/Features/Board/MobileBoardView.swift`
- `mobile/App/Features/Board/MobileTaskDetailSheet.swift`
- `mobile/App/Infrastructure/FocusNotificationScheduler.swift` 신규
- `mobile/App/Infrastructure/FocusNotificationActionInbox.swift` 신규 후보
- `mobile/App/Infrastructure/PlanBaseFocusNotificationActionRuntime.swift` 신규 후보
- `mobile/App/Infrastructure/FocusPresentationVisibilityStore.swift` 신규 후보
- `mobile/App/Infrastructure/FocusIntentRuntime.swift` 신규 후보
- `mobile/App/Infrastructure/TaskNotificationScheduler.swift`
- `mobile/App/Infrastructure/PlanBaseTaskIntentRuntime.swift`
- `mobile/App/Infrastructure/TaskLiveActivityCoordinator.swift`
- `mobile/App/Infrastructure/MobileBackupService.swift`
- `mobile/App/PlanBaseMobileApp.swift`
- `mobile/App/MobileAppRootView.swift`
- `mobile/Widget/PlanBaseTaskActivityAttributes.swift`
- `mobile/Widget/PlanBaseTaskLiveActivity.swift`
- `mobile/Widget/PlanBaseTaskWidgetIntents.swift`

### macOS

- `desktop/App/Features/Focus/DesktopFocusView.swift` 신규
- `desktop/App/Features/Focus/DesktopFocusPanel.swift` 신규 후보
- `desktop/App/Features/Board/BoardView.swift`
- `desktop/App/Features/Board/DesktopTaskDetailSheet.swift`
- `desktop/App/PlanBaseDesktopApp.swift`
- `desktop/App/AppRootView.swift`
- `desktop/App/Services/BackupService.swift`
- `desktop/App/Services/DesktopFocusNotificationScheduler.swift` 신규
- `desktop/App/Services/DesktopFocusNotificationActionRuntime.swift` 신규 후보
- `desktop/App/Services/DesktopFocusPresentationVisibilityStore.swift` 신규 후보

### Watch

- `watch/App/WatchFocusView.swift` 신규
- `watch/App/WatchFocusNotificationActionRuntime.swift` 신규 후보
- `watch/App/WatchRootView.swift`
- `watch/App/WatchWidgetSnapshotPublisher.swift`
- `watch/Widget/PlanBaseWatchWidget.swift`

### 프로젝트·테스트·문서

- `PlanBase.xcodeproj/project.pbxproj`
- `shared/Tests/FocusTimerRulesTests.swift` 신규
- `shared/Tests/FocusActiveSessionStoreTests.swift` 신규
- `shared/Tests/FocusSessionServiceTests.swift` 신규
- `shared/Tests/FocusSessionIntegrityTests.swift` 신규
- `shared/Tests/FocusSessionQueryTests.swift` 신규
- `shared/Tests/FocusNotificationRulesTests.swift` 신규 후보
- `shared/Tests/FocusNotificationActionTokenStoreTests.swift` 신규 후보
- `shared/Tests/FocusNotificationActionServiceTests.swift` 신규 후보
- `shared/Tests/SchemaMigrationTests.swift`
- `shared/Tests/BackupCodecCompatibilityTests.swift`
- `shared/Tests/BackupPackageTests.swift`
- `shared/Tests/DataSafetyTests.swift`
- `shared/Tests/DataIntegrityTests.swift`
- iOS/macOS/Watch UI·통합 테스트 파일
- `docs/README.md` 및 구현 완료 후 운영 문서

신규 플랫폼 Swift 파일은 반드시 해당 app/widget target membership에 등록한다. SwiftPM 경로의
공통 파일은 자동 발견되지만 공개 API와 Sendable/MainActor 경계는 별도로 검증한다.

## 14. 테스트 계획

### 14.1 순수 규칙

1. 25분 시작 직후 남은 시간이 25분이다.
2. 10분 실행, 5분 pause, 재개 후 15분 실행하면 focused duration은 25분이다.
3. pause 중에는 현재 시각이 변해도 남은 시간이 변하지 않는다.
4. deadline을 여러 번 reconcile해도 terminal 결과가 하나다.
5. stop, taskCompleted, interrupted outcome이 원인별로 결정된다.
6. 음수/초과 duration과 잘못된 설정 범위를 clamp 또는 거부한다.
7. timezone/DST 변경 뒤 절대 시간 계산이 동일하다.
8. 자정을 가로지른 세션이 강제 종료되지 않고 종료일 기준으로 집계된다.
9. deadline 뒤 늦게 reconcile해도 `endedAt`은 deadline이고 focused duration은 계획 시간을
   넘지 않는다.
10. deadline과 stop/Task 완료가 경쟁하면 먼저 발생한 시각으로 terminal outcome이 정해진다.

### 14.2 저장·복구

1. Task `todo → doing` 저장 성공 뒤에만 snapshot을 생성한다.
2. Task 저장 실패 시 snapshot과 알림이 생기지 않는다.
3. terminal 저장 성공 후 clear 실패를 재실행해도 중복 집계하지 않는다.
4. running/paused snapshot을 process 재시작 뒤 복원한다.
5. 손상 JSON, 미래 format version, stale revision command를 안전하게 거부한다.
6. 다른 active 세션 시작은 명시적 확인 없이 기존 snapshot을 덮지 않는다.
7. 과거·오늘·미래 계획일의 canonical Task는 Focus 가능하고 planned day는 바뀌지 않는다.
8. Task 삭제·supersede는 active Focus만 중단하고 기존 terminal 기록은 보존한다.
9. 기존 세션 terminal 저장 실패 중에는 새 Task Focus로 교체하지 않는다.

### 14.3 데이터 안전

1. V9 persistent store가 V10으로 lightweight migration된다.
2. `FocusSession` duplicate가 logical ID 기준으로 결정적으로 수렴한다.
3. Task import보다 FocusSession이 먼저 도착해도 orphan을 삭제하지 않는다.
4. legacy JSON V1...V2와 package V2...V9가 정책대로 decode된다.
5. package V8 merge가 기존 로컬 FocusSession을 보존한다.
6. package V9 왕복 후 session count, duration, outcome이 동일하다.
7. iPhone/macOS/Watch CloudKit probe가 같은 terminal record로 수렴한다.
8. active Focus 중 export는 terminal 기록만 내보내고, import/merge/replace-all은 명시적 종료
   전까지 시작하지 않는다.

### 14.4 UI·Live Activity

1. 긴 한글/영문/이모지 Task 제목과 큰 글자 크기
2. running/paused/completed/break 상태의 VoiceOver label과 action
3. background, force quit, reboot, 알림 tap 후 복원
4. Live Activity compact/minimal/expanded/잠금 화면
5. Always On, privacy redaction, Light/Dark와 모든 PlanBase theme
6. 알림 권한 허용/거부, Live Activities 허용/거부의 독립 동작
7. macOS panel close/reopen, Space, 전체 화면, 다중 모니터
8. 빠른 pause/resume/stop 연속 탭과 stale Intent
9. 기존 non-Focus Task count-up Activity의 회귀 여부
10. Focus와 Task reminder notification payload가 같은 app delegate에서 올바르게 분기됨
11. 과거·미래 계획일 Focus와 자정 통과 시 같은 Activity가 유지되고 stale date가 갱신됨
12. 8시간 이상 `doing`이던 Task의 새 Focus가 generic maximum age guard로 종료되지 않음
13. Focus 완료 화면의 Task 완료가 예정 reminder 확인 절차를 그대로 거침

### 14.5 종료 알림과 빠른 action

1. focus running에는 집중 종료 요청 하나, break running에는 휴식 종료 요청 하나만 존재한다.
2. identifier와 payload가 session ID, revision, phase를 구분하고 Task reminder와 충돌하지 않는다.
3. pause, stop, phase 전환 시 이전 pending request가 제거되고 resume의 새 deadline으로 재예약된다.
4. `휴식 시작`은 기존 Focus를 한 번만 완료 저장하고 설정된 휴식 시간으로 전환한다.
5. `계속 집중`과 `집중 시작`은 직전 집중 시간을 사용하되 새 session ID를 만든다.
6. `5분 더 쉬기`는 FocusSession을 만들지 않고 새 5분 break snapshot만 만든다.
7. stale notification, revision 불일치, deadline 이전 action과 빠른 중복 탭은 안전하게 거부된다.
8. cold launch inbox가 같은 command를 한 번만 전달하고 성공 후 receipt를 제거한다.
9. deadline reconcile이 snapshot을 먼저 지운 경우에도 token과 terminal record로 현재 action이
   동작하고, 60분 만료·새 세션·더 새로운 token 뒤에는 거부된다.
10. 유효 token의 delivered notification은 자동 reconcile 직후 삭제되지 않으며 action, dismiss,
    새 세션 또는 만료 때 정리된다.
11. notification 본문 탭은 snapshot이 이미 없어도 token을 통해 올바른 집중·휴식 종료 화면을
    복원하고, stale token이면 현재 active session 또는 안전한 시작 화면으로 이동한다.
12. 같은 scene/session의 foreground Focus 화면에서만 중복 banner가 억제되고 background·잠금 화면,
    보드 화면과 다른 scene에서는 도착한다.
13. 권한 미결정·허용·거부, OS 전달 실패와 알림 dismiss가 타이머 및 기록 결과를 바꾸지 않는다.
14. iPhone 알림의 OS Watch 미러링과 Watch 소유 session의 local 알림이 앱에서 중복 예약되지 않는다.

검증 명령:

```bash
swift test
swift test -c release
./scripts/verify-platform-builds.sh
```

ActivityKit background 표시, 실제 알림 시각, Always On, Dynamic Island, macOS panel level,
Watch wrist-down 동작은 simulator만으로 완료 처리하지 않고 실기기 인수를 필수로 둔다.

## 15. 위험과 대응

| 위험 | 대응 |
|---|---|
| background에서 callback이 정확히 실행되지 않음 | deadline 표시 + local notification + 다음 기회 reconcile |
| 매초 SwiftData/App Group 쓰기로 배터리·동기화 비용 증가 | 전환 시점만 저장하고 화면은 timestamp에서 계산 |
| 기존 count-up Live Activity와 Focus Activity가 경쟁 | Activity 타입 하나를 호환 확장하고 Focus가 표시 우선권을 가짐 |
| 기존 coordinator의 오늘 `dayKey` 매칭이 non-today/자정 Focus를 종료 | Focus 중에는 task ID·focus session ID 매칭과 deadline stale date 사용 |
| 오래된 Intent가 새 세션을 중지 | session ID + revision precondition |
| CloudKit으로 active 상태가 늦게 도착해 유령 타이머 생성 | active snapshot은 기기 로컬 전용 |
| 여러 기기에서 같은 Task를 동시에 집중 | 별도 실제 세션으로 보존, 자동 겹침 제거 금지, 인계는 후속 기능 |
| 새 모델이 백업에서 누락 | legacy JSON V2와 package V9에 함께 반영하고 호환 테스트 |
| Task와 Focus 저장소 사이 원자성 부재 | 시작은 Task 저장 후 snapshot, 종료는 terminal 저장 후 snapshot clear |
| 자정·시각 변경으로 통계가 모호 | 종료일 기준 집계, duration clamp, 명시적 UI 문구와 테스트 |
| macOS panel이 방해됨 | close와 always-on-top 해제 제공, 위치 복원과 화면 clamp |
| Focus scheduler가 기존 Task notification delegate와 경쟁 | 공통 center client와 단일 app delegate route 분기 |
| 오래된 종료 알림 action이 새 세션을 변경 | session ID + revision + phase + deadline 검증 후 직렬 실행 |
| deadline reconcile이 snapshot을 먼저 지워 빠른 action 정보가 사라짐 | 60분 유효 local action token과 terminal record를 함께 검증 |
| 화면 완료 표현과 system banner가 동시에 노출 | 전면 Focus presentation 상태를 확인해 같은 종료 banner 억제 |
| iPhone과 Watch에서 같은 알림을 앱이 이중 예약 | local session 소유 기기만 예약하고 OS notification mirroring에 위임 |
| action cold launch 중 container 준비 전 데이터 변경 | durable typed inbox에 보관하고 기존 coordinator 설치 뒤 한 번만 실행 |

## 16. 완료 기준

1. `todo` 또는 `doing` Task에서 Focus를 시작하고 앱을 닫아도 남은 시간이 유지된다.
2. pause/resume/stop과 deadline 완료가 정확하고 재실행에 안전하다.
3. Focus 동작이 `TaskProgressEvent` 의미나 Task 완료 규칙을 우회하지 않는다.
4. 각 기기에서 iPhone 앱과 Live Activity 또는 macOS 플로팅 패널이 그 기기의 같은 로컬
   세션을 표시한다.
5. Focus 완료 뒤 Task 상태는 자동으로 바뀌지 않고 사용자가 휴식 또는 다음 행동을 선택한다.
6. 종료된 FocusSession이 V10 SwiftData, CloudKit, backup package에 손실 없이 보존된다.
7. 활성 snapshot은 CloudKit·backup에 포함되지 않고 다른 기기에서 유령 타이머를 만들지 않는다.
8. 기존 Task count-up Live Activity, reminder, widget, archive 통계가 회귀하지 않는다.
9. 관련 단위·통합 테스트와 Debug/Release 전체 플랫폼 빌드가 통과한다.
10. iPhone, iPad, macOS 실기기 인수를 통과한 뒤 Watch 단계의 포함 여부를 출시 단위별로
    명확히 기록한다.
11. 집중·휴식 종료 알림의 문구, 단일 전달, 빠른 action과 stale/cold-launch 안전성이 Phase 9
    완료 조건과 실제 기기 인수를 통과한다.

## 17. 확정된 구현 기본값

아래 세 항목을 현재 구현의 제품 기본값으로 확정했다.

- 첫 출시 기본값: 집중 25분 / 휴식 5분, 자동 다음 구간 시작 없음
- 예상 시간이 있는 Task는 5~120분 범위의 예상 값을 새 집중 기본 시간으로 제안한다.
- Task 없는 자유 타이머 제외, Task 기반 Focus만 제공
- Watch는 iPhone/macOS 출시 이후 별도 단계로 제공하고 기기 간 활성 타이머 미러링은 제외
