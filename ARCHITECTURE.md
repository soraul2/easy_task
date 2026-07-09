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

- SwiftData 모델: `Task`, `CalendarEvent`, `TaskTemplate`, `DailyReview`, `DiaryBlock`
- 저장소 구성: `EasyTaskSchemaV1`, `EasyTaskMigrationPlan`, `EasyTaskContainerFactory`
- 날짜/보드 규칙: `DayKey`, `TaskRules`
- 기록 조회 규칙: `ArchiveQueryRules`, `ArchiveFilter`
- 템플릿 규칙: `TemplateService`, `TemplateListRules`
- 캘린더 이벤트 계산: `CalendarEventTimeline`
- 백업 코덱: `BackupCodec`
- 이미지 파일 저장: `DiaryImageFileStore`
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

1. 두 앱은 `EasyTaskContainerFactory`에서 같은 V1 스키마의 로컬 컨테이너를 생성한다.
2. 앱 시작 시 정책에 따라 demo seed와 lazy archive 규칙을 실행한다.
3. 사용자는 칸반에서 날짜별 작업을 추가하고 상태를 변경한다.
4. 완료된 작업은 당일에는 보드에 남고, 이후 조회 시 보관 흐름으로 이동한다.
5. 캘린더 이벤트는 기간 이벤트로 보이며, 작업 세부 계획은 보드에서 조정한다.
6. 회고는 날짜별 `DailyReview`로 저장되고 기록 탭에서 완료 작업과 함께 검색된다.

## 현재 MVP 범위

- V1 버전 스키마와 로컬 SwiftData 저장만 사용하며 CloudKit은 명시적으로 비활성화한다.
- iCloud/CloudKit 동기화는 다음 단계에서 적용한다.
- macOS와 iOS는 같은 모델 스키마를 공유한다.
- iOS는 iPhone 우선이며 drag/drop은 제외하고 버튼/segmented control 중심으로 처리한다.

## 다음 단계

데이터 스키마, 백업, 이미지, CloudKit 동기화 작업의 순서와 Git 운영 규칙은
[`DATA_FOUNDATION_PLAN.md`](DATA_FOUNDATION_PLAN.md)를 따른다.
