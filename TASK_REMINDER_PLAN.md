# EasyTask Task 알림 구현 계획

## 목표

- `Task` 하나에 선택적인 1회성 알림 하나를 저장한다.
- 알림 데이터는 SwiftData와 CloudKit을 통해 macOS와 iPhone이 공유한다.
- 첫 MVP의 실제 알림 예약과 표시는 iPhone에서만 담당한다.
- macOS는 동기화된 알림 시각을 표시하되, 실제 알림 예약은 후속 단계로 둔다.
- 빠른 작업 추가 흐름은 바꾸지 않고 작업 상세에서만 알림을 설정한다.

## 확정 결정

```swift
var reminderAt: Date?
```

- `nil`: 알림 없음
- 값 있음: 해당 절대 시각에 한 번 알림
- 반복, 여러 알림, 위치 알림, 템플릿 알림은 MVP에서 제외
- `plannedAt`은 보드 날짜 전용이므로 알림 시각으로 재사용하지 않는다.
- 시스템의 pending notification은 캐시이며 `Task.reminderAt`이 원본 데이터다.
- 시스템 알림 식별자는 `easytask.task-reminder.<task.id>`로 고정한다.
- 완료된 작업, 삭제된 작업, 대표 레코드가 아닌 작업에는 알림을 예약하지 않는다.

## 현재 구조와 영향 범위

현재 `Task`는 다음 정보를 한 레코드에 가진다.

- 논리/물리 식별자: `id`, `instanceID`
- 보드 정보: `status`, `plannedAt`, `plannedDayKey`, `order`
- 상세 정보: `title`, `note`, `priority`, `tags`, `estimatedMinutes`
- 연결 정보: `eventId`, `templatePlacementId`
- 수명주기: `createdAt`, `updatedAt`, 완료/보관 시각, `supersededAt`

알림 추가 시 함께 변경해야 하는 영역은 다음과 같다.

- SwiftData 버전 스키마와 마이그레이션
- 데이터 무결성 및 충돌 비교
- JSON V1/패키지 V2 백업 DTO와 병합
- iPhone 작업 상세 UI
- iOS 로컬 알림 권한, 예약, 취소, 탭 처리
- 앱 시작, 저장 성공, CloudKit import 이후 예약 목록 재조정
- macOS 작업 카드/상세의 읽기 전용 알림 표시

## 1. 데이터 스키마

### V4 추가

- 기존 V1, V2, V3 파일은 수정하지 않는다.
- `EasyTaskSchemaV4`를 추가하고 현재 모델 전체를 동결 복사한다.
- V4 `Task`에 `reminderAt: Date?`를 추가한다.
- `EasyTaskMigrationPlan`에 V3 → V4 lightweight migration을 추가한다.
- `AppModels`와 `EasyTaskContainerFactory`의 현재 스키마를 V4로 변경한다.
- 기존 Task는 마이그레이션 후 `reminderAt == nil`이어야 한다.

### 무결성 규칙

- 유한하지 않은 알림 시각은 `nil`로 정리한다.
- `status == done`인 Task의 `reminderAt`은 `nil`로 정리한다.
- 과거 알림은 데이터에서 강제 삭제하지 않고 예약 대상에서만 제외한다.
- `supersededAt != nil`인 Task는 예약 대상에서 제외한다.
- 충돌 대표 Task를 선택할 때 `reminderAt`도 해당 대표 레코드의 스칼라로 취급한다.

## 2. 백업과 CloudKit

### 백업

- `TaskDTO`에 optional `reminderAt`을 추가한다.
- 내보내기, 가져오기, 병합 적용, 동일성 비교에 필드를 포함한다.
- 기존 백업에 필드가 없어도 `nil`로 읽히게 유지한다.
- additive optional 변경이므로 JSON V1과 패키지 V2 버전은 올리지 않는다.
- 신규 백업을 이전 앱이 읽을 때 알 수 없는 필드를 무시하는지 회귀 테스트한다.

### CloudKit

- Development 환경에서만 V4 스키마를 초기화한다.
- iPhone → macOS, macOS → iPhone의 알림 설정·변경·해제 전파를 검증한다.
- 현재 데이터 기반 검증이 끝나기 전에는 Production 스키마로 승격하지 않는다.
- CloudKit은 `reminderAt`만 동기화한다. 실제 로컬 알림 요청은 각 기기에서 별도로 만든다.

## 3. 공통 알림 규칙

`EasyTaskCore`에는 UserNotifications에 의존하지 않는 순수 규칙만 둔다.

```text
TaskReminderRules
  isSchedulable(task, now)
  notificationIdentifier(taskID)
  normalizedReminderAt(value)
  snapshot(task)
```

예약 가능 조건:

- 활성 대표 Task
- 상태가 `todo` 또는 `doing`
- `reminderAt`이 존재
- `reminderAt > now`
- 제목이 비어 있지 않음

`TaskReminderSnapshot`은 `taskID`, `title`, `plannedDayKey`, `reminderAt`만 가진
Sendable 값 타입으로 만들고, UserNotifications adapter에 SwiftData 모델을 직접 넘기지 않는다.

## 4. iOS 알림 계층

`EasyTaskiOS`에 `TaskNotificationScheduler`를 둔다.

역할:

- 현재 알림 권한 조회
- 첫 알림 설정 시 `.alert`, `.sound` 권한 요청
- 고정 식별자로 1회성 `UNCalendarNotificationTrigger` 예약
- 변경 시 같은 식별자의 요청을 교체
- 완료, 삭제, 알림 해제 시 pending/delivered 알림 제거
- 활성 Task 스냅샷과 시스템 pending 요청 전체를 비교해 누락·고아 요청 정리

알림 내용:

- 제목: Task 제목
- 본문: `예정된 작업 시간입니다.`
- 소리: 시스템 기본음
- `userInfo`: `taskID`, `plannedDayKey`
- 메모와 태그는 잠금화면 개인정보 노출을 줄이기 위해 포함하지 않는다.

권한 정책:

- 앱 첫 실행에서는 요청하지 않는다.
- 사용자가 첫 알림을 켜고 저장할 때 요청한다.
- 거절 상태에서도 `reminderAt`은 보존한다.
- 거절된 경우 작업 상세에 상태와 시스템 설정 이동 버튼을 표시한다.

## 5. 예약 재조정

개별 삭제 함수마다 취소 코드를 흩어놓지 않고 coordinator가 최종 상태를 맞춘다.

`TaskReminderCoordinator` 실행 시점:

1. 앱 시작과 active 전환
2. Task 저장 명령 성공 후
3. Task 완료 또는 삭제 후
4. 템플릿 배치 삭제 후
5. 백업 가져오기 완료 후
6. CloudKit import 성공 및 무결성 정리 후
7. 시스템 시간대 변경 후

처리 순서:

1. `reminderAt != nil`인 활성 Task만 제한 조회한다.
2. 예약 가능한 스냅샷 집합을 만든다.
3. `easytask.task-reminder.` prefix의 pending 요청을 조회한다.
4. 사라지거나 완료된 Task 요청을 제거한다.
5. 시각 또는 제목이 달라진 요청을 같은 식별자로 교체한다.
6. 누락된 요청을 추가한다.

저장 트랜잭션이 실패한 경우에는 알림 상태를 변경하지 않는다.

## 6. 모바일 UI

작업 상세의 `상세` 아래에 `알림` 섹션을 추가한다.

- 알림 토글
- `10분 후`, `30분 후`, `1시간 후` 빠른 선택
- 날짜와 시간을 함께 선택하는 DatePicker
- 현재 시각 이전이면 저장 불가 메시지
- 알림 권한 거절 시 `설정에서 알림 허용` 버튼

초깃값:

- 미래 보드 날짜: 해당 날짜 오전 9시
- 오늘 또는 과거 보드 날짜: 현재 시각에서 1시간 후

표시:

- 알림이 있는 카드에는 `bell` 아이콘과 짧은 시각 표시
- 완료 Task에는 알림 편집을 비활성화한다.
- 빠른 Task 추가에는 알림 입력을 넣지 않는다.

알림을 탭하면 우선 해당 `plannedDayKey`의 칸반보드로 이동한다. 특정 Task 상세를
자동으로 여는 동작은 안정화 후 추가한다.

## 7. macOS 범위

MVP에서는 다음만 포함한다.

- Task 카드와 상세 화면에 동기화된 알림 시각 표시
- 실제 macOS 알림 예약과 권한 요청은 하지 않음
- macOS 알림 편집도 첫 배포에서는 비활성화

후속 단계에서 기기별 `Mac에서도 알림` 설정을 로컬 UserDefaults로 추가하면 같은
`reminderAt`을 사용해 macOS 예약을 켤 수 있다. 기본값은 꺼짐으로 두어 iPhone과 Mac의
중복 알림을 방지한다.

## 8. 테스트 계획

### 단위 테스트

- V3 저장소가 V4로 이동하고 기존 Task의 알림이 `nil`인지 확인
- 미래의 todo/doing Task만 예약 대상인지 확인
- 완료, 과거, superseded Task가 제외되는지 확인
- 알림 식별자가 Task ID로 결정적인지 확인
- 상태를 done으로 변경하면 `reminderAt`이 정리되는지 확인
- 기존/신규 백업 round trip과 병합 동일성 확인
- 동일 Task 중복 수렴 후 대표 알림만 남는지 확인

### Scheduler 테스트

UserNotifications를 protocol 뒤로 감추고 fake scheduler로 검증한다.

- 신규 예약
- 같은 ID의 시각 변경
- 알림 해제
- 완료/삭제 후 고아 요청 제거
- 권한 거절 시 데이터는 보존하고 예약만 생략
- 여러 번 reconcile해도 결과가 같은지 확인

### 실기기 검증

- 2분 뒤 알림을 설정하고 foreground/background/앱 종료 상태에서 확인
- 알림 변경과 해제 확인
- 완료 및 삭제 직후 알림이 취소되는지 확인
- 알림 탭 시 해당 날짜 보드 이동 확인
- iPhone 재부팅 후 pending 요청 유지 확인
- CloudKit 양방향 설정·변경·해제 수렴 확인
- 앱 재설치 후 CloudKit 데이터 복구와 예약 재생성 확인

집중 모드, 알림 요약과 시스템 정책에 따라 표시 시각이 늦어질 수 있음을 실패와 구분한다.

## 9. 구현 및 Git 순서

현재 데이터 기반/CloudKit 검증 브랜치를 먼저 정리하고 clean `main`에서 시작한다.

```text
feature/task-reminder-v4
```

권장 커밋:

1. `feat(data): add optional task reminder schema v4`
2. `feat(core): add reminder rules and backup support`
3. `feat(ios): schedule and reconcile task notifications`
4. `feat(ios): add task reminder editor and board navigation`
5. `test: cover reminder migration sync and cancellation`
6. `docs: document task reminder lifecycle`

각 커밋에서 `swift test`, iOS 빌드, macOS 빌드를 통과시킨다. V4 변경을 Production
CloudKit에 배포한 뒤에는 필드를 제거하는 롤백을 하지 않고 optional 상태로 유지한다.

## 완료 기준

- 기존 데이터 손실 없이 V4 저장소가 열린다.
- 사용자가 Task 하나에 미래 알림 하나를 저장·변경·해제할 수 있다.
- 앱이 종료되어도 iPhone에서 알림이 표시된다.
- 완료·삭제된 Task의 알림이 남지 않는다.
- 권한 거절이 저장 실패나 앱 크래시로 이어지지 않는다.
- Mac과 iPhone에서 `reminderAt`이 같은 값으로 수렴한다.
- 기존 백업과 신규 백업을 모두 읽을 수 있다.
- 전체 테스트, 양 플랫폼 빌드와 iPhone 실기기 검증을 통과한다.
