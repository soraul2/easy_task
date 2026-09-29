# Dynamic Island 작업 진행 시간 멈춤 분석

분석일: 2026-09-29. 기준 소스: `688829a` / TestFlight 1.0(84).
요청의 “다이나믹디스플레이”는 iPhone Dynamic Island 및 같은 Live Activity의 잠금 화면으로 해석했다.
상태: 구현·격리된 시뮬레이터 검증 완료. iOS 27 실기기 최종 확인은 미완료이며 사용자 이슈 전체는 해결 완료로 표시하지 않는다. 후속 요청에 따른 [TestFlight 1.0(85) 업로드 기록](../../releases/TESTFLIGHT_BUILD_85.md)을 별도로 남겼다.

## 수정 전 분석과 증거 수준

일반 Task에서 재현한 원인은 진행 작업의 시간을 **시스템 타이머가 아닌, TimelineView에서 계산한
문자열로 표시하는 구현**이다. Live Activity에서 이 클로저가 매초 실행된다는 보장이 없으므로
이전 숫자가 남고, 나중에 다시 렌더링될 때 그 시점의 경과 시간으로 뛰는 현상을 설명한다.
코드·공식 문서 대조에 더해 iOS 27.0/26.5 시뮬레이터에서 재현했다. 사용자가 보고한
실기기의 발생 순간이나 Focus 증상까지 확정한 결과는 아니다.

| 구분 | 확인 내용 |
|---|---|
| 수정 전 코드 | 일반 Task는 `TimelineView(.periodic(from: .now, by: 1))` 안에서 `Text(String)`을 생성한다. 초 단위 시스템 타이머 Text가 아니다. |
| 수정 전 코드 | Focus는 `Text(timerInterval:…, countsDown: true)`를 사용한다. 일반 Task와 표시 갱신 방식이 다르다. |
| 수정 전 코드 | 같은 시간 컴포넌트가 Dynamic Island compact·minimal·expanded 및 잠금 화면에 사용된다. |
| 이력 정정 | 배포 문서에는 build 57부터 TimelineView·수동 문자열 표시가 기록되어 있다. Git에서는 해당 변경이 `8318d8b`(2026-09-01, build 60) 커밋에 묶여 있다. build 84에도 이 경로가 남아 있었다. |
| 증상과 부합하는 추론 | 정지해 있던 숫자가 Activity 상태 변경이나 시스템의 화면 재생성 때 현재 경과 시간으로 한 번에 바뀐다. |
| 사용자 확인 | iOS 27.0, 화면이 켜진 상태에서 다른 앱을 사용하는 동안 일반 Task와 Focus 모두 멈춤을 경험했다. 기기 모델·OS 세부 빌드·발생 순간 로그는 미확인이다. |

## 1. 수정 전 표시 경로

[`PlanBaseTaskLiveActivity.swift`](../../../mobile/Widget/PlanBaseTaskLiveActivity.swift)의
`TaskLiveActivityTimeText` 일반 Task 분기(분석 당시 190~197행)는 다음 구조다.

```swift
TimelineView(.periodic(from: .now, by: 1)) { timeline in
    Text(Self.elapsedText(startedAt: state.elapsedTimerStartedAt, now: timeline.date))
}
```

`elapsedText`가 반환한 `"12:34"`는 계산 시점의 일반 문자열이다. 타이머 시작 날짜를 가진
Text와 달리, 이 문자열 자체에는 시간에 따라 증가하는 동작이 없다. `.periodic(..., by: 1)`의
설정만으로 Live Activity 확장이 계속 실행되는 것은 보장되지 않는다.

Apple은 위젯 확장이 항상 실행되지 않으므로 시스템이 뷰를 대신 표시한다고 설명하고,
앱/확장이 실행되지 않을 때도 증가하는 시간 표시에는 날짜 기반 Text를 제시한다.
Live Activity 콘텐츠 갱신은 ActivityKit의 update 또는 push를 사용한다.

- [Apple: Displaying dynamic dates in widgets](https://developer.apple.com/documentation/widgetkit/displaying-dynamic-dates)
- [Apple: Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Apple: Text timerInterval](https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:))

위 문서의 플랫폼 동작과 현재 구현을 대조하여 내린 진단이다. 문서가 이번 앱의 실기기 증상을
직접 검증한 것은 아니다.

## 2. 가끔 동기화되는 것처럼 보이는 이유

[`TaskLiveActivityCoordinator.swift`](../../../mobile/App/Infrastructure/TaskLiveActivityCoordinator.swift)
86~104행은 과거 누적 시간과 현재 구간을 합쳐 `elapsedTimerStartedAt`을 만든다.
현재 구간의 시작이 미래가 아닌 정상적인 경우 수식은 다음처럼 정리된다.

```text
기준 시각 = 현재 시각 - (과거 누적 시간 + 현재 시각 - 이번 시작 시각)
          = 이번 시작 시각 - 과거 누적 시간
```

예를 들어 이전에 20분 작업하고 14:00에 재개했다면 기준 시각은 13:40이다.
14:05에 계산하면 25분, 14:06에 계산하면 26분이다. 기준 시각은 매초 동기화할 필요가 없다.
문자열을 다시 계산할 기회가 없으면 화면의 25분은 멈춰 있고, 나중에 렌더링될 때 26분이 된다.
실제 측정값이 아닌 코드 동작 설명용 예시다.

[`MobileAppRootView.swift`](../../../mobile/App/MobileAppRootView.swift)는 앱 활성화,
작업 변경 알림, 테마·날짜·시간대 변경 등에 Coordinator를 호출한다. CloudKit import 후에도
`CloudKitSyncService.reconcileIfNeeded` → `PersistenceCommandService`의 변경 알림 →
Coordinator 재계산 경로가 존재한다. 단, Coordinator는 **ContentState가 실제로 다를 때만**
`Activity.update`를 호출한다(126행). 따라서 동기화가 있을 때마다 숫자가 갱신되는 것은 아니다.

시간의 원천은 매초 수신하는 서버 데이터가 아니라 로컬 날짜와 진행 이벤트다.
이번 증상은 표시 갱신 정체로 설명되지만, 이것만으로 사용자의 누적 기록이 항상 정상이라고
단정할 수는 없다. 진행 이벤트가 아직 도착하지 않은 동안 `task.updatedAt`을 대신 사용하고,
이후 이벤트가 도착하면 기준 시각이 보정되는 경우는 별도 점검 대상이다.

## 3. 영향 범위와 기존 검증의 빈틈

- 일반 `doing` Task: Dynamic Island의 세 크기 및 잠금 화면에 공통 영향 가능.
- `todo`: 시간 대신 “할 일”을 표시하므로 이 증상의 대상이 아니다.
- Focus: 시스템 countdown Text 경로이므로 같은 코드 원인의 대상은 아니다. 별도 OS 동작까지
  모두 정상임을 검증한 것은 아니다.
- build 84의 캘린더 추천 변경에서 새로 발생한 코드가 아니다. 배포 문서상 build 57부터
  남아 있던 회귀 지점이다(Git에서는 build 60 커밋에 포함). 실제 사용자 최초 발생 빌드는 알 수 없다.
- 기존 Live Activity 상태 테스트는 payload 호환성·상태 분기, UI 테스트는 카드 생성·선택·
  시작·완료와 버튼을 확인한다. **상태 업데이트 없이 앱을 배경에 둔 동안 일반 Task 숫자가
  연속 증가하는지**를 비교하는 검증은 없다. 따라서 기존 테스트 통과로 이 문제를 배제할 수 없다.

## 4. 최초 분석에서 제안한 개선 방향

1. 일반 Task 시간도 기존 `elapsedTimerStartedAt`을 사용하는 시스템 timer Text로 바꾼다.
   `Text(startedAt, style: .timer)` 또는 유효한 구간과 `countsDown: false`를 사용하는
   `Text(timerInterval:…)`가 후보이며, 후자는 상한에서 멈추지 않도록 구간 정책을 정해야 한다.
2. 기존 누적 시간·일시정지·재개 의미와 payload 키 `updatedAt`의 호환성을 유지한다.
   영속 모델 변경이나 CloudKit schema 변경은 필요하지 않다.
3. 숫자를 수동 문자열로 다시 바꾸지 않고 시스템 타이머를 유지한 상태에서 폭·정렬을 조절한다.
   현재 compact 50pt·minimal 32pt·expanded 72pt에서 `59:59 → 1:00:00`, 10시간 이상 누적,
   긴 제목과 접근성 크기의 잘림을 확인한다. 접근성 값도 정지된 문자열로 덮지 않도록 한다.
4. Activity 업데이트는 작업 상태·선택·누적 기준 시각 변경에 사용한다. 초 단위 화면 숫자를
   만들기 위해 서버 동기화, 매초 저장 또는 Activity.update 호출 주기를 늘리지 않는다.
5. 화면이 켜진 정상 밝기와 Always-On 저휘도 상태를 구분해 검증한다. Apple은 Always-On에서
   애니메이션을 수행하지 않는다고 명시하므로 모든 화면 상태에서 매초 시각적 갱신을 보장한다고
   안내하지 않는다. [Apple의 애니메이션 제약](https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities)

## 5. 수정 후 필요한 재현·완료 기준

- 메모리 fixture로 일반 Task를 시작하고 홈 화면 또는 다른 앱에서 60초 이상 관찰한다.
  Activity 콘텐츠 업데이트가 없는 동안 숫자가 증가해야 한다. 화면을 다시 열어서 바뀐 숫자만
  확인하는 테스트로 대체하지 않는다.
- 같은 조건의 Focus countdown을 비교군으로 확인한다.
- Dynamic Island compact·minimal·expanded 및 잠금 화면을 각각 확인한다.
- 과거 누적 구간이 있는 Task의 재개, 작업 변경, 완료 후 다른 작업 전환을 확인한다.
- 1시간·10시간 자리수 경계와 VoiceOver 값, 저전력·저휘도 상태를 별도로 기록한다.
- 테스트 앱은 사용자 저장소·CloudKit에 연결하지 않는다. 실기기에서 화면 연속 갱신은 별도로
  확인하고, 시뮬레이터나 정적 스크린샷만으로 실기기 통과로 기록하지 않는다.

## 수정 전 분석에서 수행한 검증

소스·Git 이력·기존 테스트 범위를 확인하고 Apple 공식 문서를 대조했다.
`swift test --filter 'taskProgress|sameTimestampProgress'`의 관련 공통 테스트 5개가 통과했다.
이는 상태 전환·누적 계산·문자열 규칙 검증이며 Dynamic Island 실시간 갱신 검증이 아니다.
로그는 `.local/dynamic-island-task-timer-2026-09-29/progress-tests.log`에 보존한다.
앱 실행·실제 사용자 데이터/CloudKit 접근·실기기 화면 재현·소스 수정·추가 업로드는 수행하지 않았다.


## 구현 결과

- 일반 Task의 `TimelineView + Text(String)`을 상한 없는 `Text(startedAt, style: .timer)`로 변경했다.
- Focus 실행/휴식은 phase 시작 시각부터 deadline까지의 고정 구간을 전달한다. 본문에서
  `Date.now`로 구간을 재구성하지 않는다. 시스템 countdown이 종료 시각에서 0으로 멈춘다.
- 일시정지는 저장된 잔여 시간을 올림하여 `Text(Duration, format: .time(pattern: .minuteSecond))`로
  표시한다. 사용자 정의 formatter는 추가하지 않았다.
  [Apple Duration.TimeFormatStyle](https://developer.apple.com/documentation/swift/duration/timeformatstyle)
- 부분 Focus 정보, 잘못된 revision/phase/run state, 누락·역전·비유한 종료 시각,
  잘못된 잔여 시간은 `—` 및 접근성 `시간 확인 필요`로 표시하고 DEBUG 진단에 남긴다.
- `TaskActivityTimerPresentation`과 `TaskActivityTimerIdentity`는 비영속 내부 값 타입이다.
  식별자는 작업/세션·revision·시간 상태로 구성하며 제목·진행 개수·테마 변경만으로 재생성하지 않는다.
- 동일한 동적 Text를 접근성 값에도 사용한다. 숨긴 overlay, clipping, `.fixedSize()`,
  초 단위 저장·네트워크 요청·Activity 업데이트 루프를 추가하지 않았다.
- compact 50pt·expanded 72pt·minimal 32pt 폭을 유지했다. iOS 27 가로 화면도 사용하는
  minimal 시간 글꼴은 7pt bold와 기존 최소 축소 비율로 조정하여 10시간의 초까지 표시한다.
  작은 슬롯에서 글씨가 작아지는 절충이 있으므로 실기기 가독성은 추가 확인 대상이다.
- payload `updatedAt`, 영속 모델, CloudKit, 기존 누적 계산·Focus 종료/기록 정책은 유지했다.
  구현·검증 단계에서는 배포 번호 1.0(84)를 유지했고 추가 TestFlight 업로드·commit·push를 수행하지 않았다.
  이후 별도의 사용자 배포 요청으로 1.0(85)를 업로드했다. 배포 결과는 위 연결 문서를 따른다.

### 검증 환경과 격리

Xcode 26.6 (17F113), iPhone 17 Pro Simulator의 iOS 27.0 (24A434) 및
비교 환경 iOS 26.5 (23F77)를 사용했다. `--ui-testing` 메모리 저장소와 프로세스별 임시
Focus snapshot만 사용했다. 실제 사용자 저장소·CloudKit에 연결하지 않았다.
연결 가능한 실기기가 없어 사용자가 보고한 기기의 모델·세부 OS 빌드·실기기 증상은 미확인이다.

DEBUG `--ui-testing-live-timer-audit`는 일반 Task, Focus, 휴식 fixture를 만든다.
`--ui-testing-live-timer-mode=focus|break`, `--ui-testing-live-timer-elapsed=<seconds>`로
상태와 장시간 표시를 선택할 수 있다. 테스트 Activity만 잠금 화면에 같은 payload의
장식 없는 Native control을 함께 표시한다. UI 감사는 `PLANBASE_WIDGET_UI_AUDIT=1`일 때만 실행한다.

두 Live Activity가 함께 표시되는 실제 minimal 슬롯은 Debug 앱의 로컬 사본을 별도 simulator
bundle `com.soraul2.easytask.timeraudit`로 설치해 검증했다. 비교 앱 역시 메모리 fixture만 실행했고,
검증 로그를 보존한 뒤 제거했다. 저장소의 앱 식별자·프로젝트 설정은 바꾸지 않았다.
`PLANBASE_TIMER_CONTROL_APP`이 없으면 해당 UI 감사는 skip되므로 일반 UI 테스트 통과와 구분한다.

앱 임시 디렉터리의 `planbase-live-timer-audit.jsonl`에는 Activity ID, 타이머 종류,
기준·종료 시각, revision, 실행 상태와 실제 request/update 호출 시각을 기록한다.
작업 제목·메모는 기록하지 않는다. `unchanged`는 조회가 있었지만 Activity를 갱신하지 않았다는 뜻이다.

### 수정 전후 관찰

각 관찰 구간은 앱을 백그라운드에 둔 상태로 화면을 계속 녹화했다. 화면 재진입 순간의
숫자만 비교하지 않고 비디오의 여러 프레임, 0/10/30/60초 접근성 값, payload와 API 호출 로그를 대조했다.
아래 수치는 접근성 스냅샷 기준이며 영상 프레임 추출 시점과 1초 이내 차이가 있을 수 있다.

| 환경/상태 | 관찰 결과 | 관찰 중 Activity request/update |
|---|---|---|
| 수정 전 iOS 27 일반 Task | `02:00` 고정. 같은 payload의 Native control은 계속 증가 | 0회 |
| 수정 전 iOS 26.5 일반 Task | 동일하게 `02:00` 고정, Native control만 증가 | 0회 |
| 수정 전 Focus, 두 OS | 기본 timer와 동일하게 감소. 보고된 Focus 멈춤은 재현하지 못함 | 0회 |
| 수정 후 일반 Task, 두 OS, compact | 60초 동안 `2:04 → 3:04` | 0회 |
| 수정 후 일반 Task, 두 OS, 잠금 화면 | 60초 동안 `3:10 → 4:10` | 0회 |
| 수정 후 iOS 27 휴식 compact | 60초 동안 `2:55 → 1:55` | 0회 |
| 수정 후 iOS 27 휴식 종료 | `0:48 → 0:00`, 이후에도 0 유지 | 0회 |
| 최종 iOS 26.5 Focus compact / 잠금 화면 | 각각 60초 동안 `4:55 → 3:55` / `3:49 → 2:49` | 0회 |
| 최종 iOS 26.5 Focus 일시정지 | 저장된 값 `2:47`을 30초 동안 유지 | 0회 |
| 최종 iOS 26.5 Focus 재개 | 60초 동안 `2:46 → 1:46` | 0회 |
| 최종 iOS 27 Focus compact / 잠금 화면 | 각각 60초 동안 `4:56 → 3:56` / `3:50 → 2:50` | 0회 |
| 최종 iOS 27 Focus 일시정지 | 저장된 값 `2:46`을 30초 동안 유지 | 0회 |
| 최종 iOS 27 Focus 재개 | 60초 동안 `2:44 → 1:44` | 0회 |
| 최종 iOS 27 minimal, Task / Focus 동시 표시 | 60초 동안 `10:00:12 → 10:01:12` / `4:54 → 3:54` | 0회 |

진행 중 60초 구간의 변화량 오차는 1초 이내였고, 접근성 값과 payload 기준 현재 시간의
차이도 1초 이내였다. 종료 시각 도달은 0으로 제한하여 비교했다.
1초 간격으로 Activity를 갱신하거나 Activity를 재생성하는 우회책은 사용하지 않았다.

일반 Task의 `59:59 → 1:00:00`, `9:59:59 → 10:00:00` 전환을 비디오 연속 프레임에서
확인했다. compact와 expanded 모두 초가 잘리거나 말줄임되지 않았다. 긴 제목은 기존 정책대로
별도로 말줄임하며 시간 영역은 유지했다.

minimal 및 Safari가 전면인 가로 화면의 최초 영상에서는 `10:0…` 말줄임을 발견했다.
중간 시도의 폭 40pt·9pt 글꼴은 시스템 슬롯 경계에서 마지막 숫자가 잘려 채택하지 않았다.
최종 32pt·7pt 구성의 XCTest 첨부 화면과 녹화에서는 가로 `10:00:13`, minimal `10:01:12` 및
Focus `3:54`의 모든 숫자가 보였다. 최종 증거는 `narrow-final-ios27` 자료다.
`final-ios27`의 minimal/가로 및 `narrow-layout-ios27` 자료는 수정 과정의 실패 증거로 보존한다.
expanded는 자리수·배치 확인을 수행했으며 별도의 무조작 60초 연속 관찰은 수행하지 않았다.

1차 구현의 일시정지에서 과거 날짜 구간과 `pauseTime`을 사용했을 때, 실제 payload에 잔여 시간이
있어도 화면은 `0:00`을 표시했다. 이를 최종 결과로 인정하지 않고 저장된 Duration 표시로
수정했다. UI 테스트에 일시정지 직전 값과의 비교 및 30초 후 동일 값 어설션을 추가했다.
`after-ios*` 자료의 일시정지 부분은 이 발견의 기록이며 최종 통과 증거는 `final-*` 자료다.

### 테스트와 증거 파일

산출물 루트: `.local/dynamic-island-task-timer-2026-09-29/` (Git에는 넣지 않는 로컬 검증 자료).

- 공통 관련 테스트 19개 통과: `related-core-tests.log`.
- 전체 게이트 `./scripts/verify-platform-builds.sh` 통과: `platform-verification.log`.
  Debug 511개·Release 507개 패키지 테스트, iOS/macOS Debug·Release 빌드,
  내장 Watch 앱·Watch/iOS/macOS 위젯 및 privacy manifest 검증을 포함한다.
- 모바일 상태 테스트 12개는 iOS 27.0 및 26.5에서 모두 통과했다: 기존 payload/키 호환, 고정 구간, pause/resume identity,
  부분·잘못된·비유한 값, 장시간 시작 시각과 표현 타입의 비저장 여부를 검증한다.
- 기존 공통 테스트의 누적 구간 재개·같은 시각의 진행 이벤트·Focus stale revision 거부도
  관련 테스트와 전체 게이트에서 확인했다. 과거 누적 구간 재개를 실기기 UI에서 새로 검증한 것은 아니다.
- 일시정지 표시 수정 후 iOS Debug 재빌드와 Release 추가 빌드를 수행했다:
  `final-build.log`, `final-audit-build.log`, `release-final.log`.
- 최종 minimal 글꼴 조정 후 iOS Debug·Release 빌드도 통과했다:
  `narrow-final-debug.log`, `narrow-final-release.log`. 공통 코드·공개 API·프로젝트 설정 변경이 없는
  마지막 글꼴 변경 때문에 전체 패키지 게이트를 반복 실행하지는 않았다.
- iOS 27 최초 화면 감사 5개 및 iOS 26.5 감사 2개가 실행 완료되었다. 일반 Task/휴식/장시간
  영상은 유효하지만 최초 일시정지 화면은 위 실패 기록으로 분리한다. 기존 `todo → 시작 → 다음 → 완료 → 종료`
  UI 회귀도 iOS 27에서 통과했다.
- 일시정지 수정 후 Focus 연속 감사는 두 OS에서 다시 통과했고, 마지막 minimal·가로 감사 2개도
  iOS 27에서 통과했다. 감사 테스트의 실행 성공 외에 실제 첨부 이미지·영상과 호출 로그를 검토했다.
- 원본 연속 녹화: `baseline-ios27.mp4`, `baseline-ios26.mp4`, `after-ios27.mp4`,
  `after-ios26.mp4`, `final-focus-ios26.mp4`, `final-ios27.mp4`, `narrow-final-ios27.mp4`.
- XCTest `.xcresult`와 `*-attachments/`에 스크린샷·접근성 계층을 보존했다.
  `*-audit.jsonl`, `*-observations.json`, `*-validation.jsonl`, `*-video-values.txt`에
  호출 시각, 화면 값, payload 비교와 영상 프레임 판독 결과를 보존했다.
- 빠른 비교: [수정 전 60초 영상](../../../.local/dynamic-island-task-timer-2026-09-29/task-before-ios27-60s.mp4),
  [수정 후 60초 영상](../../../.local/dynamic-island-task-timer-2026-09-29/task-after-ios27-60s.mp4).
- 최종 화면: [iOS 27 가로 10시간](../../../.local/dynamic-island-task-timer-2026-09-29/narrow-final-ios27-attachments/836296C3-46A3-4359-8F0F-DE8A295869E8.png),
  [두 Activity 최소 표시](../../../.local/dynamic-island-task-timer-2026-09-29/narrow-final-ios27-attachments/5EC9BFC9-8947-4E45-9123-D16BD4EC3668.png).

모바일 상태 테스트 최초 실행은 테스트 시작 이전에 멈췄다. 호스트의 성능 측정용
`libRPAC.dylib`/`PERFC_*` 주입 환경과 XCTest bundle 주입이 함께 들어간 상태였고,
프로세스 샘플에는 XCTest가 로드되지 않은 앱 이벤트 루프만 확인되었다.
로컬 `.xctestrun` 사본과 해당 실행 명령에서 성능 측정용 환경만 제외하여 같은 바이너리를 검증했다.
프로젝트/배포 설정은 변경하지 않았으며 중단한 시도는 통과로 계산하지 않았다.

### 완료 판정의 한계

일반 Task의 문자열 표시 멈춤은 두 OS의 시뮬레이터에서 재현·수정 확인했다.
Focus는 원래 시스템 타이머도 정상 감소했으므로 사용자 실기기의 Focus 멈춤 원인은 아직 확정하지 못했다.
현재 증거로 iOS 27 전체의 시스템 타이머 결함이라고 주장할 수 없다.

iOS 27 실기기의 일반 Task와 Focus 연속 갱신 확인 전에는 사용자 이슈 전체를 최종 해결로 표시하지 않는다.
실기기 모델·OS 세부 빌드, VoiceOver 실제 음성, 저전력·Always-On 저휘도/깨우기 동작은 미검증이다.
접근성 트리의 동적 값 확인은 실제 VoiceOver 음성 검증을 대체하지 않는다.
과거 AOD 표시 문제 때문에 수동 문자열로 바꿨던 이력도 있으므로 AOD 회귀 확인은 유지해야 한다.
상태 변경 없는 관찰 구간에서 Activity 호출이 없음을 로그로 확인했고, 초 단위 저장·네트워크
루프가 추가되지 않았음을 코드로 확인했다. 별도 네트워크 패킷 캡처·전력 계측은 수행하지 않았다.
