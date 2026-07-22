# EasyTask Architecture

## 개요

EasyTask는 macOS 데스크톱 MVP와 iPhone MVP를 하나의 저장소에서 관리한다. 두 앱은 같은 SwiftData 모델과 순수 서비스 로직을 공유하고, 화면 구현만 플랫폼별로 분리한다.

## 구조

```text
EasyTask.xcodeproj          # iPhone/macOS 앱 번들 타겟과 공유 scheme
Package.swift               # SwiftPM 기반 공통 코어/테스트 구성
Sources/
  EasyTaskCore/             # 공통 모델, 서비스, 테마, 리소스
  TodoDesktopMVP/           # macOS 앱 구현
  EasyTaskiOS/              # iPhone 앱 구현
  EasyTaskWidget/           # iPhone 홈 화면 캘린더 위젯
Tests/
  TodoDesktopMVPTests/      # 공통 로직 테스트
```

## 공통 코어

`EasyTaskCore`는 플랫폼 UI에 의존하지 않는 영역이다.

- SwiftData 모델: `Task`, `TaskChecklistItem`, `CalendarEvent`, `TaskTemplate`, `DailyReview`, `DiaryBlock`, `DiaryAttachment`, `Memo`
- 저장소 구성: 동결된 `EasyTaskSchemaV1`~`V5`, 현재 `EasyTaskSchemaV6`, `EasyTaskMigrationPlan`, `EasyTaskContainerFactory`
- 데이터 무결성: `DataIntegrityService`
- 저장 명령 경계: `PersistenceCommandService`의 명시적 save/rollback
- 동기화 상태: `CloudKitSyncMonitor`, 이벤트별 진행·오류 추적
- 날짜/보드 규칙: `DayKey`, `TaskRules`
- 제한 조회: `BoundedQueryService`, 날짜 범위 descriptor와 action-time 관계 fetch
- 기록 조회: `ArchiveQueryRules`, `ArchiveFilter`, `ArchiveQuerySession`
- 메모: `MemoRules`, `MemoService`, `MemoQuerySession`, `MemoEditorSession`
- 템플릿 규칙: `TemplateService`, `TemplateListRules`
- 캘린더 이벤트 계산: `CalendarEventTimeline`
- 캘린더 위젯 계약: `CalendarWidgetSnapshot`, `CalendarWidgetSnapshotStore`, `EasyTaskDeepLink`
- 백업: JSON V1 호환 `BackupCodec`, 이미지·Task 알림·체크리스트·메모를 포함하는 V5 `BackupPackageCodec`(V2~V5 읽기 호환)
- 회고 첨부: `DiaryAttachmentService`, 레거시 입력용 `DiaryImageFileStore`
- 한국 특일 JSON: `SpecialDays.kr.json`
- 테마 토큰: `AppTheme`, `CalendarEventPalette`

## 플랫폼 경계

macOS 앱은 `TodoDesktopMVP`에 둔다.

- 데스크톱 칸반 보드, 캘린더, 기록, 목록·편집기 분할형 메모 UI
- AppKit 기반 파일 패널 wrapper
- 데스크톱 전용 드래그/호버 UX
- Xcode `EasyTask-macOS` 타겟에서 `EasyTaskCore` 패키지 제품에 의존한다.

iPhone 앱은 `EasyTaskiOS`에 둔다.

- `MobileBoardView`: segmented 상태 전환 기반 칸반
- `MobileCalendarView`: 월간 캘린더와 이벤트/템플릿 sheet
- `MobileArchiveView`: 회고와 완료 작업 피드
- `MobileMemoView`: 검색·고정 목록과 자동 저장 편집기
- `MobileReviewComposerSheet`: 이미지 첨부 가능한 회고 작성
- `CalendarWidgetSnapshotPublisher`: 캘린더 변경을 App Group 스냅샷으로 발행
- Xcode `EasyTask` 타겟과 `EasyTask-iOS` 공유 scheme을 사용한다.

iPhone 홈 화면 위젯은 `EasyTaskWidget`에 둔다.

- 소형은 오늘 이벤트, 중형은 월간 42일 그리드와 이벤트 표시점, 대형은 날짜별 이벤트 제목을 제공한다.
- 위젯은 SwiftData나 CloudKit을 직접 열지 않고 `group.com.soraul2.easytask`의 JSON 스냅샷만 읽는다.
- 스냅샷에는 선택 테마 ID를 포함하며 위젯은 시스템 Light/Dark 환경에 맞는 동일 테마 팔레트를 사용한다.
- 날짜 탭은 `easytask://calendar?date=yyyy-MM-dd`로 앱의 해당 날짜 캘린더를 연다.
- Xcode `EasyTaskWidgetExtension` 타겟에서 `EasyTaskCore` 패키지 제품에 의존하고 `EasyTask.app`에 내장된다.

두 앱 타겟은 공통 코어 소스를 직접 컴파일하지 않고 로컬 Swift Package의
`EasyTaskCore` 제품을 링크한다.

## 데이터 흐름

1. 두 앱은 `EasyTaskContainerFactory`에서 같은 V6 스키마와 private CloudKit 설정을 사용하는 컨테이너를 생성한다.
2. 저장소는 V1 → V2 → V3 → V4 → V5 → V6 순서로 이동하며 이미 배포된 V1~V5 정의는 수정하지 않는다.
   TemplatePlacement 도입 전의 초기 macOS 저장소는 별도 레거시 브리지를 거친다.
3. 앱 시작 시 무결성 정리를 하나의 저장 명령으로 실행하고, 레거시 이미지 이관 뒤 seed와 lazy archive 규칙을 실행한다.
4. 사용자는 칸반에서 날짜별 작업을 추가하고 상태를 변경한다.
5. 완료된 작업은 당일에는 보드에 남고, 이후 조회 시 보관 흐름으로 이동한다.
   이월함의 `오늘로`는 배치일을 오늘로 옮기고 상태를 할 일로 되돌린다.
   `원래 날짜에 모두 완료`는 배치일을 바꾸지 않고 각 작업의 `plannedDayKey`를
   `completedDayKey`로 사용하며, `completedAt`에는 실제 처리 시각을 기록한다.
6. 캘린더 이벤트는 기간 이벤트로 보이며, 작업 세부 계획은 보드에서 조정한다.
7. 회고는 날짜별 `DailyReview`로 저장되고 기록 탭에서 완료 작업과 함께 검색된다.
8. 새 회고 이미지는 `DiaryAttachment.data`에 external storage로 저장되고 파일명 필드는 이관 입력으로만 사용한다.
9. 메모는 날짜·Task·회고와 독립적으로 저장하며 600ms 자동 저장과 상단 고정을 제공한다.
10. 백업 V5는 `manifest.json`, `records.json`, `attachments/`로 구성된 `.easytaskbackup` 패키지이며 V2~V5를 읽는다.
11. `Task.reminderAt`이 알림 원본이고 iPhone의 pending notification은 재생성 가능한 로컬 캐시다.
12. 보드와 캘린더는 선택 날짜 또는 42일 월 그리드 범위만 live query하고, 기록은 완전한 날짜 그룹 30개, 메모는 40개씩 조회한다.
13. iPhone 앱은 이벤트 변경·앱 활성화 때 App Group 위젯 스냅샷을 갱신하고, 내용이 달라졌을 때만 WidgetKit 타임라인을 다시 요청한다.

## 저장과 동기화 런타임

- 컨테이너 개방 실패는 앱을 종료하지 않고 원인과 재시도 버튼이 있는 복구 화면으로 표시한다.
- 주요 생성·수정·이동·삭제는 `PersistenceCommandService`를 거쳐 저장하며 실패 시 해당 명령을 rollback한다.
- CloudKit setup/import/export 이벤트는 식별자별로 추적한다. 동시에 실행 중인 이벤트가 있으면 동기화 중 상태를 유지하고, 다른 이벤트의 성공이 기존 실패를 숨기지 않는다.
- 성공한 import 뒤 무결성 정리를 같은 저장 명령 안에서 실행한다. 정리나 저장이 실패하면 변경을 남기지 않는다.
- 앱 활성화, 자정, 시스템 시간대 변경 때 오늘 키를 갱신한다. 사용자가 오늘 보드를 보고 있었다면 새 오늘을 따라가고, 과거·미래 날짜를 보고 있었다면 날짜 키를 보존해 새 시간대에서 다시 구성한다.
- 동기화 상태 화면은 iCloud 계정 상태, 진행 여부, 최근 성공 시각, 동기화 오류와 데이터 정리 오류를 구분해 표시한다.
- 앱 루트는 전체 모델을 상시 구독하지 않는다. 데모 seed는 로컬 demo 정책에서만 일회성 fetch하고 lazy archive는 미보관 완료 후보만 조회한다.
- 성공한 저장 명령은 데이터 변경 알림을 게시하며, 기록 세션은 이미 불러온 페이지 깊이를 보존해 다시 조회한다.

## 무결성 규칙

- `id`는 기기 간에 유지되는 논리 ID이고 `instanceID`는 물리 레코드를 구분한다.
- 같은 논리 ID나 자연 키가 중복되면 가장 큰 `(updatedAt, instanceID)` 후보 자체가 대표 레코드가 된다.
- 이전 후보의 스칼라는 덮어쓰지 않고 `supersededAt`만 표시해 각 `instanceID`의 원본을 보존한다.
- 날짜별 회고는 `dayKey`, 기본 템플릿과 항목은 `seedKey`를 자연 키로 병합한다.
- 중복 레코드는 즉시 삭제하지 않고 참조를 대표 레코드로 옮긴 뒤 `supersededAt`으로 표시한다.
- 상태, 우선순위, 이벤트 색상, 날짜 키와 UUID 참조는 앱 시작과 백업 직전에 정리한다.
- 템플릿 배치 소속의 원본은 `Task.templatePlacementId`이며, 백업의 `taskIds`는 내보낼 때 계산하는 호환 값이다.
- 체크리스트는 `TaskChecklistItem.taskId`로 Task에 연결한다. 날짜 이동, 이월, 완료·재개는 연결과 항목 완료 상태를 유지하고 Task 삭제만 연결 항목을 함께 삭제한다.
- 모든 체크리스트 항목이 완료돼도 상위 Task 상태는 자동 변경하지 않는다. 빈 제목과 부모 없는 항목은 supersede하고 활성 항목 순서는 100 단위로 다시 계산한다.
- `진행 중` 카드에서는 체크리스트를 펼쳐 완료 상태만 바로 바꿀 수 있다. 항목 추가·수정·삭제·정렬은 작업 상세에서만 처리하고 iOS는 한 번에 한 카드만 펼친다.
- 템플릿은 체크리스트 제목과 순서만 저장하며 적용 시 모든 항목을 미완료로 생성한다.
- 메모 중복은 같은 `id` 내에서 가장 최신 `updatedAt`을 우선하고 `instanceID`로 결정적으로 수렴한다.
- 첨부는 `reviewId`로 대표 회고에 재연결하며 MIME, 크기, SHA-256을 원본 데이터에서 다시 계산한다.
- 활성 첨부는 회고당 최대 10개이며, 백업 병합은 무결성 정리 후의 최종 개수를 저장 전에 다시 검증한다.
- 백업 병합은 `(id, instanceID)` 후보를 보존하고 최종 저장 전에 같은 무결성 규칙으로 수렴시킨다.

## 이미지와 백업

- PNG, JPEG, HEIC만 허용하며 20MB 이하인지와 ImageIO 실제 디코딩 가능 여부를 저장 전에 확인한다.
- 목록과 작성 화면의 미리보기는 원본을 직접 디코딩하지 않는다. iOS는 최대 1,280px, macOS는 최대 1,600px로 백그라운드 다운샘플하고 제한된 메모리 캐시와 진행 중 요청 병합을 사용한다.
- 기록 화면은 회고별 첨부·레거시 블록 인덱스를 한 번 구성해 카드마다 전체 배열을 반복 검색하지 않는다.
- 새 이미지 추가·삭제는 회고 본문과 한 번의 SwiftData 저장으로 확정되어 별도 고아 파일을 만들지 않는다.
- V2의 `imageFileNames`와 이미지 `DiaryBlock`은 V3 개방 후 앱 지원 폴더에서 점진적으로 옮긴다.
- 누락되거나 손상된 기존 파일은 참조를 지우지 않고 다음 실행에서 재시도하며, 모두 옮긴 회고만 레거시 참조를 정리한다.
- 기존 이미지가 10개를 넘으면 처음 10개까지만 옮기고 초과 참조는 보존한다. 배열과 block-only 참조를 함께 표시하며 미해결 레거시 항목은 삭제해 백업 차단을 해소할 수 있다.
- 미해결 레거시 항목이 남은 동안 canonical 이미지 추가·삭제는 잠그고, 마지막 항목을 정리해 저장할 때 기존 메타데이터와 이미지 블록을 제거한다.
- 백업 V5는 records와 각 첨부의 크기·SHA-256, MIME, Task/체크리스트 참조, 메모 식별자 무결성을 전부 확인한 뒤 비파괴 병합한다.
- 회고가 대표 ID로 재연결된 첨부는 병합 전 공통 부분집합과 병합 후 전체 incoming 부분집합의 상대 순서가 일치해야 한다.
- 다만 로컬 첨부가 백업 후보보다 최신이면 해당 후보는 과거 순서 검증에서 제외해 최신 로컬 정렬을 보존한다.
- `.easytaskbackup`은 `public.package` 계열의 고정 UTI로 등록해 Finder와 파일 패널에서 하나의 패키지로 다룬다.
- JSON V1은 계속 읽지만 이미지 바이트를 포함하지 않으므로 누락 파일을 보고하고 결정적 `instanceID`로 병합한다.

## 초기 macOS 저장소 브리지

- `EasyTaskContainerFactory.makeAppPersistent`는 앱 저장소를 열기 전에 초기 macOS 스키마인지 검사한다.
- 해당하는 경우 SQLite 원본과 WAL/SHM, 검증된 JSON 스냅샷을 `EasyTaskLegacyBackups`에 먼저 보존한다.
- 원본 백업이 끝난 뒤 현재 스키마 저장소를 만들고 기존 레코드를 비파괴 병합한다.
- 병합이 끝나기 전에는 pending marker를 유지한다. 중단되면 다음 실행에서 불완전한 현재 저장소만 버리고 보존된 스냅샷으로 재시도한다.
- 성공 후에도 원본 백업은 자동 삭제하지 않는다. 테스트용 `makePersistent`는 이 앱 시작 전용 브리지를 실행하지 않는다.

## macOS 배포 경계

- macOS Debug 빌드는 기존 개발 데이터와 병행 실행을 위해 `com.soraul2.easytask.macos`와 비샌드박스 설정을 유지한다.
- Mac App Store/TestFlight용 Release 빌드는 iPhone과 같은 `com.soraul2.easytask`를 사용하며 App Sandbox, CloudKit, 사용자 선택 파일 읽기·쓰기를 활성화한다.
- 첫 샌드박스 실행 때 `container-migration.plist`가 기존 `Application Support`의 SwiftData 저장소, 브리지 백업과 회고 이미지 폴더를 동일한 상대 경로로 컨테이너에 옮긴다.
- Release 앱 이름은 `PlanBase`이고 최소 지원 버전은 macOS 26.0이다. 배포 프로파일과 export 설정은 `PlanBase macOS App Store`를 기준으로 한다.

## 현재 MVP 범위

- V6 버전 스키마를 사용하며 앱 타겟은 private CloudKit 저장소를 사용한다.
- 공통 컨테이너는 `iCloud.com.soraul2.easytask`이며 iOS와 macOS가 같은 컨테이너를 명시적으로 선택한다.
- 테스트, 파일 마이그레이션, 복구 도구는 기본 로컬 저장 모드를 유지해 CloudKit에 접근하지 않는다.
- CloudKit import가 성공적으로 끝나면 공통 무결성 정리를 실행하고, 동기화 모드에서는 Debug 샘플 데이터를 만들지 않는다.
- CloudKit Production에는 V6 스키마가 배포되어 있으며 TestFlight 앱은 운영 private database를 사용한다.
- macOS와 iOS는 같은 모델 스키마를 공유한다.
- iOS는 iPhone 우선이며 drag/drop은 제외하고 버튼/segmented control 중심으로 처리한다.
- 양 플랫폼 작업 상세는 제목, 보드 날짜, 상태, 메모, 우선순위, 예상 시간, 태그와 선택형 체크리스트를 편집한다.
- iOS는 현재 보드에서 작업을 편집·제외해 템플릿으로 저장하고 검색, 즐겨찾기, 적용, 삭제할 수 있다.
- 기본 내보내기는 이미지 원본, Task 알림·체크리스트·메모를 포함한 백업 V5이며 패키지 V2~V4와 JSON V1은 가져오기 호환 경로로 유지한다.
- Board는 선택일·이월·겹침 이벤트 쿼리를 분리하고 다음 순서를 데이터베이스 최대값으로 계산한다.
- Calendar는 표시 월의 42일 범위 이벤트·배치만 관찰하며 관계 삭제는 이벤트/배치 ID로 필요한 작업만 조회한다.
- 기록 검색은 300ms debounce를 적용하고 행 수가 아닌 완전한 날짜 30개 단위로 페이지를 추가한다.
- 메모 검색은 기록과 분리하고 제목·본문 전체를 대상으로 40개씩 조회한다. 편집은 600ms debounce로 저장하며 화면 이탈·백그라운드 전환 시 즉시 flush한다.
- 회고 작성은 선택 날짜의 회고와 선택 회고 ID의 블록·첨부만 조회한다.
- iOS 홈 화면 캘린더 위젯은 소형·중형·대형을 지원하며 스냅샷에는 현재 월 기준 이전 1개월부터 이후 3개월까지 최대 256개의 활성 이벤트와 선택 테마 ID만 포함한다.

## 다음 단계

2026-07-12 기준으로 동일 개발 컨테이너의 macOS ↔ iPhone 양방향 create/delete 전파는
고유 진단 레코드로 통과했다. 다음 우선순위는 같은 레코드의 오프라인 동시 편집,
이미지 추가·삭제·재설치, iCloud 로그아웃·재로그인, 자동 복구 백업과 UI smoke test다.
이 조건과 Debug/Release 서명 검증은 이후 스키마 변경과 배포의 회귀 게이트로 유지한다.

데이터 스키마, 백업, 이미지, CloudKit 동기화 작업의 순서와 Git 운영 규칙은
[`DATA_FOUNDATION_PLAN.md`](DATA_FOUNDATION_PLAN.md)를 따른다.
개발 컨테이너 발급과 검증 절차는 [`CLOUDKIT_SYNC.md`](CLOUDKIT_SYNC.md)를 따른다.
Task 1회성 알림의 V4 스키마, iOS 예약 수명주기와 검증 순서는
[`TASK_REMINDER_PLAN.md`](TASK_REMINDER_PLAN.md)를 따른다.
