# TestFlight 1.0 (92) — 업로드 완료

2026-10-14 잠금화면의 실시간 할 일 카드에서 화살표로 다른 작업을 보는 동작을 수정한
iOS·iPadOS·내장 watchOS 패키지를 준비했다. 고정 소스 519개는
`.local/releases/build-92/source/`에 보존한다. 이번 업로드 대상은 iOS 패키지이며,
배포된 macOS의 최신 빌드는 1.0(91)이다.

## 포함한 변경

표시할 작업만 바꾸는 `AdvancePlanBaseTaskIntent`의 인증 정책을
`.requiresLocalDeviceAuthentication`에서 `.alwaysAllowed`로 수정했다.
작업 시작·완료·집중 제어의 인증 정책과 제목의 개인정보 가림은 유지한다.
build 91과 비교한 기능 변경은 이 Intent 한 곳이며, 스키마·CloudKit·백업 계약은 동일하다.

## 검증

- 공통 작업 선택 회귀 테스트 6개 통과.
- iOS Debug 상태 테스트 13개 및 실제 Simulator 카드 UI 테스트 1개 통과.
- UI 검증은 작업 순환·시작·완료·같은 Activity 유지·마지막 작업 완료 후 제거를 포함한다.
- 실제 암호로 잠긴 iPhone에서의 넘김과 TestFlight 설치 확인은 남아 있다.

테스트는 버전 번호 변경 직전 작업 폴더에서 실행했다. 배포 소스는 이후 번호만 92로
맞춰 고정했으며, 배포된 build 91 대비 변경 범위와 고정 소스 SHA를 확인했다.
이번 변경에 대한 전체 플랫폼 회귀 게이트는 재실행하지 않았다.

## 업로드와 공지 상태

Release archive와 App Store 배포 패키지 export는 모두 exit 0으로 완료됐다.
앱·위젯·Watch 앱·Watch 위젯 4개 번들의 1.0(92), 기존 bundle ID, strict 서명,
Production CloudKit/APS, App Group, privacy manifest 및 device 플랫폼을 확인했다.
Watch 최소 OS 10.0과 arm64_32·arm64, archive와 배포 실행 파일 UUID 일치 및
DEBUG 진단 코드 부재도 통과했다.

2026-10-14 16:36:50 KST에 `Upload succeeded`·`Uploaded package is processing`·
`EXPORT SUCCEEDED` 및 exit 0을 확인했다. App Store Connect에서 빌드 92의 처리가 완료돼
`제출 준비 완료` 상태가 된 것을 확인했다. 기존 내부 ‘지인’ 그룹 2명에 연결돼 있었으며,
한국어 테스트 내용을 입력하고 `저장 완료` 및 원문 일치를 확인했다.
이미 수락된 패키지는 재업로드하지 않는다. 별도의 테스터 알림 버튼 실행과 실제 기기의
TestFlight 설치는 확인 범위 밖이다.

[빌드 92](https://appstoreconnect.apple.com/teams/b758923f-e4ea-4044-847d-88402a515c41/apps/6792667826/testflight/ios/ef56ca15-e33a-4453-8ff5-691997887111)의
공지 저장 화면은 `.local/releases/build-92/testflight-ios-notice-saved.png`,
UI 확인 영수증은 `app-store-connect-ui-completion.json`에 보존했다.

## 한국어 테스트 내용

잠금화면의 실시간 할 일 카드에서 화살표를 눌러도 다른 작업으로 바뀌지 않던 동작을 수정했습니다. 기기를 잠근 상태에서도 화살표로 오늘의 할 일과 진행 중 작업을 차례로 볼 수 있도록 했습니다.

테스트할 내용

• 업데이트 후 앱을 한 번 열고, 오늘의 할 일이 2개 이상 있는 상태에서 잠금화면 카드를 확인해 주세요.
• 화살표를 눌렀을 때 다른 할 일이나 진행 중 작업으로 바뀌는지 확인해 주세요.
• 작업을 넘겨 보는 것만으로 시작·완료 상태나 진행 시간이 바뀌지 않는지 확인해 주세요.
• 작업 시작·완료는 기존처럼 잠금 해제 후 사용하고, 마지막 작업 완료 시 카드가 사라지는지 확인해 주세요.

공지 원문과 배포 영수증은 `.local/releases/build-92/`에 보존한다.
