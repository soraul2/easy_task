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
Tests/
  TodoDesktopMVPTests/      # 공통 로직 테스트
```

## 공통 코어

`EasyTaskCore`는 플랫폼 UI에 의존하지 않는 영역이다.

- SwiftData 모델: `Task`, `CalendarEvent`, `TaskTemplate`, `DailyReview`, `DiaryBlock`, `DiaryAttachment`
- 저장소 구성: `EasyTaskSchemaV1`, `EasyTaskSchemaV2`, `EasyTaskSchemaV3`, `EasyTaskMigrationPlan`, `EasyTaskContainerFactory`
- 데이터 무결성: `DataIntegrityService`
- 저장 명령 경계: `PersistenceCommandService`의 명시적 save/rollback
- 동기화 상태: `CloudKitSyncMonitor`, 이벤트별 진행·오류 추적
- 날짜/보드 규칙: `DayKey`, `TaskRules`
- 제한 조회: `BoundedQueryService`, 날짜 범위 descriptor와 action-time 관계 fetch
- 기록 조회: `ArchiveQueryRules`, `ArchiveFilter`, `ArchiveQuerySession`
- 템플릿 규칙: `TemplateService`, `TemplateListRules`
- 캘린더 이벤트 계산: `CalendarEventTimeline`
- 백업: JSON V1 호환 `BackupCodec`, 이미지 포함 V2 `BackupPackageCodec`
- 회고 첨부: `DiaryAttachmentService`, 레거시 입력용 `DiaryImageFileStore`
- 한국 특일 JSON: `SpecialDays.kr.json`
- 테마 토큰: `AppTheme`, `CalendarEventPalette`

## 플랫폼 경계

macOS 앱은 `TodoDesktopMVP`에 둔다.

- 데스크톱 칸반 보드, 캘린더, 기록 UI
- AppKit 기반 파일 패널 wrapper
- 데스크톱 전용 드래그/호버 UX
- Xcode `EasyTask-macOS` 타겟에서 `EasyTaskCore` 패키지 제품에 의존한다.

iPhone 앱은 `EasyTaskiOS`에 둔다.

- `MobileBoardView`: segmented 상태 전환 기반 칸반
- `MobileCalendarView`: 월간 캘린더와 이벤트/템플릿 sheet
- `MobileArchiveView`: 회고와 완료 작업 피드
- `MobileReviewComposerSheet`: 이미지 첨부 가능한 회고 작성
- Xcode `EasyTask` 타겟과 `EasyTask-iOS` 공유 scheme을 사용한다.

두 앱 타겟은 공통 코어 소스를 직접 컴파일하지 않고 로컬 Swift Package의
`EasyTaskCore` 제품을 링크한다.

## 데이터 흐름

1. 두 앱은 `EasyTaskContainerFactory`에서 같은 V3 스키마와 private CloudKit 설정을 사용하는 컨테이너를 생성한다.
2. 저장소는 V1 → V2 → V3 순서로 이동하며 이미 배포된 V1/V2 정의는 수정하지 않는다.
   TemplatePlacement 도입 전의 초기 macOS 저장소는 별도 레거시 브리지를 거친다.
3. 앱 시작 시 무결성 정리를 하나의 저장 명령으로 실행하고, 레거시 이미지 이관 뒤 seed와 lazy archive 규칙을 실행한다.
4. 사용자는 칸반에서 날짜별 작업을 추가하고 상태를 변경한다.
5. 완료된 작업은 당일에는 보드에 남고, 이후 조회 시 보관 흐름으로 이동한다.
6. 캘린더 이벤트는 기간 이벤트로 보이며, 작업 세부 계획은 보드에서 조정한다.
7. 회고는 날짜별 `DailyReview`로 저장되고 기록 탭에서 완료 작업과 함께 검색된다.
8. 새 회고 이미지는 `DiaryAttachment.data`에 external storage로 저장되고 파일명 필드는 이관 입력으로만 사용한다.
9. 백업 V2는 `manifest.json`, `records.json`, `attachments/`로 구성된 `.easytaskbackup` 패키지다.
10. 보드와 캘린더는 선택 날짜 또는 42일 월 그리드 범위만 live query하고, 기록은 완전한 날짜 그룹 30개씩 조회한다.

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
- 백업 V2는 records와 각 첨부의 크기·SHA-256, MIME, 참조 무결성을 전부 확인한 뒤 비파괴 병합한다.
- 회고가 대표 ID로 재연결된 첨부는 병합 전 공통 부분집합과 병합 후 전체 incoming 부분집합의 상대 순서가 일치해야 한다.
- 다만 로컬 첨부가 백업 후보보다 최신이면 해당 후보는 과거 순서 검증에서 제외해 최신 로컬 정렬을 보존한다.
- `.easytaskbackup`은 `public.package` 계열의 고정 UTI로 등록해 Finder와 파일 패널에서 하나의 패키지로 다룬다.
- JSON V1은 계속 읽지만 이미지 바이트를 포함하지 않으므로 누락 파일을 보고하고 결정적 `instanceID`로 병합한다.

## 초기 macOS 저장소 브리지

- `EasyTaskContainerFactory.makeAppPersistent`는 앱 저장소를 열기 전에 초기 macOS 스키마인지 검사한다.
- 해당하는 경우 SQLite 원본과 WAL/SHM, 검증된 JSON 스냅샷을 `EasyTaskLegacyBackups`에 먼저 보존한다.
- 원본 백업이 끝난 뒤 새 V3 저장소를 만들고 기존 레코드를 비파괴 병합한다.
- 병합이 끝나기 전에는 pending marker를 유지한다. 중단되면 다음 실행에서 불완전한 V3 저장소만 버리고 보존된 스냅샷으로 재시도한다.
- 성공 후에도 원본 백업은 자동 삭제하지 않는다. 테스트용 `makePersistent`는 이 앱 시작 전용 브리지를 실행하지 않는다.

## 현재 MVP 범위

- V3 버전 스키마를 유지하며 앱 타겟은 private CloudKit 저장소를 사용한다.
- 공통 컨테이너는 `iCloud.com.soraul2.easytask`이며 iOS와 macOS가 같은 컨테이너를 명시적으로 선택한다.
- 테스트, 파일 마이그레이션, 복구 도구는 기본 로컬 저장 모드를 유지해 CloudKit에 접근하지 않는다.
- CloudKit import가 성공적으로 끝나면 공통 무결성 정리를 실행하고, 동기화 모드에서는 Debug 샘플 데이터를 만들지 않는다.
- 개발 스키마만 사용하며 운영 스키마 승격은 실기기 수렴 검증 전까지 금지한다.
- macOS와 iOS는 같은 모델 스키마를 공유한다.
- iOS는 iPhone 우선이며 drag/drop은 제외하고 버튼/segmented control 중심으로 처리한다.
- 양 플랫폼 작업 상세는 제목, 보드 날짜, 상태, 메모, 우선순위, 예상 시간, 태그를 편집한다.
- iOS는 현재 보드에서 작업을 편집·제외해 템플릿으로 저장하고 검색, 즐겨찾기, 적용, 삭제할 수 있다.
- 기본 내보내기는 이미지 원본을 포함한 백업 V2이며 JSON V1은 가져오기 호환 경로로만 유지한다.
- Board는 선택일·이월·겹침 이벤트 쿼리를 분리하고 다음 순서를 데이터베이스 최대값으로 계산한다.
- Calendar는 표시 월의 42일 범위 이벤트·배치만 관찰하며 관계 삭제는 이벤트/배치 ID로 필요한 작업만 조회한다.
- 기록 검색은 300ms debounce를 적용하고 행 수가 아닌 완전한 날짜 30개 단위로 페이지를 추가한다.
- 회고 작성은 선택 날짜의 회고와 선택 회고 ID의 블록·첨부만 조회한다.

## 다음 단계

2026-07-12 기준으로 동일 개발 컨테이너의 macOS ↔ iPhone 양방향 create/delete 전파는
고유 진단 레코드로 통과했다. 다음 우선순위는 같은 레코드의 오프라인 동시 편집,
이미지 추가·삭제·재설치, iCloud 로그아웃·재로그인, 자동 복구 백업과 UI smoke test다.
이 조건과 Debug/Release 서명 검증을 모두 통과한 뒤 CloudKit 운영 스키마 승격을 판단한다.

데이터 스키마, 백업, 이미지, CloudKit 동기화 작업의 순서와 Git 운영 규칙은
[`DATA_FOUNDATION_PLAN.md`](DATA_FOUNDATION_PLAN.md)를 따른다.
개발 컨테이너 발급과 검증 절차는 [`CLOUDKIT_SYNC.md`](CLOUDKIT_SYNC.md)를 따른다.
Task 1회성 알림의 V4 스키마, iOS 예약 수명주기와 검증 순서는
[`TASK_REMINDER_PLAN.md`](TASK_REMINDER_PLAN.md)를 따른다.
