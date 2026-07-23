# Task 완료 전환 시 알림 보존 설계 및 구현 기록

## 목적

사용자가 알림이 설정된 Task를 실수로 완료했다가 다시 `할 일` 또는 `진행 중`으로 되돌려도 알림 설정 기록을 잃지 않게 한다. 완료 전환 시 아직 울리지 않은 미래 알림이 있으면 경고하되, 이미 지난 알림 때문에 불필요한 확인창을 띄우지 않는다.

이 문서는 기존 [`TASK_REMINDER_PLAN.md`](../completed/TASK_REMINDER_PLAN.md)의 완료 처리 정책을 보완한 후속 설계와 구현 기록이다. 아래 정책은 공통 코어, iPhone, macOS 완료 경로에 반영되었고 검증 항목은 마지막 구현 상태에 기록한다.

## 구현 상태

- 완료: 공통 보존·미래 판정·수정 여부 규칙, 무결성/백업 테스트
- 완료: iPhone 카드·상세·이월 경고, 저장 성공 후 즉시 알림 취소, 기록 표시
- 완료: macOS 카드·상세·이월 경고와 기록 표시
- 완료: `PlanBaseMobileTests` fake notification-center 단위 테스트 타깃과 UI-testing fixture 추가
- 통과: SwiftPM Debug 225개·Release 224개 테스트
- 통과: iOS scheduler fake client 3개와 snapshot 파일 보호 1개를 포함한 단위 테스트 4개
- 통과: reminder 완료 시나리오 3개를 포함한 iPhone launch UI 테스트 8개
- 통과: iOS/macOS Debug/Release 빌드와 `git diff --check`
- 실기기 확인 필요: 신버전 iPhone ↔ 신버전 Mac CloudKit 완료·재개 왕복과 실제 알림 전달/취소

## 합의 정책

`Task.reminderAt`은 다음 두 역할을 가진다.

1. 알림을 설정했다는 기록
2. Task가 미완료이고 시각이 미래일 때 iPhone 로컬 알림을 재생성하는 원본

완료는 알림 기록의 삭제가 아니라 예약의 일시 중지로 취급한다. 사용자가 알림 토글을 명시적으로 끄거나 Task를 삭제한 경우에만 기록을 제거한다.

### 구현 범위와 전제

- 이 정책은 iPhone과 macOS에서 사용자가 직접 실행하는 모든 완료 동작에 동일하게 적용한다. macOS가 로컬 알림을 울리지는 않지만, macOS의 완료 상태가 CloudKit을 통해 iPhone의 미래 알림을 중지시키기 때문이다.
- 경고 여부는 현재 기기의 알림 권한이나 실제 pending 요청 존재 여부가 아니라 SwiftData의 정규화된 `reminderAt`만으로 판단한다. 권한 거절 상태여도 미래 알림 기록이 있으면 같은 경고를 표시한다.
- 이번 범위의 기록은 Task당 가장 최근에 설정된 시각 하나다. immutable audit log나 실제 전달 이력은 만들지 않는다. 사용자가 새 시각을 설정하면 이전 시각을 대체하고, 알림을 명시적으로 끄면 `nil`이 된다.
- 스키마를 추가하지 않고 현재 `reminderAt`을 보존하는 방향으로 확정한다. iOS와 macOS를 같은 공통 규칙으로 함께 배포하고, 사용 중인 모든 기기를 신버전으로 업데이트한 뒤 기록 보존을 보장한다.

### 완료 전환 결정표

| 전환 직전 상태 | `reminderAt` 조건 | 경고 | 완료 후 데이터 | 시스템 알림 |
|---|---|---|---|---|
| 미완료 | `nil` | 없음 | `nil` 유지 | 없음 |
| 미완료 | `reminderAt <= now` | 없음 | 시각 유지 | 예약하지 않음 |
| 미완료 | `reminderAt > now` | 표시 | 시각 유지 | 완료 확정 후 취소 |
| 완료 | 상태 변화 없음 | 없음 | 기존 시각 유지 | 예약하지 않음 |

미래 알림의 경고 문구는 다음 의미를 명확히 전달한다.

```text
예정된 알림이 있습니다
이 작업을 완료하면 예정된 알림이 중지됩니다.
알림 설정 기록은 계속 유지됩니다.
```

버튼은 `완료하기`와 `취소` 두 개로 둔다. `완료하기`는 상태만 완료로 바꾸고 `reminderAt`을 유지한다. `취소`는 상태와 알림 모두 변경하지 않는다.

### 다시 미완료로 전환할 때

| 전환 후 상태 | 보존된 알림 조건 | 처리 |
|---|---|---|
| `할 일` 또는 `진행 중` | 미래 시각 | 다음 reconcile에서 자동 재예약 |
| `할 일` 또는 `진행 중` | 현재 또는 과거 시각 | 기록만 유지하고 재예약하지 않음 |
| `할 일` 또는 `진행 중` | `nil` | 아무 알림도 만들지 않음 |

과거 알림을 자동으로 미래로 옮기지 않는다. 사용자가 새 시각을 선택해야 다시 예약된다.

보존된 과거 알림은 미완료 Task의 저장을 막지 않는다. 상세 화면에서 제목·상태·메모 등 다른 값을 수정했을 뿐 알림 토글과 시각을 바꾸지 않았다면 과거 `reminderAt`을 그대로 저장할 수 있어야 한다. 미래 시각 검증은 알림을 새로 켰거나 기존 시각을 실제로 변경한 경우에만 적용한다.

## 용어와 한계

`reminderAt`이 과거라는 사실은 “그 시각의 알림을 설정했었다”는 의미다. 집중 모드, 알림 요약, 기기 전원, 권한 상태 등에 따라 실제 배너가 사용자에게 전달됐는지는 보장하지 않는다.

이번 변경에서는 실제 전달 이력을 위한 `deliveredAt` 같은 새 필드를 추가하지 않는다. 따라서 UI에서도 `울린 알림`이 아니라 `설정했던 알림` 또는 `지난 알림`이라고 표현한다.

기존 버전에서 완료 처리와 함께 이미 `nil`로 지워진 알림 시각은 복원할 원본이 없으므로 소급 복구할 수 없다. 새 정책이 배포된 이후 완료되는 Task부터 기록이 보존된다.

## 현재 문제 지점

현재 코드는 다음 네 지점에서 완료 Task의 알림 값을 제거하거나 즉시 취소 완료를 보장하지 못한다.

1. `shared/Core/Services/TaskRules.swift`
   - `applyStatus(.done)`가 `task.reminderAt = nil`을 수행한다.
   - 이미 완료 상태인 Task에도 다시 `applyStatus(.done)`가 호출되면 알림을 지운다.
   - `setReminder`는 Task 상태가 완료이면 전달된 값과 무관하게 `nil`로 정규화한다.
2. `shared/Core/Services/DataIntegrityService.swift`
   - 완료 Task의 `reminderAt`을 무결성 정리 과정에서 `nil`로 만든다.
3. `mobile/App/Features/Board/MobileTaskDetailSheet.swift`
   - 상세 화면에서 상태를 완료로 선택하면 `reminderEnabled = false`로 바꾼다.
   - 저장 시 `TaskRules.setReminder(nil, ...)`가 호출되어 기록이 사라진다.
   - 미완료 Task에 과거 알림이 남아 있으면 알림을 수정하지 않은 저장도 만료 검증에 걸린다.
4. `mobile/App/Infrastructure/TaskNotificationScheduler.swift`
   - 데이터 변경 후 전체 reconcile은 비동기로 시작된다.
   - 이미 reconcile 중인 호출은 다음 pass만 요청하고 즉시 반환하므로, 호출자가 실제 pending 알림 제거 완료까지 기다렸다고 볼 수 없다.

반면 scheduler는 이미 완료 Task를 예약 대상에서 제외한다. 따라서 데이터 삭제 규칙만 제거해도 완료 Task의 로컬 알림은 계속 중지된 상태를 유지할 수 있다.

## 구현 원칙

### 1. 공통 데이터 규칙

대상 파일:

- `shared/Core/Services/TaskRules.swift`
- `shared/Core/Services/TaskReminderRules.swift`
- `shared/Core/Services/DataIntegrityService.swift`

변경 사항:

1. `TaskRules.applyStatus(.done)`에서 `reminderAt`을 지우지 않는다.
2. 이미 완료 상태일 때 `applyStatus(.done)`가 호출되어도 알림 기록을 건드리지 않는다.
3. `TaskRules.setReminder`는 Task 상태와 무관하게 전달된 시각을 분 단위로 정규화한다.
   - `nil` 전달은 사용자의 명시적 알림 해제로 취급한다.
   - 완료 Task에 보존된 값은 예약 원본이 아니라 설정 기록으로 남는다.
4. `DataIntegrityService`는 완료 여부와 무관하게 유효한 `reminderAt`을 정규화해 보존한다.
5. 미래 알림 여부를 판단하는 순수 규칙을 `TaskReminderRules`에 추가한다.
   - 조건은 정규화된 `reminderAt > now`다.
   - `nil`, 현재 분, 과거 시각은 경고 대상이 아니다.
   - UI에서 날짜 비교를 중복 구현하지 않게 단일 Task와 Task 배열용 helper를 제공한다.
   - Task ID에 대응하는 신규/레거시 알림 식별자 집합도 공통 helper로 계산한다.
6. 완료 판단 helper는 `now`를 인자로 받아 alert 결정과 테스트에서 같은 기준 시각을 사용한다.
7. 완료 확정 대기 상태에는 SwiftData 모델 객체 자체가 아니라 논리 `taskID`를 저장한다. alert 확인 시 활성 Task를 ID로 다시 조회해 삭제·supersede·CloudKit 변경 여부를 반영한다.

alert가 열린 동안 알림 시각이 과거가 되더라도 두 번째 경고를 띄우지 않는다. 사용자가 이미 경고를 확인했으므로 최신 Task를 완료하고 최신 `reminderAt`을 보존한다. 대상 Task가 삭제됐거나 대표 레코드가 아니게 됐다면 완료 명령을 실행하지 않고 안전하게 종료한다.

스키마와 백업 형식은 변경하지 않는다. 기존 optional `reminderAt` 필드를 그대로 사용하므로 migration이나 CloudKit schema 배포도 필요하지 않다.

### 2. 예약 수렴 로직

대상 파일:

- `shared/Core/Services/BoundedQueryService.swift`
- `shared/Core/Services/TaskReminderRules.swift`
- `mobile/App/Infrastructure/TaskNotificationScheduler.swift`

예약 가능 집합과 전체 수렴 규칙은 현재 구조를 유지한다.

- `activeReminderTasksDescriptor`는 완료 Task를 fetch하지 않는다.
- `TaskReminderRules.snapshot`은 `todo`와 `doing`, 미래 시각만 예약 대상으로 만든다.
- 완료 저장 후 `PersistenceCommandService.dataChangedNotification`이 발생하면 scheduler가 기존 pending 요청을 고아 요청으로 판단해 제거한다.
- 완료 Task를 다시 미완료로 바꾸면 미래 `reminderAt`이 descriptor와 snapshot에 다시 포함되어 자동 예약된다.
- 보존된 시각이 과거이면 snapshot에서 제외되므로 재예약되지 않는다.

단, 사용자가 미래 알림 경고를 확인하고 완료한 직후에는 전체 비동기 reconcile에만 의존하지 않는다. `TaskNotificationScheduler`에 Task ID 배열을 받는 idempotent 즉시 취소 API를 추가한다.

완료 확정 순서는 다음과 같다.

```text
1. PersistenceCommandService로 완료 상태 저장
2. 저장 성공 후에만 해당 taskID의 pending/delivered 요청 즉시 제거
3. 전체 reconcile을 요청해 나머지 알림과 최종 수렴
4. 완료 안내와 화면 닫기
```

- 저장 실패 또는 rollback이면 시스템 알림을 건드리지 않는다.
- 즉시 취소 API는 신규 `planbase.task-reminder.`와 레거시 `easytask.task-reminder.` 식별자를 모두 제거한다.
- `UNUserNotificationCenter` 직접 호출은 UI에 흩어놓지 않고 scheduler 내부에만 둔다.
- 단일 완료와 일괄 완료가 같은 API를 사용한다.
- Debug UI-testing 환경에서는 reconcile과 즉시 취소를 모두 no-op으로 두고 시스템 알림 센터를 건드리지 않는다. 시스템 호출은 주입한 fake client 단위 테스트로 검증한다.
- 운영체제 알림과 SwiftData 저장을 하나의 원자적 트랜잭션으로 만들 수는 없다. 위 순서는 저장 성공 직후 취소 요청을 제출해 경쟁 구간을 최소화하고, 앱 시작/active/reconcile을 최종 안전망으로 둔다.
- CloudKit import나 백업 병합처럼 UI 밖에서 완료 상태가 들어오는 경로는 기존 전체 reconcile로 정리한다.

### 3. 모바일 칸반 카드 상태 변경

대상 파일:

- `mobile/App/Features/Board/MobileBoardView.swift`
- 필요 시 `mobile/App/Features/Board/MobileBoardComponents.swift`

현재 카드의 상태 슬라이더는 `MobileBoardView.changeTaskStatus`를 즉시 호출한다. 이를 요청과 확정 두 단계로 분리한다.

```text
상태 변경 요청
  → 목표 상태가 완료가 아니면 즉시 저장
  → 이미 완료 상태라면 기존 처리
  → 미완료 → 완료이며 미래 알림이 없으면 즉시 저장
  → 미완료 → 완료이며 미래 알림이 있으면 alert 표시
      ├─ 취소: 아무 변경 없음
      └─ 완료하기: 상태 저장, reminderAt 보존
```

alert에는 Task 제목과 예정된 알림 시각을 표시한다. alert가 떠 있는 동안 다른 Task와 혼동하지 않도록 pending task ID와 목표 상태를 하나의 상태 값으로 보관한다.

### 4. 모바일 작업 상세 저장

대상 파일:

- `mobile/App/Features/Board/MobileTaskDetailSheet.swift`

변경 사항:

1. 상태를 완료로 선택할 때 `reminderEnabled`를 자동으로 `false`로 바꾸는 코드를 제거한다.
2. `저장` 버튼 동작을 `저장 요청`과 `실제 저장`으로 분리한다.
3. 기존 상태가 미완료이고 새 상태가 완료이며, 폼에 남아 있는 알림 시각이 미래인 경우에만 alert를 표시한다.
4. 사용자가 먼저 알림 토글을 직접 끈 뒤 완료하면 명시적 삭제로 보아 경고 없이 `nil`을 저장한다.
5. 경고에서 완료를 확정하면 `reminderAt`을 유지한 채 상태를 완료로 저장한다.
6. 이미 완료된 Task를 열었을 때는 토글을 비활성화하되 보존된 시각을 `설정했던 알림`으로 보여준다.
7. 완료 Task를 `할 일` 또는 `진행 중`으로 바꾸면 토글과 시각 편집을 다시 활성화한다.
8. 화면 진입 시의 `initialReminderEnabled`와 정규화된 `initialReminderAt`을 보관하고 현재 폼과 비교해 `reminderWasEdited`를 계산한다.
9. 미완료 상태 저장 시 과거 알림이어도 `reminderWasEdited == false`면 저장을 허용한다.
10. 알림을 새로 켰거나 시각을 변경해 `reminderWasEdited == true`라면 기존처럼 미래 시각만 허용한다.
11. 상세 저장의 alert 확인 시에도 Task를 ID로 다시 조회하고, 저장 성공 후 즉시 취소 API를 호출한다.

상세 저장 도중 시각이 현재를 지나더라도 과거 알림 정책을 적용해 완료 자체를 막지 않는다. 미완료 상태로 저장하면서 알림을 켜는 기존 경로만 계속 미래 시각을 요구한다.

### 5. 모바일 이월함 일괄 완료

대상 파일:

- `mobile/App/Features/Board/MobileCarryoverSheet.swift`

`원래 날짜에 모두 완료`는 여러 Task를 한 번에 완료하므로 동일한 정책을 적용한다.

- 미래 알림이 있는 Task가 0개면 즉시 완료한다.
- 1개 이상이면 한 번만 alert를 표시하고 대상 개수를 안내한다.
- `완료하기`를 누르면 전체 Task를 완료하되 모든 `reminderAt` 기록을 유지한다.
- `취소`하면 어느 Task도 변경하지 않는다.
- 지난 알림만 있는 경우에는 alert를 표시하지 않는다.
- alert 대기 상태에는 대상 Task ID 목록을 고정해 보관한다. 확인 시 현재 활성 Task를 다시 조회하고 삭제되거나 이미 완료된 항목은 제외한다.

예시 문구:

```text
예정된 알림 2개가 있습니다
모두 완료하면 해당 알림이 중지됩니다.
알림 설정 기록은 계속 유지됩니다.
```

### 6. macOS 완료 경로

대상 파일:

- `desktop/App/Features/Board/BoardView.swift`
- `desktop/App/Features/Board/DesktopTaskDetailSheet.swift`
- `desktop/App/Features/Board/DesktopKanbanComponents.swift`

macOS는 알림을 직접 예약하지 않지만 완료 변경이 iPhone 알림을 중지시키므로 같은 미래 알림 경고를 적용한다.

- 보드의 클릭/상태 변경과 drag/drop 완료 요청을 저장 전 요청 단계로 분리한다.
- 미래 알림이 있는 카드를 완료 열로 drop하면 즉시 상태를 바꾸지 않고 pending completion을 저장한 뒤 alert를 표시한다. 취소 시 원래 열에 남고, 확인 시 최신 Task를 다시 조회해 완료한다.
- `DesktopTaskDetailSheet`에서 미완료 → 완료로 저장할 때 같은 alert를 표시한다.
- `completeAllCarryoverTasks`는 미래 알림 Task 수를 한 번 안내하고 일괄 완료한다.
- macOS에는 로컬 pending 요청이 없으므로 즉시 취소 API를 호출하지 않는다. CloudKit import를 받은 iPhone이 해당 Task를 전체 reconcile에서 제거한다.

### 7. 알림 기록 표시

대상 파일:

- `mobile/App/Features/Board/MobileBoardComponents.swift`
- `mobile/App/Features/Board/MobileTaskDetailSheet.swift`
- `desktop/App/Features/Board/DesktopKanbanComponents.swift`
- `desktop/App/Features/Board/DesktopTaskDetailSheet.swift`

보존된 값이 실제 활성 예약인지 과거 기록인지 구분해 표시한다.

| Task/시각 상태 | 표시 제안 |
|---|---|
| 미완료 + 미래 | 기존 `bell.fill`과 예정 시각 |
| 미완료 + 과거 | `bell.slash`와 `지난 알림` 시각 |
| 완료 + 시각 있음 | `bell.slash`와 `설정했던 알림` 시각 |
| 시각 없음 | 알림 chip/기록 없음 |

완료 카드에 미래 시각이 남아 있어도 활성 알림처럼 보이지 않게 `중지됨` 의미를 시각적으로 전달한다.

## 경고를 표시하지 않는 경로

다음은 사용자와 상호작용 중인 완료 명령이 아니므로 modal 경고를 띄우지 않는다.

- CloudKit에서 완료 상태를 import한 경우
- 백업 병합으로 완료 상태가 들어온 경우
- 데이터 무결성 수렴 과정
- 앱 시작 시 기존 완료 Task를 읽는 경우

이 경우에도 공통 데이터 규칙은 `reminderAt`을 보존하고, iPhone scheduler는 pending 알림만 제거한다.

## 확정된 혼합 버전·배포 정책

이번 계획은 기존 `reminderAt` 필드의 의미만 확장하므로 schema migration은 필요하지 않지만, 구버전 앱은 완료 Task의 값을 계속 `nil`로 정리한다. 신버전과 구버전이 같은 CloudKit private database를 동시에 사용하면 구버전이 보존된 기록을 다시 지워 동기화할 수 있다.

이 위험에 대해서는 다음 방향으로 확정한다.

1. 별도 history 필드나 새 `VersionedSchema`를 추가하지 않고 기존 `reminderAt`을 사용한다.
2. iOS와 macOS에 같은 공통 코어 변경을 포함해 같은 배포 단위로 출시한다.
3. 릴리스 안내에 iPhone과 Mac 등 PlanBase를 사용하는 모든 기기를 신버전으로 업데이트해야 한다고 명시한다.
4. 구버전 클라이언트가 남아 있는 혼합 기간에는 기록이 다시 삭제될 수 있음을 알려진 제한으로 수용한다.
5. 모든 활성 기기가 신버전이 된 이후의 완료·재개·백업·CloudKit 왕복부터 기록 보존을 보장한다.
6. 혼합 기간에 구버전이 이미 지운 `reminderAt`은 복원 가능한 원본이 없으므로 자동 복구하지 않는다.

배포 검증은 신버전 iPhone과 신버전 Mac 사이의 양방향 완료·재개 수렴을 기준으로 한다. 구버전 공존 보장은 이번 변경의 완료 기준에서 제외한다.

## 테스트 계획

### 공통 단위 테스트

대상: `shared/Tests/TaskReminderRulesTests.swift`

1. 미래 알림이 있는 Task를 완료해도 `reminderAt`이 유지된다.
2. 지난 알림이 있는 Task를 완료해도 `reminderAt`이 유지된다.
3. 이미 완료된 Task에 완료 상태를 다시 적용해도 값이 유지된다.
4. 완료 Task에서 `setReminder(nil)`을 명시적으로 호출하면 값이 삭제된다.
5. 완료 Task의 알림 시각도 분 단위로 정규화된다.
6. 완료 Task는 시각이 미래여도 snapshot 대상이 아니다.
7. 완료 후 다시 `todo` 또는 `doing`으로 바꾸면 미래 알림은 snapshot 대상이 된다.
8. 완료 후 다시 미완료로 바꿔도 과거 알림은 snapshot 대상이 아니다.
9. 미래 판정 helper는 `nil`, 과거, 현재, 미래 경계를 올바르게 구분한다.
10. 여러 Task 중 미래 알림 개수를 정확히 계산한다.
11. 신규/레거시 알림 식별자 helper가 같은 논리 Task ID로 결정적으로 계산된다.

### 무결성 테스트

기존 `integrityNormalizesReminderAndClearsCompletedReminder` 테스트를 새 정책에 맞게 변경한다.

- 미완료와 완료 Task 모두 유효한 시각을 분 단위로 정규화해 보존한다.
- 비유한 시각만 `nil`로 정리한다.
- 중복 Task 수렴에서 선택된 대표 레코드의 완료 상태와 알림 시각 조합이 그대로 유지된다.

### 백업·동기화 테스트

대상:

- `shared/Tests/BackupPackageTests.swift`
- `shared/Tests/DataIntegrityTests.swift`
- 필요 시 `shared/Tests/CloudKitConvergenceProbeTests.swift`

1. 미래 알림을 보존한 완료 Task가 현재 package export/import 후 동일한 `reminderAt`을 가진다.
2. 지난 알림을 보존한 완료 Task도 package merge와 무결성 정리 후 값을 유지한다.
3. 명시적으로 알림을 끈 더 최신 Task는 백업 병합 후 `nil`을 유지한다.
4. CloudKit import 뒤 완료 Task 기록은 보존되고 iPhone 예약 집합에서는 제외된다.
5. 다른 기기에서 다시 미완료로 바꾼 미래 알림 Task는 import 후 예약 집합에 포함된다.

### 수렴 테스트

1. 미래 pending 요청이 있는 Task를 완료하면 해당 요청이 취소 계획에 포함된다.
2. 완료 Task를 미래 시각 그대로 다시 미완료로 바꾸면 예약 계획에 포함된다.
3. 지난 시각을 가진 Task는 미완료로 복귀해도 예약 계획에 포함되지 않는다.
4. PlanBase가 관리하지 않는 다른 알림은 취소하지 않는다.
5. 즉시 취소 API가 신규/레거시 식별자의 pending과 delivered 요청을 모두 제거한다.
6. 여러 Task 일괄 취소가 중복 ID에도 idempotent하게 동작한다.
7. 저장 실패 경로에서는 즉시 취소 API가 호출되지 않는다.

실제 `UNUserNotificationCenter` 호출을 자동 검증할 수 있도록 얇은 notification-center client protocol과 시스템 adapter를 scheduler 내부에 둔다. fake client를 주입하는 iOS 단위 테스트가 필요하므로 `PlanBaseMobileTests` 타겟을 추가하고 `PlanBase-iOS` scheme의 TestAction에 포함한다. 순수 예약 판단은 계속 `PlanBaseCoreTests`에서 검증하고, iOS 타겟에서는 add/remove 호출과 동시 reconcile 동작만 검증한다.

### 상세 편집 검증 테스트

1. 기존 과거 알림을 수정하지 않고 제목만 바꾸면 저장 가능하다.
2. 완료 Task의 과거 알림을 수정하지 않고 `todo`/`doing`으로 바꾸면 저장 가능하고 값이 유지된다.
3. 기존 과거 알림을 다른 과거 시각으로 변경하면 저장을 거부한다.
4. 알림을 새로 켰지만 저장 전에 시각이 지나면 저장을 거부한다.
5. 기존 미래 알림이 화면을 여는 동안 과거가 된 경우, 알림을 수정하지 않은 다른 필드 저장은 허용한다.
6. 알림 토글을 직접 끄면 상태와 관계없이 `nil` 저장을 허용한다.
7. alert 대기 후 다시 조회한 Task가 삭제·supersede된 경우 완료 대상에서 제외된다.
8. 알림 권한 거절 상태에서도 미래 `reminderAt`이면 같은 완료 경고를 표시한다.

### 모바일 UI/수동 검증

1. 알림 없는 카드 완료: alert 없음.
2. 지난 알림 카드 완료: alert 없음, 완료 카드에 기록 표시.
3. 미래 알림 카드 완료: alert 표시.
4. alert 취소: 상태와 pending 알림 모두 유지.
5. alert 완료 확정: 완료 상태, `reminderAt` 유지, pending 알림 제거.
6. 완료 Task를 미래 시각이 남은 채 진행 중으로 복귀: pending 알림 재생성.
7. 완료 Task를 지난 시각이 남은 채 진행 중으로 복귀: 재생성 없음.
8. 상세 화면에서 미래 알림이 있는 Task 완료 저장: 동일 alert와 결과.
9. 상세 화면에서 알림을 직접 끄고 완료: alert 없이 값 삭제.
10. 이월함 일괄 완료: 미래 알림 Task 수가 맞고 취소 시 전부 무변경.
11. 앱 재실행과 foreground 복귀 후에도 완료 Task 알림이 재예약되지 않음.
12. CloudKit으로 다시 미완료 상태가 들어오면 미래 알림만 재예약됨.
13. 상세 화면에서 보존된 과거 알림을 수정하지 않고 재개·제목 수정 저장이 가능함.
14. 완료 저장 성공 직후 신규/레거시 pending 요청이 제거됨.
15. alert가 열린 동안 Task를 삭제하거나 외부 변경한 경우 crash나 stale 저장이 없음.

UI 경고 조건은 수동 검증에만 두지 않는다. Debug UI-testing 전용 in-memory fixture에 알림 없음/과거/미래 Task를 생성하는 launch argument를 추가하고 `PlanBaseLaunchUITests`에서 다음을 검증한다.

- 알림 없음과 과거 알림 완료에는 alert가 나타나지 않는다.
- 미래 알림 완료에는 alert가 나타나며 `취소`는 상태를 유지한다.
- `완료하기`는 카드를 완료 상태로 이동시키고 보존 기록 label을 노출한다.
- 이월함 일괄 완료 alert가 미래 알림 Task 개수를 표시한다.
- alert 제목과 버튼은 접근성 트리에서 안정적으로 조회된다.

UI test 환경에서는 실제 notification scheduler가 비활성화되므로 pending 요청 add/remove는 `PlanBaseMobileTests`의 fake client 테스트가 담당한다.

### macOS 수동 검증

1. 보드 버튼과 drag/drop 완료에서 미래 알림만 경고한다.
2. 상세 저장과 이월함 일괄 완료도 같은 조건과 문구를 사용한다.
3. alert 취소 시 카드 위치와 데이터가 바뀌지 않는다.
4. 완료 카드와 상세가 알림을 활성 예약처럼 표시하지 않는다.
5. macOS에서 완료한 상태가 iPhone에 import되면 iPhone pending 알림이 제거되고 기록은 유지된다.

## 검증 명령

공통 규칙 테스트:

```bash
swift test --filter taskReminder
```

전체 공통 테스트:

```bash
swift test
```

iOS 빌드:

```bash
xcodebuild -quiet \
  -project PlanBase.xcodeproj \
  -scheme PlanBase-iOS \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath "${TMPDIR:-/tmp}/PlanBaseReminderCompletion" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

iOS 단위/UI 테스트는 설치된 simulator UDID를 선택해 실행한다.

```bash
xcodebuild -quiet \
  -project PlanBase.xcodeproj \
  -scheme PlanBase-iOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<simulator-udid>' \
  -derivedDataPath "${TMPDIR:-/tmp}/PlanBaseReminderCompletionTests" \
  test
```

공유 코어 변경은 macOS에도 링크되므로 최종적으로 전체 회귀 게이트를 실행한다.

```bash
./scripts/verify-platform-builds.sh
```

## 구현 순서

1. iOS와 macOS가 함께 사용하는 `TaskReminderRules`에 미래 알림 판정과 단일/배치 완료 판단 helper를 추가한다.
2. `TaskRules`와 `DataIntegrityService`가 완료 Task의 알림을 보존하도록 변경한다.
3. 공통 단위·무결성·백업·수렴 테스트를 새 정책으로 갱신한다.
4. scheduler에 신규/레거시 식별자를 처리하는 즉시 취소 API와 notification-center adapter를 추가한다.
5. `PlanBaseMobileTests` 타겟과 fake client 기반 add/remove/reconcile 테스트를 추가한다.
6. 모바일 카드의 단일 완료 alert, ID 재조회, 저장 후 즉시 취소 흐름을 구현한다.
7. 작업 상세의 reminder 수정 여부 판정, 저장 전 alert, 과거 기록 보존을 구현한다.
8. 모바일 이월함 일괄 완료 alert와 ID 기반 재검증을 구현한다.
9. macOS 보드·상세·이월함 완료 경고를 동일한 공통 판단 규칙으로 구현한다.
10. 양 플랫폼의 알림 표시를 활성/지난/완료 기록 상태에 맞게 구분한다.
11. UI-testing fixture와 모바일 alert UI 테스트를 추가한다.
12. iOS 단위/UI 테스트와 양 플랫폼 수동 수명주기를 검증한다.
13. 신버전 iPhone ↔ 신버전 Mac의 완료·재개 CloudKit 수렴을 검증한다.
14. 전체 패키지 및 양 플랫폼 회귀 게이트를 실행한다.
15. 기존 알림 문서, 아키텍처 문서와 릴리스 안내에 완료 정책·전체 기기 업데이트 요구사항을 반영한다.

## 완료 기준

- 지난 알림 또는 알림이 없는 Task는 경고 없이 완료된다.
- 미래 알림이 있는 Task만 완료 확인 alert를 표시한다.
- alert 취소 시 어떤 데이터나 시스템 알림도 바뀌지 않는다.
- 완료 저장이 실패하면 시스템 알림은 그대로 유지된다.
- 완료 저장이 성공하면 `reminderAt`은 보존되고 해당 신규/레거시 pending·delivered 알림에는 즉시 제거 요청이 제출된다.
- 다시 미완료로 전환하면 미래 알림만 자동으로 재예약된다.
- 수정하지 않은 지난 알림은 미완료 복귀나 다른 필드 저장을 막지 않는다.
- 새로 켜거나 변경한 알림만 미래 시각 검증을 받는다.
- 사용자가 알림을 명시적으로 끈 경우에만 기록이 삭제된다.
- iPhone과 macOS의 단일 완료, 상세 저장, 이월함 일괄 완료가 같은 정책을 따른다.
- alert 확인 시 Task를 ID로 다시 조회해 삭제·supersede된 stale 모델을 저장하지 않는다.
- 양 플랫폼에서 완료/지난 알림 기록이 활성 알림으로 오해되지 않게 표시된다.
- SwiftData schema, CloudKit schema, 백업 포맷 변경 없이 동작한다.
- 현재 백업 package round trip과 CloudKit import 후에도 완료 Task의 기록이 유지된다.
- 새 schema 없이 기존 `reminderAt`을 사용하며, iOS와 macOS 신버전에 동일한 보존 규칙이 포함된다.
- 릴리스 안내에 모든 사용 기기를 신버전으로 업데이트해야 기록 보존이 보장된다는 제한이 포함된다.
- 신버전 iPhone과 신버전 Mac 사이의 완료·재개 CloudKit 왕복이 기록을 유지한다.
- 공통 테스트, iOS scheduler 단위 테스트, 모바일 UI 테스트와 iOS/macOS 빌드가 모두 통과한다.
