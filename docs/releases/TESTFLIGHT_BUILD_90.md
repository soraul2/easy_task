# TestFlight 1.0 (90) — 업로드 완료

watchOS 10·Apple Watch SE 1세대를 위한 iPhone 연동 모드를 포함한다.
앱·위젯·Watch 빌드 번호는 모두 90이며, 검증한 소스 499개와 빌드 입력 417개를
`.local/releases/build-90/source/`에 고정했다. 시작 HEAD는 `d09d431`이며,
이번 호환 변경은 아직 별도 commit·push하지 않은 작업 폴더 변경이다.

## 포함한 변경

- watchOS 10: iPhone에서 오늘 목록을 받고 작업 추가·상태 변경·집중 기록을 전송한다.
- 오프라인 변경을 원자적 로컬 파일에 보관하고, iPhone 저장 확인 후 대기 목록에서 제거한다.
- 재전송 중복 방지, 오래된 화면의 변경 충돌 보호, 완료 날짜·집중 기록 보존을 적용했다.
- watchOS 11 이상: 기존 SwiftData·CloudKit 독립 실행 경로를 유지한다.
- 기존 스키마 필드·인덱스·마이그레이션과 앱·CloudKit·App Group 식별자는 유지한다.

## 검증

- 연동 기능 테스트 10개 통과.
- 공통 Debug 703통과·36skip / Release 698통과·10skip, 실패 0.
- 전체 플랫폼 게이트 exit 0: iOS·macOS 및 내장 Watch 앱·위젯 Debug/Release 빌드와
  번들·privacy manifest 검증 완료. 이후 코드 변경 없이 빌드 번호만 89→90으로 올렸다.
- Watch 실기기 대상 Debug/Release 컴파일, 최소 OS 10.0 및 `arm64_32`·`arm64` 확인.
- watchOS 26.5·SE 2 40mm 시뮬레이터에서 강제 연동 모드의 작업 시작과 집중 타이머
  시작·일시정지·종료를 확인했다. 기존 독립 경로의 오늘 목록과 Focus 진입도 확인했다.
- iOS·macOS Release archive와 App Store 배포 패키지의 총 6개 번들에서 1.0(90),
  strict 서명, device 플랫폼, privacy manifest, Production CloudKit/APS와 App Group을 확인했다.
  전체 entitlements는 정상 업로드된 build 89와 일치한다.
- 최종 Watch 앱·컴플리케이션의 최소 OS 10.0과 `arm64_32`를 확인했다. watchOS 11 전용
  SwiftData Index 참조는 weak link다. 배포 실행 파일 UUID는 archive와 일치하고
  Debug 전용 호환 모드·fixture 입력어는 포함되지 않는다.
- 실제 컴파일된 iOS 224개·macOS 213개 Swift 소스와 빌드 입력 417개가 고정 소스 및
  작업 폴더와 일치한다. macOS는 Apple Silicon·Intel을 함께 포함한다.

실제 SE 1·watchOS 10 설치, iPhone과 WatchConnectivity 왕복, 손목을 내린 상태의 종료
알림·햅틱은 미확인이다. [SE 1 실기기 확인 순서](../WATCHOS.md)를 따른다.

## 업로드 상태

| 플랫폼 | 업로드 완료 시각(KST) | Delivery ID |
|---|---|---|
| iOS·iPadOS·watchOS | 2026-10-03 23:48:07 | `19d25dfd-4811-44d8-b467-551534e3aaac` |
| macOS | 2026-10-03 23:47:08 | `84417180-cbc2-4248-9a8f-9355c6205047` |

두 플랫폼 모두 `Upload succeeded.`·`Uploaded package is processing.`·`EXPORT SUCCEEDED`
및 exit 0를 확인했다. Apple 패키지 처리 시작까지 확인했으며, TestFlight 설치 가능 상태와
외부 테스트 심사·테스터 그룹 공개는 확인하지 않았다. 이미 수락된 빌드는 재업로드하지 않는다.
영수증과 소스·패키지 검증 근거는 `.local/releases/build-90/`에 보존한다.

## 한국어 테스트 안내 초안

Apple Watch SE 1세대용 watchOS 10 지원을 추가했습니다.
iPhone의 PlanBase를 먼저 열고 워치에서 오늘 작업 목록을 받아 주세요.
작업 추가·시작·완료, 연결 해제 후 재전송, 집중 타이머와 종료 알림을 확인해 주세요.
watchOS 11 이상은 기존 독립 동기화 방식을 유지합니다.

이 안내는 로컬 초안이며 App Store Connect 테스트 정보 입력이나 테스터 알림 발송을
완료했다는 뜻은 아니다.
