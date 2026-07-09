# EasyTask Architecture

## 개요

EasyTask는 macOS 데스크톱 MVP와 iPhone MVP를 하나의 저장소에서 관리한다. 두 앱은 같은 SwiftData 모델과 순수 서비스 로직을 공유하고, 화면 구현만 플랫폼별로 분리한다.

## 구조

```text
EasyTask.xcodeproj          # iPhone 앱 번들 타겟
Package.swift               # SwiftPM 기반 공통/데스크톱/테스트 구성
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

iPhone 앱은 `EasyTaskiOS`에 둔다.

- `MobileBoardView`: segmented 상태 전환 기반 칸반
- `MobileCalendarView`: 월간 캘린더와 이벤트/템플릿 sheet
- `MobileArchiveView`: 회고와 완료 작업 피드
- `MobileReviewComposerSheet`: 이미지 첨부 가능한 회고 작성

## 데이터 흐름

1. 앱 시작 시 seed 데이터와 lazy archive 규칙을 실행한다.
2. 사용자는 칸반에서 날짜별 작업을 추가하고 상태를 변경한다.
3. 완료된 작업은 당일에는 보드에 남고, 이후 조회 시 보관 흐름으로 이동한다.
4. 캘린더 이벤트는 기간 이벤트로 보이며, 작업 세부 계획은 보드에서 조정한다.
5. 회고는 날짜별 `DailyReview`로 저장되고 기록 탭에서 완료 작업과 함께 검색된다.

## 현재 MVP 범위

- 로컬 SwiftData 저장만 사용한다.
- iCloud/CloudKit 동기화는 다음 단계에서 적용한다.
- macOS와 iOS는 같은 모델 스키마를 공유한다.
- iOS는 iPhone 우선이며 drag/drop은 제외하고 버튼/segmented control 중심으로 처리한다.
