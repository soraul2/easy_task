# TestFlight 1.0 (88) — 검증 완료·업로드 준비

2026-10-03 과거 날짜 보드에서 완료일을 선택하는 기능을 추가했다. 사용자는 구현·검증 후 commit·push와 TestFlight 업로드까지 요청했다. 업로드 성공 여부는 전송 결과가 확인된 뒤 갱신한다.

## 포함한 변경

- iPhone·iPad·Mac의 과거 보드에서 일반 완료를 **오늘 완료**로 표시한다.
- 미완료 작업 메뉴에 **선택한 날짜에 완료로 기록**을 추가한다. 예를 들어 10월 2일 보드에서는 `10월 2일 완료로 기록`을 선택할 수 있다.
- 완료 카드에 계획일·완료일을 함께 표시하고 완료 안내에도 기록된 날짜를 표시한다.
- 두 방식 모두 15초 실행 취소를 지원한다. 과거 완료일과 실제 처리 시각을 분리하고, 알림 확인 중 날짜 변경·이후 동기화 변경을 보호한다.

`completedAt`·진행 종료·captured 활동은 실제 처리 시각을 유지한다. SwiftData V11, CloudKit V11 Production, App Group, 백업 V10과 위젯 snapshot v5는 변경하지 않는다. 상세 동작은 [칸반 흐름](../plans/active/KANBAN_FLOW_IMPROVEMENT.md#2026-10-03-완료일-선택-보완)을 따른다.

## 검증 상태

- 완료일 선택·실행 취소 관련 공통 테스트 14개 통과. 첫 테스트 컴파일의 Sendable 인자 문제는 테스트 인자만 문자열로 수정했다.
- iPhone 17 Pro·iPad Pro 11 M4의 iOS 26.5 격리 시뮬레이터에서 각 3개, 총 6개 UI 테스트 통과. 오늘 완료의 날짜 이동·실행 취소, 선택한 과거 날짜 완료·날짜 표시·실행 취소, 접근성 큰 글자 흐름을 확인했다.
- 전체 플랫폼 게이트는 876.195초, exit0. 공통 Debug 693통과·36skip, Release 688통과·10skip, 실패0. iOS/macOS Debug·Release와 내장 Watch·위젯·privacy manifest를 확인했다.
- 실제 Mac UI·실기기 화면은 이번 검사에 포함하지 않았다. 기존 빌드의 보류된 화면 인수 항목도 그대로 유지한다.
- 실기기 CloudKit 왕복·Apple 처리 후 설치 가능 상태는 별도 확인 대상이다.

배포 자료는 Git에서 제외된 `.local/releases/build-88/`, 최초 공통 검증은 `.local/completion-date-choice-20261003/`에 보존한다.

## 소스·배포 패키지

- 시작 HEAD는 `e02eb9f70a267d7dfb08c82441cb727fddc002c3`. 저장소 파일491개를 `.local/releases/build-88/source/`에 고정해 두 플랫폼을 컴파일했다. 빌드 번호는 프로젝트14곳·Info.plist5개의 87→88 변경이며 마케팅 버전은1.0이다.
- 빌드 입력411개 중 전체 게이트 진행 중 바뀐 것은 별도로 다시 컴파일·실행한 UI 테스트의 스크롤·헤더 확인 순서뿐이다. 앱·공통 테스트 입력은 바뀌지 않았다. 최종 입력411개와 작업 폴더가 일치하며 실제 컴파일된 iOS219개·macOS211개 Swift 파일도 고정 소스와 일치한다.
- 최종 `export-ios-retry2`·`export-macos-retry2` 패키지의 6개 번들은 1.0(88), 기존 bundle ID·App Group, Production CloudKit/APS, privacy manifest와 strict 서명을 통과했다. Mac은 Apple Silicon·Intel과 Apple 발급 설치 서명을 확인했다.
- 최종 실행 파일6개의 UUID는 archive와 일치하며 DEBUG fixture·UI 오류 주입 표식이 없다. device 플랫폼과 전체 entitlements가 build87의 정상 Production 패키지와 정확히 일치한다.

## 검증·서명 재시도 기록

첫 iPhone 큰 글자 검사에서는 화면 밖의 lazy 카드와 날짜 헤더를 스크롤 전에 찾던 테스트 단언을 수정했다. 최종 `ui-iphone-retry2`에서 3개 모두 통과했다. 첫 iPad 실행은 테스트 시작 전 CoreSimulator 앱 실행 요청에서 멈춰 해당 작업용 시뮬레이터만 재시작했고, `ui-ipad-retry1`에서 3개 모두 통과했다. 이 과정에서 제품 소스를 변경하지 않았다.

Xcode가 프로파일에 포함되지 않은 개발 인증서를 자동 선택해 최초 archive가 실패했다. 특정 인증서/수동 프로파일을 지정한 시도도 Xcode 관리형 프로파일과 충돌했다. 서명 없이 컴파일한 archive의 첫 자동 export는 App Group 권한이 빠져 최종 검증에서 제외했고 업로드하지 않았다.

7개 entitlement 소스가 build87과 동일함을 확인한 뒤, 기존의 유효한 Apple Distribution 인증서·Production 프로파일과 build87의 동일한 entitlements로 archive의 내부 번들부터 서명했다. 실행 파일 UUID가 유지됨을 확인하고 자동 export를 다시 수행했다. 최종 패키지에서 strict 서명·전체 권한·UUID를 재검증했다. 실패한 시도와 권한 누락 패키지는 구분해 로컬 증거로 보존했다. 인증서 폐기·새 권한 추가·저장소의 서명 설정 변경은 하지 않았다.

주요 근거는 `platform-validation.json`, `ui-validation.json`, `compiled-source-verification.json`, `archive-production-signing.json`, `production-final-acceptance.json`과 두 최종 xcresult다. 한국어 테스트 안내는 `testflight-notes-ko.txt`에 준비했으며 App Store Connect 입력 완료로 표시하지 않는다.
