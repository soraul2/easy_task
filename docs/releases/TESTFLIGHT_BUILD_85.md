# TestFlight 1.0 (85)

2026-09-29 사용자의 TestFlight 업로드·커밋·푸시 요청에 따라 iOS·iPadOS·watchOS와 macOS를 업로드했다.

| 플랫폼 | 업로드 완료 (KST) | 근거 |
|---|---|---|
| iOS·iPadOS·watchOS | 2026-09-29 15:09:36.661 | `upload-ios.log`, 종료 코드 0, `Upload succeeded` |
| macOS | 2026-09-29 15:09:36.036 | `upload-macos.log`, 종료 코드 0, `Upload succeeded` |

두 플랫폼 모두 Apple 패키지 처리 시작까지 확인했다. TestFlight 설치 가능 상태·외부 테스트
심사 완료는 확인하지 않았으며, App Store 공개 출시는 수행하지 않았다.

## 포함한 변경

- 일반 Task의 Live Activity 시간 표시를 `TimelineView`에서 계산한 문자열 대신 상한 없는
  시스템 타이머로 바꾸어 앱이 백그라운드인 동안에도 경과 시간을 표시한다.
- Focus는 고정된 시작·종료 시각을 사용하며, 일시정지는 저장된 남은 시간을 표시한다.
  잘못된 실행 payload는 `—`와 접근성 설명으로 구분한다.
- 작업·세션·revision·시각으로 타이머 식별자를 구성하고, 동일한 동적 Text를 접근성 값에도 사용한다.
- iOS 27 최소·가로 표시에서 10시간 이상 값의 초가 잘리던 문제를 보완했다.
  최소 표시의 작은 글꼴은 실기기 가독성 확인이 남아 있다.
- 실제 사용자 저장소를 열지 않는 DEBUG fixture·진단 및 상태·UI 감사 테스트를 추가했다.
  진단 코드와 비교용 Native control은 Release 바이너리에서 제외된다.

일반 Task 멈춤의 수정 전후 증거와 Focus의 미확인 원인은
[Dynamic Island 타이머 구현·검증 결과](../plans/active/DYNAMIC_ISLAND_TASK_TIMER_ANALYSIS_2026_09_29.md#구현-결과)를 따른다.

## 빌드·검증 범위

- 관련 공통 테스트 19개, Debug 511개·Release 507개 패키지 테스트와
  `./scripts/verify-platform-builds.sh`가 기능 구현 단계에서 통과했다.
- 모바일 상태 테스트 12개씩이 iOS 27.0/26.5에서 통과했다. 메모리 fixture의 60초 연속 갱신,
  30초 일시정지, 휴식 종료, 장시간·최소·가로 표시를 녹화·화면 값·API 호출 로그로 검증했다.
  최종 최소 글꼴 변경 후 iOS Debug·Release 빌드와 관련 UI 감사 2개도 통과했다.
- 기능 검증 이후 앱 코드는 변경하지 않았다. 배포 준비에서는 프로젝트 설정 14개와 Info.plist
  5개의 빌드 번호만 85로 올렸다. 버전 변경만으로 전체 공통 테스트를 반복하지 않았다.
- iOS(내장 Watch 포함)·macOS Release archive와 App Store Connect용 export가 모두 종료 코드 0으로
  완료됐다. 앱·위젯 6개 모두 1.0(85)이며 archive 서명, 배포 패키지의 Production 권한,
  기존 bundle ID·App Group·CloudKit·key-value store와 privacy manifest를 확인했다.
- iOS 214개·macOS 206개 컴파일 소스가 고정한 배포 사본 및 작업 폴더와 일치한다.
  배포 실행 파일 6개의 UUID가 archive와 같고 DEBUG 타이머 감사 심볼·인자가 없다.
  Mac 패키지는 Intel·Apple Silicon을 포함한다.
- 영속 스키마 V11·백업 package V10·payload 키 `updatedAt`·기존 누적 시간 계산은 유지한다.
  실제 사용자 저장소·CloudKit 접근 또는 별도 CloudKit schema 배포는 수행하지 않았다.

**iOS 27 실기기 최종 확인은 남아 있다.** Focus 멈춤은 시뮬레이터에서 재현하지 못했으므로
사용자 이슈 전체를 해결 완료로 표시하지 않는다. VoiceOver 실제 음성, 저전력·Always-On 및
깨우기 동작, 최소 글꼴 가독성, TestFlight 설치와 기기 간 CloudKit 왕복은 미검증이다.
expanded는 배치·자리수 검증을 수행했으며 별도 60초 연속 관찰은 수행하지 않았다.

## 소스와 증거

배포 시작 HEAD는 `688829a894850fb51fb5c8b0eb03664aea4c524d`다. 타이머 변경과 build 85 설정을
포함한 작업 폴더를 `.local/releases/build-85/source/`에 고정하여 archive를 생성했다.
업로드는 커밋 전에 완료했으며, 배포한 앱 소스·설정과 이 기록을 같은 후속 커밋에 포함한다.
업로드 완료 후 갱신한 문서는 앱 바이너리에 영향을 주지 않는다.

Git에서 제외된 `.local/releases/build-85/`에 소스 426개의 해시, 변경 patch, archive,
배포 패키지, 버전·서명·컴파일 소스·실행 파일 검증, 업로드 로그와 결과 JSON을 보존한다.
기능 검증 자료는 `.local/dynamic-island-task-timer-2026-09-29/`와
`feature-verification-link.json`으로 연결한다. 커밋·푸시 후 SHA는 로컬 `release-status.json`에 기록한다.
테스트 안내 문구는 `testflight-notes-ko.txt`에 보관했으며 App Store Connect의 안내 필드에는 입력하지 않았다.
