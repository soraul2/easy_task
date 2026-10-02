# TestFlight 1.0 (86)

2026-10-02 사용자의 TestFlight 업로드 후 커밋·푸시 요청에 따라 iOS·iPadOS·watchOS와 macOS를 업로드했다.

| 플랫폼 | 업로드 완료 (KST) | 근거 |
|---|---|---|
| iOS·iPadOS·watchOS | 2026-10-02 15:19:10.967 | `upload-ios.log`, 종료 코드 0, `Upload succeeded` |
| macOS | 2026-10-02 15:18:41.542 | `upload-macos.log`, 종료 코드 0, `Upload succeeded` |

두 플랫폼 모두 Apple 패키지 처리 시작까지 확인했다. TestFlight 설치 가능 상태와 외부 테스트
심사 완료는 확인하지 않았다.

## 포함한 변경

- iPhone·iPad와 Mac 보드에서 빠른 입력칸이 비어 있으면 아래에
  “/를 입력하면 저장한 작업을 찾아 추가할 수 있어요.”를 표시한다.
- 입력칸에 같은 접근성 힌트를 추가하고 시각 안내 문구의 중복 낭독을 제외한다.
- `/` 입력 시 후보 표시·검색·선택·추가하는 기존 동작은 유지한다.
  이번 변경은 저장한 작업 추천을 발견할 수 있게 돕는 안내이며, 임의의 과거 Task를 추천하는 기능을 추가한 것은 아니다.

## 빌드·검증 범위

- `./scripts/verify-platform-builds.sh`가 종료 코드 0으로 완료됐다.
  Debug 511개·Release 507개 공통 테스트와 iOS(내장 Watch 포함)·macOS Debug/Release 빌드,
  내장 앱·위젯 및 privacy manifest 검증을 통과했다.
- iOS·macOS Release archive와 App Store Connect용 export·upload가 모두 종료 코드 0으로 완료됐다.
  앱·위젯 6개 모두 1.0(86)이며 archive 서명과 배포 패키지의 Production 권한,
  기존 bundle ID·App Group·CloudKit·key-value store 및 privacy manifest를 확인했다.
- iOS 214개·macOS 206개 컴파일 소스가 고정한 배포 사본과 작업 폴더의 파일에 일치한다.
  배포 실행 파일 6개의 UUID가 archive와 같고 검증 대상 DEBUG fixture·진단 심볼과 테스트 인자가 없다.
  Mac 앱·위젯은 Intel·Apple Silicon을 포함하며 설치 패키지 서명도 통과했다.
- 프로젝트 설정 14개와 Info.plist 5개의 빌드 번호를 85에서 86으로 올렸다.
  영속 스키마 V11·백업 package V10과 호환 식별자는 유지한다.

새 안내 문구의 시뮬레이터·실기기 화면과 VoiceOver 음성 검증은 수행하지 않았다.
기존 타이머·Focus 및 운영 인수의 남은 확인은 [문서 지도](../README.md#현재-상태)를 따른다.

## 소스와 증거

배포 시작 HEAD는 `7ad526dd784cf06393fb3d392af26b7dd43403d5`다. 안내 변경과 build 86 설정을
포함한 작업 폴더를 `.local/releases/build-86/source/`에 고정하여 archive를 생성했다.
업로드 완료 후 앱 소스·설정과 배포 기록을 같은 후속 커밋에 포함한다.
업로드 후 갱신한 문서는 앱 바이너리에 영향을 주지 않는다.

Git에서 제외된 `.local/releases/build-86/`에 소스 427개의 해시, 변경 patch, archive,
배포 패키지, 버전·서명·컴파일 소스·실행 파일 검증, 전체 회귀 로그와 업로드 결과를 보존한다.
Mac의 첫 export는 `PLA Update available`로 실패했으며 사용자가 계약 동의를 완료한 후 재시도에 성공했다.
첫 실패와 성공 재시도의 로그를 모두 보존한다. 커밋·푸시 후 SHA는 로컬 `release-status.json`에 기록한다.
테스트 안내 문구는 `testflight-notes-ko.txt`에 보관했다.
