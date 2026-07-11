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
- 날짜/보드 규칙: `DayKey`, `TaskRules`
- 기록 조회 규칙: `ArchiveQueryRules`, `ArchiveFilter`
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

1. 두 앱은 `EasyTaskContainerFactory`에서 같은 V3 스키마의 로컬 컨테이너를 생성한다.
2. 저장소는 V1 → V2 → V3 순서로 이동하며 이미 배포된 V1/V2 정의는 수정하지 않는다.
3. 앱 시작 시 무결성 정리와 레거시 이미지 이관을 실행한 뒤 demo seed와 lazy archive 규칙을 실행한다.
4. 사용자는 칸반에서 날짜별 작업을 추가하고 상태를 변경한다.
5. 완료된 작업은 당일에는 보드에 남고, 이후 조회 시 보관 흐름으로 이동한다.
6. 캘린더 이벤트는 기간 이벤트로 보이며, 작업 세부 계획은 보드에서 조정한다.
7. 회고는 날짜별 `DailyReview`로 저장되고 기록 탭에서 완료 작업과 함께 검색된다.
8. 새 회고 이미지는 `DiaryAttachment.data`에 external storage로 저장되고 파일명 필드는 이관 입력으로만 사용한다.
9. 백업 V2는 `manifest.json`, `records.json`, `attachments/`로 구성된 `.easytaskbackup` 패키지다.

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
- 새 이미지 추가·삭제는 회고 본문과 한 번의 SwiftData 저장으로 확정되어 별도 고아 파일을 만들지 않는다.
- V2의 `imageFileNames`와 이미지 `DiaryBlock`은 V3 개방 후 앱 지원 폴더에서 점진적으로 옮긴다.
- 누락되거나 손상된 기존 파일은 참조를 지우지 않고 다음 실행에서 재시도하며, 모두 옮긴 회고만 레거시 참조를 정리한다.
- 기존 이미지가 10개를 넘으면 처음 10개까지만 옮기고 초과 참조는 보존한다. 배열과 block-only 참조를 함께 표시하며 미해결 레거시 항목은 삭제해 백업 차단을 해소할 수 있다.
- 미해결 레거시 항목이 남은 동안 canonical 이미지 추가·삭제는 잠그고, 마지막 항목을 정리해 저장할 때 기존 메타데이터와 이미지 블록을 제거한다.
- 백업 V2는 records와 각 첨부의 크기·SHA-256, MIME, 참조 무결성을 전부 확인한 뒤 비파괴 병합한다.
- `.easytaskbackup`은 `public.package` 계열의 고정 UTI로 등록해 Finder와 파일 패널에서 하나의 패키지로 다룬다.
- JSON V1은 계속 읽지만 이미지 바이트를 포함하지 않으므로 누락 파일을 보고하고 결정적 `instanceID`로 병합한다.

## 현재 MVP 범위

- V3 버전 스키마와 로컬 SwiftData 저장만 사용하며 CloudKit은 명시적으로 비활성화한다.
- iCloud/CloudKit 동기화는 다음 단계에서 적용한다.
- macOS와 iOS는 같은 모델 스키마를 공유한다.
- iOS는 iPhone 우선이며 drag/drop은 제외하고 버튼/segmented control 중심으로 처리한다.
- 기본 내보내기는 이미지 원본을 포함한 백업 V2이며 JSON V1은 가져오기 호환 경로로만 유지한다.

## 다음 단계

데이터 스키마, 백업, 이미지, CloudKit 동기화 작업의 순서와 Git 운영 규칙은
[`DATA_FOUNDATION_PLAN.md`](DATA_FOUNDATION_PLAN.md)를 따른다.
