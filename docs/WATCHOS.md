# PlanBase watchOS 운영

## 범위

`PlanBase-watchOS`는 watchOS 10부터 설치할 수 있다. watchOS 11 이상에서는 같은 Apple ID의
private CloudKit 데이터베이스에서 V11 모델을 직접 여는 기존 독립 실행 경로를 사용한다.
watchOS 10(SE 1세대 포함)은 아래 iPhone 연동 모드를 사용한다. 이 호환 변경은
[TestFlight 1.0 (90)](releases/TESTFLIGHT_BUILD_90.md)에 포함해 업로드했다.
Apple 처리 시작까지 확인했으며 설치 가능 상태와 실제 SE 1 왕복은 확인 대기다.

watchOS 11 이상에서 제공하는 기능:

- 오늘 남은 작업·완료 작업과 겹치는 일정 요약
- 받아쓰기와 watchOS 텍스트 입력을 이용한 오늘 작업 빠른 추가
- `할 일 → 진행 중 → 완료`, 완료 작업 재개
- 미래 알림이 남은 작업의 완료 확인
- Watch가 독립적으로 소유하는 Task 기반 Focus 시작·일시정지·재개·종료와 5분 휴식
- Focus/휴식 종료 로컬 알림, 전환 햅틱과 `휴식 시작`·`계속 집중`·`집중 시작`·`5분 더 쉬기`
  빠른 동작
- `accessoryCircular`, `accessoryRectangular`, `accessoryInline`, `accessoryCorner`
  컴플리케이션의 활성 Focus 우선 표시

기록·회고, 메모, 템플릿, 백업, 첨부 이미지는 Watch MVP 범위에 포함하지 않는다.

## watchOS 10 iPhone 연동 모드

- 처음에는 연결된 iPhone에서 PlanBase를 열어 오늘 목록을 받아야 한다.
- 워치에는 오늘 작업 목록(최대 100개, 전송 크기에 따라 더 적을 수 있음)과 일정 10개를
  보관한다. 전체 당일 작업·일정 개수는 별도로 전달해 컴플리케이션에서 축소 집계하지 않는다.
  날짜가 지난 목록은 오늘 목록으로 표시하거나 수정하지 않는다.
- 작업 추가·시작·완료·재개는 워치의 원자적 JSON outbox에 먼저 저장한다. 화면에는
  `iPhone 반영 대기 N건`을 표시하고, iPhone의 저장 확인을 받은 명령만 대기 목록에서 뺀다.
- `WatchConnectivity`의 즉시 메시지와 순서가 유지되는 배경 전송을 이용한다. 배경 전송
  시각은 OS가 정하므로 연결되더라도 즉시 반영된다고 보장하지 않는다.
- iPhone의 `WatchCompanionService`는 기존 `PersistenceCommandService`와
  `TaskLifecycleService`를 통해 작업·완료 활동·진행 이벤트를 함께 저장한다.
- iPhone에서 먼저 바뀐 작업은 예상 상태/수정 시각을 비교해 거절한다. 변경된 미래 알림도
  다시 확인하게 한다. 거절된 명령과 입력 제목은 워치에 남기고 사용자가 확인한 뒤 지운다.
- 전송 명령 ID, 영속 수신 기록과 저장 전 표시로 재전송 중복을 방지한다. 프로세스가 저장
  도중 중단되어 결과를 확인할 수 없으면 데이터를 다시 생성하지 않고 확인 안내를 보낸다.
  30일이 지난 명령은 자동 적용하지 않는다.
- Focus 타이머는 워치 로컬에서 시작·일시정지·재개·종료·5분 휴식이 가능하다. 기존
  `FocusTimerRules`의 절대 시각 계산을 재사용하고, 종료 기록을 outbox와 같은 파일에
  저장한다. iPhone Focus 타이머를 원격 조작하지 않는다.
- 로컬 종료 알림과 네 가지 컴플리케이션을 지원한다. iCloud 반영은 iPhone을 경유한다.

```text
watchOS 10: WatchCompanionView / WatchCompanionController
  → App Group / WatchCompanion/state-v1.json (목록·대기 명령·활성 타이머)
  → WatchConnectivity
  → iPhone WatchCompanionBridge / WatchCompanionService
  → 기존 V11 SwiftData 저장 명령 → private CloudKit
```

패키지와 Watch 앱/위젯의 최소 OS는 10으로 낮추되, 기존 코어 API의 watchOS 11 경계를
`@available(watchOS 11, *)`로 명시한다. 이 주석은 기존 모델의 필드·인덱스·버전·마이그레이션을
바꾸지 않는다. watchOS 10 경로는 SwiftData 컨테이너를 열지 않으며, Codable 값과 순수
타이머 계산·위젯 snapshot API만 사용한다. watchOS 11 이상은 기존 저장소를 계속 연다.
OS 업그레이드 시 남아 있는 연동 모드 타이머는 먼저 끝내고, 미전송 명령은 계속 전달한다.

## SE 1세대 실기기 확인 순서

새 호환 빌드 배포 후 iPhone과 Watch를 모두 같은 최신 TestFlight 빌드로 업데이트한다.

1. iPhone에서 PlanBase를 열고 워치를 실행한다. `iPhone 연동 모드`와 오늘 목록을 확인한다.
2. 워치에서 구분 가능한 작업 하나를 추가하고, iPhone에 한 번만 생성되는지 확인한다.
3. 작업을 시작·완료하고 iPhone의 상태와 완료 날짜를 확인한다.
4. 워치의 연결을 잠시 끊고 작업을 추가한다. 앱을 닫았다 열어도 대기 건수가 남는지,
   재연결 뒤 iPhone에서 한 번만 반영되고 대기 건수가 줄어드는지 확인한다.
5. 5분 집중을 시작하고 일시정지·재개, 손목을 내린 상태의 종료 알림, 재실행 후 복원과
   iPhone 집중 기록 반영을 확인한다.
6. 워치 페이스에 컴플리케이션을 추가하고 표시 및 앱 진입을 확인한다.

다른 모델의 물리 기기 검증을 사용자에게 요구하지 않는다. watchOS 11 이상 경로는
시뮬레이터와 빌드로 회귀 확인하되, 이는 실제 기기의 배터리·햅틱·CloudKit 검증을 대신하지 않는다.

## 데이터 흐름

```text
PlanBase-watchOS
  → Focus/focus-active-v1.json (Watch 기기 로컬 활성 상태)
  → PlanBaseContainerFactory / EasyTaskSchemaV11
  → iCloud.com.soraul2.easytask private database
  → 종료된 FocusSession 동기화 + bounded 오늘 Task·Event query
  → WatchWidgetSnapshotStore
  → group.com.soraul2.easytask/WatchWidget/watch-widget-v1.json
  → PlanBaseWatchWidgetExtension
```

Watch 앱의 상태 변경은 다른 앱과 동일하게 `PersistenceCommandService.perform` 안에서
`TaskLifecycleService.applyStatus`를 호출한다. 따라서 완료 활동과 진행 이벤트도 같은 저장
명령에서 기록된다. CloudKit import 성공 뒤에는 공통 무결성 수렴을 다시 실행한다.

컴플리케이션 확장은 SwiftData나 CloudKit을 직접 열지 않는다. Watch 앱이 App Group에 쓴
당일 최소 요약만 읽으며, 앱 활성화·저장·CloudKit import 뒤 타임라인을 갱신한다. iPhone과
Watch의 App Group 디렉터리는 기기별 로컬 저장소이므로 각각의 앱이 자신의 snapshot을 쓴다.
따라서 iPhone에서 실행 중인 Focus를 Watch가 활성 타이머로 오인하거나 제어하지 않는다. Watch
타이머의 deadline은 매초 저장하지 않고 절대 시각에서 계산하며, 앱 재실행·scene 활성화와
CloudKit import 뒤 공통 `FocusSessionService`로 수렴한다.

## 배포 식별자

- Watch 앱: `com.soraul2.easytask.watchkitapp`
- Watch 컴플리케이션: `com.soraul2.easytask.watchkitapp.widget`
- Companion 앱: `com.soraul2.easytask`
- CloudKit/App Group: 기존 iOS·macOS 식별자를 그대로 사용
- 최소 watchOS: 10.0 (watchOS 10은 iPhone 연동 모드)

Watch 앱은 `PlanBase-iOS`의 `Watch/PlanBaseWatch.app`에 포함되고, Watch 앱 안에는
`PlanBaseWatchWidgetExtension.appex`가 포함된다. 앱 아이콘은 공용 `AppIcon`의 watchOS
1024px 마케팅 이미지를 사용한다.

## 검증과 출시 게이트

2026-10-03 watchOS 10 호환 변경의 로컬 검증을 완료했다.

- 새 연동 로직 테스트 10개 통과. 재시작 복원, 중복 수신, 충돌 보호, 완료 날짜와 집중 기록,
  전송 크기 제한 및 거절된 변경 보존을 확인했다.
- 공통 Debug 703개 통과·기존 제외 36개, Release 698개 통과·기존 제외 10개.
- 전체 플랫폼 게이트 exit 0: iOS·macOS 및 내장 Watch 앱·위젯 Debug/Release 빌드,
  번들 식별자와 privacy manifest 확인.
- Watch 실기기 대상 Debug/Release 컴파일, 앱·컴플리케이션 최소 OS 10.0,
  `arm64_32`·`arm64` 실행 파일 포함 확인. 기존 스키마·마이그레이션 본문은 가용성 표시를
  제외하면 변경 전과 동일하다.
- watchOS 26.5의 SE 2 40mm 시뮬레이터에서 연동 모드를 강제로 실행해 작업 시작,
  집중 시작·일시정지·종료와 작은 화면을 확인했다. 기존 독립 모드의 오늘 목록과
  Focus 진입도 확인했다. 이는 실제 SE 1 또는 watchOS 10 런타임 검증은 아니다.
- 실제 SE 1 설치, iPhone과 WatchConnectivity 왕복, 손목을 내린 상태의 알림·햅틱은
  새 빌드 배포 후 확인할 항목이다.

검증된 코드에서 배포용 빌드 번호만 89에서 90으로 올렸다. 서명된 최종 배포 패키지에서도
최소 OS와 SE 1 아키텍처를 확인했다. iOS·Watch 및 macOS 업로드 성공 결과는
[build 90 배포 기록](releases/TESTFLIGHT_BUILD_90.md)을 따른다.

Xcode의 Settings > Components에서 현재 SDK와 같은 watchOS Simulator runtime을 먼저
설치한다. 그 뒤 다음 전체 게이트가 iOS 앱 내부 Watch 번들·컴플리케이션의 bundle ID,
실행 파일과 privacy manifest까지 확인한다.

```bash
swift test --filter WatchWidgetSnapshotTests
./scripts/verify-platform-builds.sh
```

TestFlight 업로드와 실제 기기 인수 상태는 다음과 같다.

2026-09-29 [TestFlight 1.0 (84)](releases/TESTFLIGHT_BUILD_84.md)의 iOS 묶음에 Watch 앱과
컴플리케이션을 포함해 업로드했다. Apple 패키지 처리 시작까지 확인했으며 실제 Watch 설치와
기기 간 CloudKit 수렴은 아래 인수 항목으로 유지한다. 이 빌드는 공통 테스트와 전체 플랫폼
게이트를 통과했으며, Watch 실기기 계측은 수행하지 않았다.

- [x] iOS 앱, Watch 앱, iOS·Watch 위젯의 프로젝트 설정과 Info.plist 빌드 번호를 84로 통일
- [x] Apple Developer의 Watch 앱·위젯 App ID와 iCloud, CloudKit, App Group 권한 확인
- [x] Release archive의 iOS 앱 아래 `Watch/PlanBaseWatch.app`과 Watch 앱의 `PlugIns` 확인
- [x] `WKApplication`, companion ID, 네 번들의 배포 서명과 App Store Connect 업로드 확인
- [x] Watch Focus 화면·로컬 snapshot·종료 알림 빠른 동작·햅틱·컴플리케이션 연결과 simulator 빌드
- [ ] 실제 Apple Watch에서 iCloud 최초 가져오기, 오프라인 변경 후 iPhone/Mac 수렴 확인
- [ ] 실제 Apple Watch에서 wrist-down·재실행 뒤 Focus 복원, 종료 알림과 햅틱 확인
- [ ] 네 가지 컴플리케이션 family의 갤러리, 저휘도 화면, 긴 제목과 큰 글자 확인
- [ ] 미래 알림 작업 완료 후 iPhone의 로컬 알림 캐시 정리 확인

기존 자동 테스트는 Focus를 포함한 snapshot 규칙·저장소를 다룬다. build 84에서는 공통
패키지 Debug/Release 회귀와 플랫폼 빌드·Release archive의 서명과 구조·업로드를 확인했다.
실제 기기 CloudKit 수렴은 별도 출시 인수 게이트다. 공용 Focus 화면에 추가한 체크리스트는
iPhone·iPad·Mac 대상이며, Watch의 전용 Focus 화면에는 포함하지 않는다.
