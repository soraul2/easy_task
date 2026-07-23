# PlanBase 에이전트 가이드

이 문서는 저장소에 처음 들어온 Codex 에이전트가 구조와 변경 경계를 빠르게 파악하기 위한 작업 지도다. 상세한 설계 배경과 운영 절차는 문서 마지막의 `docs/` 링크를 따른다.

## 1. 한눈에 보는 프로젝트

PlanBase는 칸반, 캘린더, 기록, 메모를 제공하는 개인 생산성 앱이다. 하나의 저장소에서 macOS 앱, iPhone 앱, iPhone 캘린더 위젯을 관리하며 두 앱은 같은 SwiftData 모델과 CloudKit private database를 공유한다.

- 언어/도구: Swift 6, Swift tools 6.3, SwiftUI, SwiftData
- 최소 플랫폼: iOS 18, macOS 26
- 공통 패키지 제품: `PlanBaseCore`
- Xcode scheme: `PlanBase-iOS`, `PlanBase-macOS`
- 현재 영속 스키마: `EasyTaskSchemaV6`

의존 방향은 아래와 같다.

```text
shared/Core (EasyTaskCore: 실제 모델·서비스 구현)
                    │
                    ▼
shared/PlanBaseCore (PlanBaseCore: 공개 re-export 계층)
          ┌─────────┼──────────────┐
          ▼         ▼              ▼
desktop/App     mobile/App     mobile/Widget
 macOS 앱        iPhone 앱       위젯 확장
```

앱 타겟은 `shared/Core`를 직접 컴파일하지 않고 로컬 Swift Package의 `PlanBaseCore` 제품을 링크한다. `EasyTaskCore`라는 이름은 배포된 SwiftData 모델의 모듈 정체성을 유지하기 위한 호환 이름이므로 임의로 바꾸지 않는다.

## 2. 반드시 지킬 경계

### 파일 접근 제한

다음 iCloud Drive 경로는 읽기, 목록 조회, 검색, 생성, 수정, 이동, 삭제를 모두 금지한다.

```text
/Users/home/Library/Mobile Documents
/Users/home/Library/Mobile Documents/com~apple~CloudDocs
```

파일이 위 경로에 있으면 사용자가 iCloud Drive 밖으로 복사하거나 이동할 때까지 접근하지 않는다. 광범위한 파일 검색으로 해당 경로를 순회해서도 안 된다.

### 배포 호환성

아래 식별자는 기존 설치 앱, CloudKit 데이터, 위젯, 백업과 연결되어 있으므로 리브랜딩 목적으로 변경하지 않는다.

- 앱 bundle ID: `com.soraul2.easytask`
- CloudKit container: `iCloud.com.soraul2.easytask`
- App Group: `group.com.soraul2.easytask`
- 백업 UTI/확장자: `com.soraul2.easytask.backup-package`, `.easytaskbackup`
- SwiftData 호환 이름: `EasyTaskSchemaV1`~`V6`, `EasyTaskMigrationPlan`
- 레거시 저장소, 이미지 폴더, migration marker 이름

호환 상수의 기준 파일은 `shared/Core/Persistence/PlanBaseCompatibility.swift`다. macOS Debug bundle ID `com.soraul2.easytask.macos`는 Release 앱과 개발 데이터를 병행하기 위한 의도된 예외다.

### 데이터 안전

- 배포된 기존 버전 스키마를 직접 고치지 않는다. 모델 변경은 새 `VersionedSchema`와 migration stage를 추가하는 방식으로 설계한다.
- 저장 작업은 가능한 한 `PersistenceCommandService.perform` 경계를 사용해 성공 시 save, 실패 시 rollback이 되게 한다.
- `id`는 논리 레코드 ID, `instanceID`는 물리 레코드 ID다. 중복 수렴과 `supersededAt` 규칙을 우회하지 않는다.
- CloudKit 동기화 중에는 중복이 일시적으로 생길 수 있으므로 단순 unique 가정이나 즉시 삭제를 추가하지 않는다.
- 테스트와 진단 도구는 기본적으로 로컬 또는 메모리 저장소를 사용한다. 실제 CloudKit 접근은 명시적인 진단 절차에서만 수행한다.
- `.local/backups/`는 Git에 포함되지 않는 안전 백업 영역이다. 명시적 요청 없이 정리하거나 덮어쓰지 않는다.

## 3. 디렉터리 지도

```text
PlanBase/
├── AGENTS.md                         # 현재 문서: 에이전트용 빠른 작업 지도
├── README.md                         # 프로젝트 소개와 최소 실행법
├── Package.swift                     # EasyTaskCore/PlanBaseCore/테스트 정의
├── PlanBase.xcodeproj/               # 앱·위젯·UI 테스트 타겟 및 shared scheme
├── shared/
│   ├── Core/
│   │   ├── Models/                   # 비영속 값 타입·공통 모델 보조 코드
│   │   ├── Persistence/              # SwiftData 버전 스키마, migration, container
│   │   ├── Services/                 # 도메인 규칙, 조회, 저장, 백업, 동기화
│   │   ├── Components/               # 양 플랫폼에서 재사용하는 SwiftUI 조각
│   │   └── Theme/                    # 색상·테마 토큰
│   ├── PlanBaseCore/Exports.swift    # EasyTaskCore 재노출과 공개 typealias
│   ├── Resources/                    # 앱 에셋과 macOS container migration plist
│   └── Tests/                        # Swift Package 단위·통합 테스트
├── desktop/
│   ├── App/PlanBaseDesktopApp.swift  # macOS @main, container 개방·복구
│   ├── App/Views/                    # macOS 탭과 기능별 화면
│   ├── App/Services/                 # macOS 파일 패널·이미지/백업 어댑터
│   └── Configuration/                # Info.plist, entitlements, export options
├── mobile/
│   ├── App/PlanBaseMobileApp.swift   # iOS @main, container 개방·복구, 탭 루트
│   ├── App/                          # iPhone 기능 화면과 플랫폼 어댑터
│   ├── Widget/                       # WidgetKit 캘린더 위젯 타겟
│   ├── Tests/                        # iPhone launch UI test
│   └── Configuration/                # iOS/Widget plist, entitlements, export options
├── docs/                             # 상세 아키텍처·동기화·계획 문서
├── scripts/                          # 전체 빌드 검증과 실기기 CloudKit probe
└── .local/backups/                   # 추적하지 않는 로컬 데이터 안전 백업
```

## 4. 빌드 그래프와 진입점

### Swift Package

`Package.swift`에는 세 타겟이 있다.

| 타겟 | 경로 | 역할 |
|---|---|---|
| `EasyTaskCore` | `shared/Core` | 실제 공통 모델, persistence, 서비스, 테마 구현 |
| `PlanBaseCore` | `shared/PlanBaseCore` | `EasyTaskCore`를 re-export하는 앱용 공개 제품 |
| `PlanBaseCoreTests` | `shared/Tests` | 공통 로직 및 데이터 안전성 테스트 |

`shared/PlanBaseCore/Exports.swift`는 현재 V5 모델을 앱 친화적 이름으로 typealias하고 V6에서 추가된 `Memo`를 함께 노출한다. 따라서 앱 코드는 `import PlanBaseCore` 후 `Task`, `CalendarEvent`, `Memo`처럼 사용한다.

### Xcode 타겟

| 타겟/scheme | 진입점 | 주요 책임 |
|---|---|---|
| `PlanBase-macOS` | `desktop/App/PlanBaseDesktopApp.swift` | macOS 앱, AppKit 연동, 백업 파일 UI |
| `PlanBase-iOS` | `mobile/App/PlanBaseMobileApp.swift` | iPhone 앱, 알림, deep link, 위젯 snapshot 발행 |
| `PlanBaseWidgetExtension` | `mobile/Widget/PlanBaseCalendarWidget.swift` | App Group JSON을 읽는 WidgetKit 확장 |
| `PlanBaseLaunchUITests` | `mobile/Tests/PlanBaseLaunchUITests.swift` | iPhone launch smoke test |

앱 소스 파일은 `PlanBase.xcodeproj/project.pbxproj`에 명시적으로 등록되어 있다. `desktop/App` 또는 `mobile/App`에 새 파일을 만들면 해당 앱 타겟 membership도 추가해야 한다. 반면 SwiftPM 타겟 경로 아래의 새 Swift 파일은 패키지에서 자동으로 발견된다.

## 5. 앱 시작과 데이터 흐름

두 앱의 기본 시작 흐름은 동일하다.

```text
@main App
  → PlanBaseContainerFactory.makeAppPersistent()
  → 실패 시 데이터 복구/재시도 화면
  → 준비된 ModelContainer를 SwiftUI 환경에 주입
  → 루트 화면 start()
      1. DataIntegrityService.reconcile
      2. 레거시 회고 이미지 이관
      3. 로컬 demo 정책일 때만 seed
      4. 지난 완료 작업 lazy archive
      5. CloudKit 이벤트 관찰 및 import 후 재수렴
```

`PlanBaseContainerFactory`는 런타임 entitlement가 유효하면 private CloudKit 저장소를, 그렇지 않으면 안전하게 로컬 저장소를 연다. 위젯은 SwiftData/CloudKit을 직접 열지 않는다. iOS 앱이 `CalendarWidgetSnapshotPublisher`를 통해 App Group에 JSON snapshot을 쓰고 위젯은 그것만 읽는다.

## 6. 데이터 모델과 핵심 규칙

현재 `EasyTaskSchemaV6`는 V5 모델 전체에 `Memo`를 추가한 스키마다.

| 모델 | 역할/주요 연결 |
|---|---|
| `Task` | 날짜별 칸반 작업, 이벤트·템플릿 배치·알림의 기준 레코드 |
| `TaskChecklistItem` | `taskId`로 Task에 연결되는 체크리스트 항목 |
| `CalendarEvent` | 시작/종료 날짜를 가진 캘린더 기간 이벤트 |
| `TaskTemplate`, `TaskTemplateItem` | 재사용 작업 묶음과 항목 정의 |
| `TemplatePlacement` | 특정 날짜에 적용한 템플릿 인스턴스 |
| `DailyReview` | `dayKey`당 회고 |
| `DiaryBlock` | 레거시 회고 블록 호환 모델 |
| `DiaryAttachment` | `reviewId`로 연결된 external-storage 이미지 데이터 |
| `Memo` | 날짜/Task와 독립된 자동 저장 메모 |

중요한 규칙은 다음과 같다.

- 날짜 비교와 저장 키 생성은 `DayKey`를 사용한다. 임의 formatter로 `yyyy-MM-dd` 로직을 중복 구현하지 않는다.
- 완료 작업은 당일 보드에는 남고 이후 lazy archive 대상이 된다. 이월/완료 날짜 규칙은 `TaskRules`에 둔다.
- 체크리스트 전체 완료가 상위 Task 상태를 자동 완료시키지는 않는다.
- `Task.reminderAt`이 알림 원본이며 iOS pending notification은 재생성 가능한 캐시다.
- 기록, 보드, 캘린더, 메모는 전체 테이블을 계속 관찰하지 않고 bounded query/session을 사용한다.
- 첨부 이미지는 MIME, 크기, 실제 decode, SHA-256 검증을 거친다. 목록에서는 원본을 바로 decode하지 않는다.
- 백업 package 병합은 파괴적 교체가 아니라 동일한 무결성 규칙으로 수렴하는 병합이다.

## 7. 기능별 수정 위치

| 기능 | 공통 코어 | macOS UI/어댑터 | iPhone UI/어댑터 |
|---|---|---|---|
| 보드·작업 | `TaskRules`, `BoardQueryRules`, `BoundedQueryService`, `PersistenceCommandService` | `BoardView`, `DesktopKanbanComponents`, `DesktopBoardSheets`, `DesktopTaskDetailSheet` | `MobileBoardView`, `MobileBoardComponents`, `MobileTaskDetailSheet`, `MobileCarryoverSheet` |
| 체크리스트 | `TaskChecklistService` | `DesktopTaskDetailSheet`, 진행 카드 UI | `MobileTaskDetailSheet`, `MobileBoardComponents` |
| 템플릿 | `TemplateService`, `TemplateListRules`, 공용 `Template*` components | `DesktopTemplatePlacementSheet`, 보드 sheet | `MobileTemplateLibrarySheet`, `MobileTemplatePlacementSheet`, `MobileTemplateComponents` |
| 캘린더 | `CalendarEventRules`, `CalendarEventTimeline`, `DayKey` | `CalendarView`, `DesktopCalendarGrid`, `DesktopEventEditorSheets` | `MobileCalendarView`, `MobileCalendarGrid`, `MobileCalendarDaySheet`, `MobileEventEditorSheet` |
| 기록·회고 | `ArchiveQueryRules`, `ArchiveQuerySession`, `DailyReview*`, `DiaryAttachmentService` | `ArchiveView`, `DiaryView`, `DiaryImageStore` | `MobileArchiveView`, `MobileArchiveRecordCard`, `MobileReviewComposer*` |
| 메모 | `MemoRules`, `MemoService`, `MemoQuerySession`, `MemoEditorSession` | `MemoView` | `MobileMemoView` |
| 백업 | `BackupCodec`, `BackupPackageCodec`, `BackupPackageMerge`, `DataIntegrityService` | `BackupService`와 파일 패널 | 현재 별도 파일 UI 없음 |
| CloudKit | `PlanBaseContainerFactory`, `CloudKitSyncService`, `CloudKitConvergenceProbe*` | 앱 루트 sync UI/diagnostic args | 앱 루트 sync UI/diagnostic args |
| 작업 알림 | `TaskReminderRules` | 로컬 알림 스케줄러 없음 | `TaskNotificationScheduler`, app delegate/route store |
| 위젯 | `CalendarWidgetSnapshot`, `PlanBaseDeepLink` | 해당 없음 | `CalendarWidgetSnapshotPublisher`, `PlanBaseCalendarWidget` |
| 테마 | `AppTheme`, `CalendarEventPalette` | 앱 루트 theme selector | 앱 루트/mobile theme UI 및 위젯 snapshot |

새 비즈니스 규칙은 가능한 한 `shared/Core/Services`에 두고 단위 테스트한다. 플랫폼 디렉터리에는 화면 상태, SwiftUI composition, AppKit/UIKit/WidgetKit 같은 플랫폼 어댑터만 둔다.

## 8. 변경 유형별 체크리스트

### 모델/필드 변경

1. 기존 스키마를 수정하지 말고 다음 `EasyTaskSchemaV*`를 추가한다.
2. `EasyTaskMigrationPlan`의 schema 목록과 stage를 갱신한다.
3. `PlanBaseContainerFactory.schema`와 `Exports.swift`의 공개 alias를 확인한다.
4. `DataIntegrityService`, 백업 DTO/codec/merge, CloudKit probe에 영향이 있는지 확인한다.
5. `SchemaMigrationTests`, `DataSafetyTests`, `DataIntegrityTests`, 백업 테스트를 추가한다.
6. CloudKit Development schema 검증 및 Production 배포 절차는 `docs/CLOUDKIT_SYNC.md`를 따른다.

### 공통 기능 변경

1. 순수 계산은 `*Rules`, 저장/조회 orchestration은 `*Service` 또는 `*Session`에 둔다.
2. 저장 실패 rollback과 `PersistenceCommandService.dataChangedNotification` 흐름을 유지한다.
3. 전체 fetch 대신 기존 bounded descriptor/session을 확장할 수 있는지 먼저 본다.
4. 공통 테스트를 추가한 뒤 양 플랫폼 호출부를 연결한다.

### 플랫폼 UI 변경

1. 동일 기능의 공통 규칙을 UI 파일에 복제하지 않는다.
2. macOS와 iPhone이 같은 모델 의미를 유지하는지 반대 플랫폼도 확인한다.
3. 새 소스 파일을 Xcode target에 등록한다.
4. 캘린더 이벤트나 테마 변경이면 iOS 위젯 snapshot 갱신 경로도 확인한다.
5. Task 알림 원본을 바꾸면 iOS reconciliation 경로를 확인한다.

## 9. 검증 명령

빠른 공통 로직 검증:

```bash
swift test
```

공통 패키지의 Release 검증까지 포함:

```bash
swift test -c release
```

양 플랫폼 Debug/Release simulator build와 패키지 테스트를 모두 실행하는 전체 회귀 게이트:

```bash
./scripts/verify-platform-builds.sh
```

이 스크립트는 `git diff --check`, Debug/Release `swift test`, iOS/macOS Debug/Release build를 수행한다. 서명된 실기기와 CloudKit 계정이 필요한 수렴 검증은 일반 테스트가 아니며 `docs/CLOUDKIT_SYNC.md`를 읽은 후에만 다음 스크립트를 사용한다.

```bash
PLANBASE_DEVICE_ID=<devicectl-id> \
PLANBASE_XCODE_DEVICE_ID=<xcode-udid> \
./scripts/run-cloudkit-convergence.sh
```

작업 범위에 비례해 최소 관련 테스트를 먼저 돌리고, schema/persistence/공통 API/Xcode 설정을 건드렸다면 전체 회귀 게이트까지 실행한다.

## 10. 상세 문서 안내

- [`README.md`](README.md): 프로젝트 요약, 시작법, 기본 검증
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): 런타임, 데이터 무결성, 백업, 이미지, 플랫폼 경계의 상세 설명
- [`docs/DATA_FOUNDATION_PLAN.md`](docs/DATA_FOUNDATION_PLAN.md): 데이터 안전 작업 순서와 Git 운영 규칙
- [`docs/CLOUDKIT_SYNC.md`](docs/CLOUDKIT_SYNC.md): entitlement, schema 배포, 실기기 수렴 검증
- [`docs/TASK_REMINDER_PLAN.md`](docs/TASK_REMINDER_PLAN.md): Task 1회성 알림 설계와 수명주기
- [`docs/TASK_REMINDER_COMPLETION_RETENTION_PLAN.md`](docs/TASK_REMINDER_COMPLETION_RETENTION_PLAN.md): 완료 전환 경고와 알림 기록 보존 정책
- [`docs/REFACTORING_PLAN.md`](docs/REFACTORING_PLAN.md): 구조 개선 이력과 후속 계획

## 11. 에이전트 시작 순서

작업을 시작할 때는 아래 순서면 충분하다.

1. `git status --short`로 사용자 변경을 확인하고 덮어쓰지 않는다.
2. 이 문서와 작업에 직접 관련된 `docs/` 문서만 읽는다.
3. 위 기능 표로 공통 코어와 양 플랫폼 영향 범위를 찾는다.
4. 기존 `Rules`/`Service`/`Session` 패턴과 인접 테스트를 먼저 확인한다.
5. 작은 변경 단위로 구현하고 관련 테스트를 실행한다.
6. 모델, 호환 식별자, 백업, CloudKit 영향이 있다면 데이터 안전 체크리스트를 다시 검토한다.
