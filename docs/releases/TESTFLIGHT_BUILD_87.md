# TestFlight 1.0 (87) — 업로드 완료

2026-10-03 iOS·iPadOS·watchOS와 macOS의 업로드 성공 및 Apple 패키지 처리 시작을 확인했다. 사용자가 후속으로 미룬 실제 화면 검증과 전체 최적화 Goal의 완료 여부는 별도로 유지한다.

**재개 경위(2026-10-03)**: 앞선 외출 중 보류 요청에 따라 소스와 배포 준비 기록을 `e02eb9f70a267d7dfb08c82441cb727fddc002c3`로 commit·push했다. 이후 사용자가 Apple 계정 로그인을 완료하고 TestFlight 업로드를 다시 요청했다. 같은 archive로 재개했으며 필요한 Mac Installer Distribution 인증서를 Xcode에서 준비했다.

## 배포 상태

| 플랫폼 | 업로드 완료 시각(KST) | 현재 확인 |
|---|---|---|
| iOS·iPadOS·watchOS | 2026-10-03 13:14:21 | `upload-ios-retry1` exit0, 업로드 성공·Apple 패키지 처리 시작 |
| macOS | 2026-10-03 13:16:38 | `export-macos-retry1`·`upload-macos-retry1` exit0, 업로드 성공·Apple 패키지 처리 시작 |

Delivery ID는 iOS `7c73f592-d6c2-4ba2-abfc-fcaa7a1b079a`, macOS `79737b54-3d0b-4b55-8799-b4c21c68b1d7`이다. 두 업로드 모두 `Upload succeeded.`·`Uploaded package is processing.`과 exit0를 확인했다. 설치 가능 상태·테스터 공개·외부 테스트 심사는 확인하지 않았다.

첫 시도의 실패 기록은 보존했다. iOS는 10:42:03 KST `Failed to Use Accounts`, Mac local export는 `No Accounts`와 `No signing certificate "Mac Installer Distribution" found`로 각각 exit70이었다. 로그인·설치 서명 준비 후 별도 `retry1` 로그에 성공 결과를 남겼다. 앱 재빌드나 기존 인증서 폐기는 수행하지 않았다.

## 포함한 변경

- 작업 기록이 많은 환경의 시작·복귀, 저장한 작업 추천, 달력의 일정 수, 메모 검색, 사진 확인과 백업의 반복 처리를 줄였다. 최신 저장 내용·미저장 초안·중복 수렴 규칙을 보완했다.
- 별도 **PlanBase 오늘 일정** 잠금 화면 위젯을 추가했다. 한 줄·원형·직사각형으로 오늘 일정과 수를 표시하고 오늘 캘린더로 이동하도록 구현했다. 추가 방법과 마지막 발행 데이터·시스템 갱신 한계는 [사용 안내](../CALENDAR_LOCK_SCREEN_WIDGET_GUIDE.md)를 따른다.
- 메모 저장 실패 시 재시도 버튼 배치를 수정하고 필기 화면 종료 시 도구 팔레트를 정리했다. iPad 캘린더 헤더는 시스템 창 제어기 영역을 반영했다.
- macOS 회고의 제목·본문을 우선 배치하고 Watch의 하루 요약 계산을 개선했다. 스케치·체크리스트·자동 저장·알림·Focus 및 백업의 데이터 계약을 유지했다.

규모별 서비스 측정, 작은 조건의 증가와 채택하지 않은 후보는 [최적화 결과](../plans/active/OPTIMIZATION_2026_10_02_RESULTS.md)에 기록했다. 함수나 합성 데이터의 개선율을 앱 전체 반응·배터리 보증으로 확대하지 않는다.

## 소스·패키지 검증

- 배포 시작 HEAD는 `b7e524a0038df84a6b5b84864cb1774b9199cabf`다. 현재 작업 폴더의 487개 파일을 `.local/releases/build-87/source/`에 고정하고 이 사본에서 아카이브를 생성했다.
- 업로드 재개 시 commit `e02eb9f70a267d7dfb08c82441cb727fddc002c3`의 빌드 입력409개와 고정 사본487개의 SHA-256을 다시 대조해 불일치0을 확인했다. 여섯 archive 번들의 strict 서명도 통과했다. 이번 재개에서는 제품 소스와 빌드 번호를 바꾸지 않았다.
- 최종 로컬 검증의 409개 빌드 입력과 비교해 변경된 여섯 파일은 프로젝트 설정 14곳·Info.plist 5개의 빌드 번호86→87뿐이다. Swift 소스373개와 스키마·호환 ID는 그대로다. 문서의 후속 갱신은 앱 바이너리에 영향을 주지 않는다.
- iOS218개·macOS210개 실제 컴파일 소스는 배포 사본과 현재 작업 폴더에 일치한다. 새 오늘 일정 위젯과 공통 규칙도 포함된다.
- iOS 배포 앱·위젯·Watch 네 번들은 1.0(87), 기존 bundle ID·App Group, Production CloudKit/APS, privacy manifest와 strict 서명을 확인했다. 배포 실행 파일은 archive UUID와 같고 DEBUG fixture·오류 주입용 표식이 없다. 독립 검토도 Info·Privacy·UUID·device 플랫폼·entitlements를 대조했다.
- Mac 아키텍처 검증기에서 빌드 번호 치환이 `x86_64` 문자열까지 바꿨던 오류는 검증기만 바로잡고 재검증했다. 실제 archive는 두 아키텍처를 포함하며 제품 재빌드는 하지 않았다. 첫 실패 기록을 보존한다.
- 재개 후 Mac 패키지의 Apple 발급 설치 서명, 앱·위젯의 1.0(87)·Production 권한·privacy manifest·strict 서명·Intel/Apple Silicon을 확인했다. 두 실행 파일의 UUID는 archive와 일치하며 DEBUG fixture·오류 주입 표식은 없다.
- 빌드 번호 변경 후 전체 플랫폼 게이트는764.430초·exit0로 완료됐다. 공통 Debug는689통과·36skip, Release는684통과·10skip이며 실패0이다. iOS/macOS Debug·Release 네 빌드, 내장 위젯6·Watch2와 privacy manifest12를 검증했다. 종료 후 현재409개 입력·373Swift 목록도 고정한 배포 사본과 일치한다.

## 후속 화면 확인

사용자 지시에 따라 잠금 화면 위젯 세 모양의 실제 추가·render·긴 제목/기간·privacy·tap·자정/iPad, Watch Today/Focus·snapshot 공유·컴플리케이션과 남은 Mac·VoiceOver/IME 화면 인수는 후속으로 보류한다. 이전 기능·hosted 검사는 실제 OS 화면 통과로 바꾸지 않는다. 직접100ms 반응, 실기기 배터리·장시간 동작과 운영 CloudKit 왕복도 별도 확인 대상이다.

Git에서 제외된 `.local/releases/build-87/`에 source manifest·변경 patch·archive·패키지·검증·실패 및 배포 로그를 보존한다. 최종 영수증은 `upload-results.json`, 재개 대조는 `resume-preflight-20261003.json`, Mac 패키지 검증은 `macos-retry1-production-acceptance.json`에 기록했다. 한국어 테스트 안내는 `testflight-notes-ko.txt`에 준비했으며 App Store Connect 입력 완료로 표시하지 않는다.
