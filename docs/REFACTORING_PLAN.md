# EasyTask UI Refactoring Plan

## 목표

- 사용자 동작과 SwiftData 스키마를 변경하지 않고 대형 SwiftUI 파일의 책임을 분리한다.
- 화면 루트는 조회, 화면 상태, 라우팅만 담당하고 세부 편집기와 반복 UI는 별도 파일로 옮긴다.
- 각 단계는 독립 커밋으로 만들며 공통 테스트와 iOS/macOS 빌드가 통과해야 다음 단계로 이동한다.

## 원칙

1. `EasyTaskCore`의 모델과 서비스 API는 이번 작업에서 변경하지 않는다.
2. SwiftData `@Query` 범위와 저장 명령 경계는 유지한다.
3. 화면 문구, 색상, 레이아웃, 접근성 식별자와 사용자 흐름을 변경하지 않는다.
4. 새 UI 타입은 기본적으로 target 내부 접근 수준을 사용하고 외부 공개 API를 만들지 않는다.
5. 공통화는 실제 중복이 확인된 경우에만 수행한다.
6. 파일 이동 단계와 동작 개선 단계를 같은 커밋에 섞지 않는다.

## 우선순위

### P0. iOS Board

현재 `MobileBoardView.swift`가 루트 조회, 카드, 상태 슬라이더, 상세 편집, 이월함,
템플릿 라이브러리를 함께 소유한다.

- `MobileBoardView.swift`: 화면 루트와 저장 명령 연결
- `MobileBoardComponents.swift`: 헤더, 이벤트, 빠른 입력, 상태 선택, 카드
- `MobileTaskDetailSheet.swift`: Task 상세 편집과 알림
- `MobileCarryoverSheet.swift`: 이월함
- `MobileTemplateLibrarySheet.swift`: 보드 템플릿 저장과 적용

### P1. iOS Calendar

- `MobileCalendarView.swift`: 월 상태, 쿼리 범위, 배치 라우팅
- `MobileCalendarGrid.swift`: 헤더, 요일, 날짜 셀, 기간 이벤트 띠
- `MobileEventEditorSheet.swift`: 이벤트 생성·수정·삭제
- `MobileCalendarDaySheet.swift`: 선택 날짜 상세
- `MobileTemplatePlacementSheet.swift`: 템플릿 검색·편집·배치

### P2. iOS Archive와 Review

- 기록 검색 세션과 카드 표시를 분리한다.
- 이미지 carousel과 이미지 디코딩 UI를 별도 파일로 옮긴다.
- 회고 작성기의 헤더, 편집기, 이미지 선택 UI를 분리한다.

### P3. macOS

- `BoardView.swift`의 카드·상세·이월·템플릿 창을 분리한다.
- `CalendarView.swift`의 그리드·이벤트 편집·템플릿 배치를 분리한다.
- AppKit 파일 패널과 SwiftUI 화면 경계는 유지한다.

### P4. 회귀 방지

- iOS launch 및 탭 전환 UI smoke 테스트 타겟을 추가한다.
- 앱 시작, 보드 빠른 입력 노출, 캘린더 열기, 기록 열기를 최소 시나리오로 둔다.
- 성능 최적화는 Instruments 측정 결과가 있는 경우에만 별도 브랜치에서 진행한다.

## 진행 결과

- [x] P0 iOS Board: 루트 파일 `1,398`줄에서 `233`줄로 축소
- [x] P1 iOS Calendar: 루트 파일 `1,962`줄에서 `448`줄로 축소
- [x] P2 iOS Archive/Review: 기록 `656`줄에서 `171`줄, 회고 작성기 `511`줄에서 `305`줄로 축소
- [x] P3 macOS Board/Calendar: 루트 파일을 각각 `561`줄, `562`줄로 축소
- [x] P4 회귀 방지: 실제 데이터와 알림을 격리한 iOS UI smoke 테스트 추가

각 단계는 독립 커밋으로 기록했으며 SwiftData 스키마, CloudKit 설정, 백업 형식은 변경하지 않았다.

## 단계별 완료 조건

- `swift test` 전체 통과
- iOS Simulator Debug 빌드 통과
- macOS Debug 빌드 통과
- `git diff --check` 통과
- 원본 화면 파일의 줄 수와 책임이 감소
- SwiftData 모델, 백업 형식, CloudKit 설정 변경 없음
