# TestFlight 1.0 (80)

2026-09-17 iOS·iPadOS·watchOS와 macOS의 App Store Connect 업로드를 완료했다.

| 플랫폼 | 업로드 완료 (KST) | 근거 |
|---|---|---|
| iOS·iPadOS·watchOS | 2026-09-17 22:11:24 | `upload-ios.log`, 종료 코드 0, `Upload succeeded` |
| macOS | 2026-09-17 22:11:17 | `upload-macos.log`, 종료 코드 0, `Upload succeeded` |

두 플랫폼 모두 Apple 패키지 처리 시작을 확인했다. 이 기록은 TestFlight 설치 가능
상태나 외부 테스트 심사 완료를 뜻하지 않는다. archive·패키지·서명 검증·업로드 로그는
Git에서 제외된 `.local/releases/build-80/`에 보존한다.

## 변경 내용

- 이월함에 전체 개수와 새로 들어온 작업을 표시하고, 마지막 작업 처리 후에도 결과 안내를 유지한다.
- 기록의 `회고` 탭에서 직접 작성한 회고를 모아 검색·읽기·수정할 수 있다. 탭 전환 후 읽던 위치와 기존 날씨·기분을 보존한다.
- 오늘 할 일이나 진행 중 작업이 남아 있으면 잠금 화면 실시간 카드를 유지한다. 할 일은 `시작`, 진행 중 작업은 `완료`로 처리하며, `변경`은 표시할 작업만 전환한다. 모두 끝나면 카드를 종료한다.
- 칸반 빈 상태 안내를 다듬고 체크리스트가 있는 작업은 기본으로 펼쳐 표시한다.

## 검증

- 기능 변경 최종 소스의 전체 플랫폼 회귀 게이트 종료 코드 0을 확인했다. 배포 전 변경 소스·설정 43개의 해시가 검증 기록과 일치했다.
- 공통 Debug 검사 총 485개 중 480개 통과·선택 성능 검사 5개 제외, Release 총 482개 중 478개 통과·4개 제외. 실패는 없다.
- iOS·macOS Debug/Release와 내장 Watch·위젯·privacy manifest 검증 통과. 화면·동작 검증과 미확인 항목은 [구현 결과](../plans/active/CARRYOVER_AND_REVIEW_DISCOVERY_RESULTS.md)에 기록했다.
- 배포를 위해 빌드 번호만 80으로 올린 고정 소스에서 iOS·macOS Release archive를 생성했다. 앱·위젯 6개 모두 1.0 (80), 기존 bundle ID·App Group·CloudKit·key-value store를 유지한다.
- 내보낸 iOS IPA·macOS 패키지의 Production 권한·서명을 검증했다. macOS는 Intel·Apple Silicon을 모두 포함한다. 실행 파일 6개의 UUID는 검증한 archive와 일치한다.
- 컴파일 소스 iOS 207개·macOS 199개가 고정 소스와 작업 트리에 일치한다. 배포 실행 파일에서 DEBUG 전용 `DiscoveryPreviewFixtures`·`MemoUITestSupport` 심볼이 제외됐다.

영속 스키마 V11·백업 형식·최소 지원 OS를 유지하며 추가 CloudKit schema 배포는 없다.
실기기 잠금 인증·Always-On·개인정보 가림·실제 8시간 경과는 별도 확인 대상이다.
이번 작업은 TestFlight 업로드이며 App Store 공개 출시는 수행하지 않았다.
