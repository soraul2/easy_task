# PlanBase 구조 정리 체크리스트

기준일: 2026-07-24

## 목표와 변경 경계

동작, 데이터 의미, 배포 호환성을 바꾸지 않고 파일 책임과 탐색 경로를 명확하게 한다.
각 단계는 관련 검증을 통과한 뒤 완료 처리한다.

- 기존 `EasyTaskSchemaV1`~`V6`, migration, CloudKit 계약을 변경하지 않는다.
- bundle ID, CloudKit container, App Group, 백업 UTI와 레거시 이름을 변경하지 않는다.
- 기능 변경과 파일 이동을 섞지 않는다.
- 수동 Xcode target membership을 파일 이동 때마다 확인한다.
- `.local/backups/`와 금지된 iCloud Drive 경로에 접근하지 않는다.

## 진행 순서

- [x] 1. 문서 최신화와 운영/진행/완료 계획 분류
  - [x] `docs/README.md` 문서 지도를 추가했다.
  - [x] 현재 구현에 맞게 적응형 월 그리드, 특일 fallback, 공통 패키지 UI 의존 설명을 고쳤다.
  - [x] 출시 확인이 남은 계획과 완료 기록을 각각 `plans/active`, `plans/completed`로 분리했다.
  - 검증: 내부 문서 링크 검색, `git diff --check`
- [x] 2. `PlanBaseCoreTests.swift`를 기능별 테스트 파일로 분리
  - [x] Task 완료, Board 규칙, Backup 호환, Template, Calendar, Archive/Review, Theme 파일로 분리했다.
  - [x] 기존 테스트 함수 37개와 테스트 표식을 그대로 보존했다.
  - 검증: `swift test` 232개 통과
- [x] 3. `MobileShared.swift`를 레이아웃·이미지 책임별로 분리
  - [x] 앱 공용 별칭·레이아웃·작은 UI는 `MobileUIComponents.swift`로 분리했다.
  - [x] 레거시 이미지 해석·다운샘플·캐시는 `MobileImageSupport.swift`로 분리했다.
  - [x] 두 파일을 iOS Sources와 Xcode group에 등록했다.
  - 검증: `swift test` 232개 통과, iOS Debug simulator build 통과
- [x] 4. 모바일·데스크톱 소스를 기능별 폴더로 재배치
  - [x] iOS 화면을 `App/Features`의 Board, Calendar, Templates, Archive, Review, Memo로 분류했다.
  - [x] iOS 플랫폼 어댑터를 `App/Infrastructure`로 분류했다.
  - [x] macOS 화면을 `App/Features`의 Board, Calendar, Archive, Memo로 분류했다.
  - [x] 실제 파일 경로와 같은 Xcode group 계층을 만들고 모든 source-root 경로를 검사했다.
  - 검증: `xcodebuild -list`, iOS/macOS Debug build 통과
- [x] 5. 위젯과 대형 플랫폼 View 파일 분리
  - [x] 978줄 캘린더 위젯을 intent, timeline, view, theme, widget, bundle 파일로 분리했다.
  - [x] macOS `ArchiveView`를 루트, 검색/필터, 날짜 기록 카드 파일로 분리했다.
  - [x] macOS `DiaryView`에서 sheet와 이미지 지원 책임을 분리했다.
  - [x] 새 파일을 Widget/macOS Sources와 기능별 Xcode group에 등록했다.
  - 검증: Widget 전용, iOS Debug, macOS Debug build 통과
- [x] 6. Backup·DataIntegrity 대형 코어 파일 분리
  - [x] Backup DTO, codec, 레코드 변환을 독립 파일로 분리했다.
  - [x] package restore 진입점, 레코드 병합, 동일성·참조 검증을 독립 파일로 분리했다.
  - [x] DataIntegrity 진입점, 중복/참조 수렴, 정규화, 레코드 계약을 독립 파일로 분리했다.
  - [x] 외부 공개 API와 Report setter의 외부 접근 수준을 유지했다.
  - 검증: `swift test` 232개 통과
- [x] 7. 전체 회귀 게이트 실행 및 체크리스트 마감
  - [x] Debug/Release SwiftPM 테스트를 실행했다.
  - [x] iOS/macOS Debug/Release simulator build를 실행했다.
  - [x] 문서 링크, Xcode source-root 경로, `git diff --check`를 최종 확인했다.
  - 검증: `./scripts/verify-platform-builds.sh` 통과

## 완료 기준

- 모든 체크박스와 단계별 검증이 완료된다.
- 저장 스키마, 호환 식별자, 사용자 동작에는 diff가 없다.
- 새 파일은 올바른 SwiftPM 또는 Xcode target에서 컴파일된다.
- 문서가 최종 디렉터리 구조와 검증 절차를 반영한다.
