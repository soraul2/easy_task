# 반응성 최적화 검증 기록

## 결과 요약 — 2026-09-04

확인한 병목의 수정과 iPhone·iPad 시뮬레이터 검증을 마쳤다. 접근 제약으로 Goal을
`blocked`로 전환한 뒤, 사용자의 USB 연결 확인으로 검증을 재개했다. Xcode 27에서
실기기 계측 연결이 복구됐고 macOS 직접 조작도 확인했다. 실기기 성능 비교 테스트는
실기기 전후 5개씩 모두 통과했다. 별도의 Instruments 전후 기록도 정상 완료했고,
단축어의 긴 화면 끊김 감소를 확인했다. 스크롤 결과는 측정 방법에 따라 방향이 달라
개선/악화를 확정하지 않는다. 100ms 초기 피드백은 미검증이므로 전체 Goal은 아직 완료하지 않는다.

아래 표는 iPhone 14 Pro 실기기 결과다. Mac 코어 측정만 별도 표시했다.

| 구간 | 느렸던 이유와 수정 | p50 전 → 후 | p95 전 → 후 |
|---|---|---|---|
| 준비된 저장소로 앱 재실행 | 같은 값을 다시 쓰던 무결성 검사 수정 | 16.155 → 1.953초 (88% 감소) | 18.506 → 1.965초 |
| 무결성 검사+저장 (Mac 코어) | SwiftData inout writeback 대신 값 비교 후 필요한 필드만 수정 | 20.961 → 1.801초 (91% 감소) | 21.067 → 1.810초 |
| 네 탭 이동의 앱 CPU | 빈 저장 알림의 후속 갱신 제거, 보드 목록 정렬 재사용 | 2.694 → 1.972초 (27% 감소) | 2.705 → 2.026초 |
| 단축어 입력·삭제의 앱 CPU | 후보마다 전체 목록을 검사하던 중복 계산 축소 | 6.097 → 1.258초 (79% 감소) | 6.707 → 1.414초 |
| 위/아래 스크롤 앱 CPU | 뚜렷한 개선 없음 | 1.852 → 1.861초 | 1.870 → 1.932초 |
| 스크롤 hitch ratio (최초 XCTest) | 최초 측정에서는 악화; 아래 Instruments 재검사와 방향이 다름 | 93.795 → 132.506ms/s | 113.596 → 146.573ms/s |

작업 3,000개/오늘 240개, 보관함 1,000개의 격리된 로컬 데이터 결과다.
CPU 시간은 동작 전체에서 앱이 계산에 쓴 시간이며 터치 후 첫 화면 반응 시간이 아니다.
앱 실행 평균은 16.980 → 1.952초, 단축어 CPU 평균은 6.102 → 1.249초다.
네 탭 CPU 평균은 2.693 → 1.970초지만 자동화 포함 전체 시간 평균은 6.697 → 6.702초로
거의 같았다. CPU 감소를 그대로 체감 전환 시간 감소율로 해석하지 않는다.
상세·집중 진입 CPU p50은 1.520 → 1.473초로 뚜렷한 개선을 주장하지 않는다.

| 기능 검증 | 결과 |
|---|---|
| iPhone 일반 UI 7개 | 회고 없는 활동·읽기 전용 작업 기록, 캘린더 추천/독립 복제, 집중 예상 시간·일시정지·재진입·휴식, 메모 탭/백그라운드 복귀, 정확/부분/없는 단축어 및 일반 입력, 상태 버튼 위에서의 스크롤 모두 성공 |
| iPhone 실기기 성능 5개 | 개선 전·후 각각 5개 모두 성공/실패 0; 시작, 네 탭, 스크롤, 상세/집중, 대용량 단축어 |
| iPhone 시뮬레이터 | 일반 UI 7개와 성능 5개 총 12개 성공 |
| macOS 직접 조작 | 작업 추가·보관함·단축어·30분 집중·완료 기록·메모 저장과 탭 복귀 확인 |
| iPad UI 5개 | 큰 글자 기록/집중/단축어, 가로·세로 네이티브 창, 중복 입력어 거부, 작업 완료와 알림 기록 보존 성공; 캡처 직접 확인 |
| 저장/이력 회귀 | 빈 알림 생략, pending edit 저장, 보관 날짜, 실패 시 rollback, 동일 ID 보드 복귀 후 새 진행 이벤트, 동일 값 검사 시 context clean 등 관련 8개 성공 |
| 전체 회귀 게이트 | 종료 상태 0. Debug 396개/Release 395개 성공; 선택 실행 벤치마크 3/2개 생략. iOS/macOS Debug·Release 및 내장 Watch/위젯 검증 성공 |
| 마지막 후보 UI 수정 후 | iOS 계측용 Release와 macOS 일반 Release 빌드 성공, 위 최종 UI 검증 수행 |

남은 확인: 실제 기기 Release의 100ms 초기 피드백. FPS/hitch 전후 기록은 확보했지만,
스크롤의 최초 XCTest 결과와 후속 Instruments 결과는 방향이 달라 뚜렷한 개선을 주장하지 않는다.
macOS 화면 직접 조작은 아래 USB 연결 후 검증에서 완료했다. 보드의 전체 템플릿 관찰과 기존 알림/Live Activity/위젯의 병합
경로는 확인했으나 별도 병목으로 입증되지 않은 부분은 변경하지 않았다.
실제 CloudKit 왕복·알림 전달·위젯 렌더링은 이 로컬 성능 검증의 성공 항목에 포함하지 않는다.
스키마 V1~V11, 호환 식별자, 백업 형식은 바꾸지 않았으며 실제 사용자 저장소에 진단 데이터를 넣지 않았다.

## 범위와 기준

- 기준 코드: `9c5a7df`, TestFlight 69와 같은 소스. 작업 브랜치: `codex/performance-responsiveness`.
- 터치 초기 피드백 목표 100ms. 전체 내용 로딩 시간 및 XCTest의 입력·idle 대기 시간을 포함하는 wall clock과 구분한다.
- 칸반/캘린더/기록/메모 전환, 상세 열기, 상태 변경, 일반/단축어 입력, 집중 모드, 스크롤, 복귀 및 첫 실행을 확인한다.
- 변경 전후 동일 설정/기기/데이터로 측정한다. 빌드와 측정을 동시에 실행하지 않는다.
- p50/p95, 메인 스레드 구간, 반복 호출, 프레임 끊김, CPU/메모리를 가능한 도구로 확인한다. 기능 테스트 통과를 성능 달성으로 간주하지 않는다.
- 실제 사용자 저장소 및 iCloud Drive에 접근하지 않는다. 격리된 로컬 fixture만 사용한다. 스키마/호환 식별자/백업과 저장 rollback 의미를 보존한다.

## 2026-09-04 환경 및 초기 조사

- macOS 26.6.2 (25G83), Xcode 26.6 (17F113), iOS Simulator 26.5.
- 측정 호스트: MacBookPro18,2 / Apple M1 Max / 32 GiB. 시뮬레이터 수치를 실기기 수치로 일반화하지 않는다.
- iPhone 14 Pro, iOS 27.0 (24A5370h): CoreDevice 연결/개발자 모드/DDI 호환 정상. Instruments에서는 offline.
- 실제 Time Profiler all-processes 3초 기록을 시도했으나 `Cannot record until the device is connected`로 실패. `.local/performance/baseline/device-availability.log`에 원문 보존. 실기기 계측은 아직 미검증이다.

## 검증할 가설

1. 양 플랫폼 탭 변경 → 보관 후보 조회 → 저장 명령 → 변경 없는 경우에도 갱신 알림. iOS에서는 알림/Live Activity 후속 작업으로 이어짐.
2. 보드의 전체 템플릿/항목 `@Query`와 반복된 보드 projection.
3. 저장/CloudKit/복귀 이벤트의 보조 작업 중복. 알림과 Live Activity에는 이미 재진입 병합이 있고 위젯 쓰기는 actor로 분리되어 있으므로, 기존 보호 장치를 확인하면서 측정한다.
4. 시작 시 무결성 검사 및 화면별 재진입 조회.

추가 코드 확인: 기록 화면의 저장 알림 수신 경로는 `isVisible`을 확인하지 않는다.
탭에서 벗어날 때 취소한 조회가 알림으로 다시 시작되는지는 프로파일에서 확인한다.
진행 시간 세션은 다시 활성화될 때 같은 ID 집합이면 기존 결과를 재사용하므로,
탭 변경 알림을 줄일 때 비활성 중 변경 내용이 누락되지 않는지도 회귀 검증한다.

## 계측 구성

- `PlanBasePerformanceTrace`: 저장 명령, 탭 보관 처리, 보드 projection, 보관함 로딩의 Instruments 구간. 작업 제목/본문/ID는 로그에 넣지 않는다.
- iOS 성능 fixture: 작업 3,000개(오늘 240개), 진행 이벤트 6,000개, 완료 기록 2,760개, 템플릿/항목 각각 1,000개, 캘린더 이벤트 180개, 메모 200개.
- `--ui-testing --ui-testing-performance`를 함께 지정한 Debug 조건 빌드만 전용 `ResponsivenessFixtures/v1.store`를 로컬로 연다. 일반 저장소와 CloudKit을 사용하지 않는다. 일반 데모 seed도 생략한다.
- Release 최적화를 유지하면서 테스트 hook을 사용하기 위해 `SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG ENABLE_TESTABILITY=YES`로 계측 빌드를 만든다. 배포용 Release와 완전히 같은 실행 환경은 아니며, UI testing에서 실제 시스템 알림 및 일부 외부 연동은 비활성이다.
- 초기 fixture 생성은 예열 단계에 포함한다. `testPreparedStoreLaunch`는 이미 준비한 파일 저장소로 프로세스를 다시 시작하는 측정이며, OS 디스크 캐시를 제거한 cold boot를 의미하지 않는다.
- `PlanBaseResponsivenessTests`: 반복 탭 전환/스크롤은 각각 10회, 저장소 준비 후 재실행은 5회. XCTClockMetric은 IPC/idle 대기를 포함하며 100ms 초기 피드백 판정에 사용하지 않는다. CPU/메모리/Hitch/스크롤 애니메이션 및 사용자 정의 구간을 별도로 수집한다.
- `scripts/summarize-responsiveness-metrics.py`가 원본 샘플과 평균/p50/nearest-rank p95를 JSON으로 보존한다. 표본이 작은 p95의 한계도 함께 기록한다.

## 진행 상태

- [x] 작업 상태 보존 및 기준 HEAD 확인.
- [x] 실제 기기 계측 연결 시도와 실패 증거 확보.
- [x] 변경 전 앱/코어 계측 및 재현 (실기기/프레임 계측 제한은 별도).
- [x] 확인된 병목 개선 및 동일 조건 재측정.
- [x] iPhone/iPad 동작 검증 및 전체 회귀 게이트.
- [x] macOS 직접 조작 (USB 연결 후 재개 턴에서 확인).
- [x] 실제 기기의 프레임/hitch 계측 및 전후 비교.
- [ ] 실제 기기의 입력 후 첫 화면 피드백 100ms 판정 (HID→표시 시점 연결 미확보).
- [x] 원인/변경/전후 수치/남은 제한 보고서 작성.

초기 성능 작업에는 push, 병합, TestFlight 업로드를 포함하지 않았다. 이후 사용자가
TestFlight 업로드를 별도로 요청해 아래 build 70 배포를 진행했다.

### 후속 접근 상태 확인

직전 Goal 턴은 코드 개선·전후 측정·회귀 검증을 완료한 progress 턴이다.
그 뒤 첫 자동 계속 턴에서 현재 상태를 다시 조회했다. 진행 중인 빌드나 측정 작업은 없었다.

- iPhone: CoreDevice 조회는 성공했고 localNetwork tunnel은 connected, 개발자 모드와
  DDI 서비스도 활성이다. 하지만 같은 시점의 Instruments 목록은 여전히 offline이다.
  원본 `.local/performance/frames/device-recheck.json`과 `.log`에 기록했다.
- 시뮬레이터 대안: `Animation Hitches` / All Processes / 10초 기록을 시도했다.
  도구가 `Hitches is not supported on this platform`으로 종료 상태 2를 반환했다.
  `.local/performance/frames/availability.log`와 오류가 포함된 `.trace`를 보존했다.
  이 파일을 성공한 프레임 계측이나 hitch 0회로 해석하지 않는다.
- macOS: 격리된 메모리 저장소 테스트 앱을 다시 띄웠다. 정상 크기의 창이 존재함을
  확인하고 창 복원 후 조회했지만, `permission_denied` / AX window reads blocked가
  재현됐다. 테스트 앱만 종료했으며 실제 설치 앱은 조작하지 않았다.

새 증거로 시뮬레이터 프레임 계측 대안의 미지원이 확인됐다. 남은 측정은 실제 기기의
Instruments 연결과 macOS 화면 도구 접근 복구가 필요하다. 같은 접근 조건이 원래
작업 턴과 이번 계속 턴에서 연속 확인됐지만, blocked 전환의 3개 Goal 턴 기준에는
아직 이르므로 Goal을 active로 유지한다. 기존 성능 결과와 구현은 변경하지 않았다.

두 번째 자동 계속 턴에서도 현재 상태를 재검증했다. 직전 턴은 시뮬레이터 Hitches
미지원이라는 새 증거를 얻은 progress 턴이며, 대기 중인 측정 프로세스는 없었다.
이번에도 `xctrace list devices`는 실제 iPhone을 Offline으로 반환했고, Simulator와
격리된 macOS 테스트 앱의 창 복원 후 조회는 모두 `permission_denied` 및 1,500ms
AX 읽기 차단으로 실패했다. 격리된 테스트 앱만 종료했다. 이미 허용으로 확인된
손쉬운 사용 설정을 다시 변경하거나 접근 제약을 우회하지 않았다.

현재 결과 파일도 다시 확인했다: `phone-final.xcresult` 11개, `shortcut-final.xcresult`
1개, `ipad-final.xcresult` 5개 모두 성공이며 실패/생략은 0개다. 전체 회귀 게이트의
기록된 종료 상태는 0, `git diff --check`도 성공했다. 추가 빌드나 벤치마크는 시작하지 않았다.

같은 실기기 계측·macOS 화면 접근 제약이 원래 작업 턴부터 이번 턴까지 3개 연속으로
확인되어 Goal을 `blocked`로 전환한다. 완료 판정은 하지 않는다. 재개 조건은 iPhone의
Instruments 연결 복구(우선 USB 연결 및 잠금 해제 확인)와 macOS 화면 접근 복구다.
재개 시 격리된 데이터와 같은 빌드 조건으로 초기 피드백/프레임 및 macOS 조작 검증을
이어가며, 이미 검증한 수치와 결과를 실기기 결과로 대체 해석하지 않는다.

### USB 연결 후 검증 재개 — 2026-09-04 20:01 이후

- CoreDevice에서 wired/connected, 부팅 후 잠금 해제 이력을 확인했다. 기본 Xcode
  26.6의 Instruments는 여전히 offline이었지만, 설치돼 있던 Xcode 27 beta 3
  (`27A5218g`)의 Instruments는 같은 iPhone을 정상 인식했다. 전역 Xcode 선택은
  변경하지 않고 명령별 `DEVELOPER_DIR`만 지정했다.
- Xcode 27의 `Animation Hitches` / All Processes / 5초 기록이 종료 상태 0으로
  완료됐다. `.local/performance/device/availability.trace` 및 `availability-toc.xml`에
  실제 iPhone 14 Pro / iOS 27.0 (`24A5370h`), 정상 종료 이유와 기록 구간이 남아 있다.
  이는 계측 가능성 확인이며 PlanBase 시나리오의 hitch/입력 반응 결과는 아니다.
- 기존 iPhone 앱 `com.soraul2.easytask` build 68을 확인했다. 이를 덮어쓰지 않도록
  별도 `com.soraul2.planbase.performance` / **PlanBase Perf** 앱을 준비했다.
  사본 프로젝트에서만 iCloud/App Group/push 권한과 Watch/위젯 포함 단계를 제거했고,
  실제 저장소의 프로젝트·호환 식별자·스키마는 변경하지 않았다. 서명 결과에는
  진단용 application identifier, team identifier, get-task-allow만 존재한다.
- `.local/performance/device/before-source`는 기준 HEAD `9c5a7df`에 동일한 테스트
  fixture/실행 진입점/데모 seed 생략/TabArchive 표식과 최신 UI 테스트만 붙인 사본이다.
  `after-source`는 현재 코드의 사본이며 모든 Swift 파일이 현재 저장소와 같음을 확인했다.
  두 사본과 SHA-256 manifest, `installation-safety.json`을 보존했다.
- Xcode 26.6의 첫 실기기 빌드는 프로비저닝 파일 경로 누락으로 실패했다. 이후 두
  비교 앱 모두 Xcode 27, Release 최적화, `SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG`,
  `ENABLE_TESTABILITY=YES`로 서명 빌드가 종료 상태 0을 반환했다. 실기기끼리 같은
  조건으로 비교하며 앞선 Xcode 26.6 시뮬레이터 숫자와 직접 비교하지 않는다.
  after 빌드에는 별도 unit-test 타겟의 `command failed with exit code 0` 메시지가 있어,
  앱/runner 생성·서명 확인 외에 실제 UI 테스트 결과까지 확인해야 한다.
- Mac은 현재 코드의 Debug 앱을 새로 빌드해 종료 상태 0을 확인했다. 격리된
  `--ui-testing` 메모리 저장소에서 일반 작업 추가, 상세 열기, 보관함 저장 및
  `/perf`·예상 30분 설정, 입력어+Enter로 새 작업 추가를 확인했다. 집중 모드는
  예상 30분으로 시작·일시정지·작업 완료가 동작했고, 실제 집중 17초와 진행/완료
  기록이 생성됐다. 기록 탭에 회고 없이 표시되며 읽기 전용 상세에 생성·진행·완료와
  집중 기록이 보였다. 캘린더·기록·메모·칸반을 이동하고, 메모 저장 후 탭 복귀에서
  같은 내용을 다시 열어 확인했다. `mac-*.json/png`에 조작 결과와 캡처를 보존했으며
  기록·집중 화면 캡처도 직접 확인했다. 테스트 앱 PID 85831만 종료했다.
- 20:19에 실제 iPhone의 before 성능 테스트 5개를 시작했다. 실행 도구가
  `Unlock iPhone to Continue`로 대기했고, 별도 lockState 조회도
  `passcodeRequired: true`를 반환했다. 테스트 프로세스 PID 90125가 살아 있음을
  확인했다. 20:21 잠금 해제 후 재개해 20:29에 5개 측정을 모두 통과했다.
  실행 로그: `.local/performance/device/before-phone.log`.

## iPhone 14 Pro 실기기 측정

Xcode 27 beta 3 / iOS 27 beta (`24A5370h`), Release 최적화와 DEBUG 테스트 hook.
위의 격리된 단일 앱 ID와 같은 파일 저장소를 사용했다. before 실행은 종료 상태 0,
5개 성공/실패 0/생략 0이며 원본은 `device/before-phone.xcresult`,
전체 샘플·평균·p50·p95는 `device/before-phone-metrics.json`에 보존했다.
후속 테스트도 `device/after-phone.xcresult`에서 같은 5개 시나리오가 모두 통과했다.
20:30에 실행했으나 잠금 상태로 대기했고, 사용자 잠금 해제 후 재개해 20:36 종료 상태 0을
반환했다. 측정 구간은 잠금 해제·설치 대기 시간을 포함하지 않는다.
후 샘플은 `after-phone-metrics.json`, 대응 비교는 `paired-phone-summary.json`이다.

| 측정 단위 | n | p50 전 → 후 | p95 전 → 후 |
|---|---:|---:|---:|
| 준비된 저장소로 프로세스 재실행 | 5 | 16.155 → 1.953 s | 18.506 → 1.965 s |
| 네 탭 이동 앱 CPU | 10 | 2.694 → 1.972 s | 2.705 → 2.026 s |
| 네 탭 이동 wall clock (자동화 포함) | 10 | 6.700 → 6.652 s | 6.737 → 6.987 s |
| 단축어 7자 입력·삭제 앱 CPU | 5 | 6.097 → 1.258 s | 6.707 → 1.414 s |
| 단축어 7자 입력·삭제 wall clock (자동화 포함) | 5 | 7.697 → 3.034 s | 8.325 → 3.268 s |
| 위/아래 스크롤 앱 CPU | 10 | 1.852 → 1.861 s | 1.870 → 1.932 s |
| 스크롤 구간 hitch ratio | 10 | 93.795 → 132.506 ms per s | 113.596 → 146.573 ms per s |
| 스크롤 구간 hitch 개수 | 10 | 19.000 → 23.000 hitches | 22.000 → 26.000 hitches |
| 상세·집중 열기/닫기 앱 CPU | 5 | 1.520 → 1.473 s | 1.533 → 1.487 s |

실기기에서는 스크롤 signpost 지표가 FPS 중앙값 67.18, hitch 평균 19.6회를
반환했으나 `XCTHitchMetric(application:)` 값들은 모두 0이었다. 같은 스크롤 지표의
Frame Count 역시 0이라 지표 사이의 불일치가 있다. 베타 도구 환경의 두 값을
임의로 합치거나 앱 전체가 hitch 0회였다고 해석하지 않고 별도 Instruments 기록으로
교차 확인한다. FPS의 p95는 느린 쪽 지표가 아니므로 지연 p95와 혼용하지 않는다.

`PlanBaseResponsivenessTraceTests`는 XCTest 성능 metric을 실행하지 않는 별도
Instruments 조작 드라이버다. 탭 12회, 단축어, 스크롤, 상세·집중, 백그라운드 복귀와
fixture 내용의 접근성 노출을 확인하고 단계별 시각을 JSON attachment로 남긴다.
이 단계 시각은 자동화·idle 대기를 포함하므로 터치 반응 시간으로 사용하지 않는다.
HID 입력과 표시 시점의 연결은 Instruments 원본으로 별도 검증한다.

### 별도 Instruments 기록

- `PlanBaseResponsivenessTraceTests/testInstrumentedInteractions`의 before 실행은
  실제 기기에서 1개 성공/실패 0, 종료 상태 0이다. 탭 12회에서 fixture 데이터 노출,
  단축어 입력·지우기, 스크롤 5회, 상세·예상 30분 집중 진입, 백그라운드 복귀를 확인했다.
  단계 시각 attachment는 `device/before-trace-attachments/`에 보존했다.
- 드라이버 추가는 두 소스 사본의 UI 테스트 파일에만 적용했다. 두 build-for-testing은
  종료 상태 0이다. 서명 후 앱 실행 파일 SHA-256은 바뀌었으나 빌드 작업 기록에는
  앱의 CodeSign만 있고 앱 재컴파일·재링크가 없다. dSYM은 각각 20:09/20:11 원본이며
  실행 파일 UUID와 일치한다. 이를 `trace-rebuild-tasks.json`,
  `trace-driver-build-provenance.json`, `trace-executable-provenance.json`에 보존했다.
- `after-attach-driver-build.log`의 UI 테스트 드라이버 재빌드도 종료 상태 0이다.
  앱 실행 코드는 변경하지 않고, 외부 profiler가 특정 앱 PID에 붙을 수 있도록
  UI 테스트에 선택적인 20초 대기 구간만 추가했다. 대기는 모든 interaction phase 밖이다.
  `run-attached-trace.py`는 실행 전에 이미 존재하는 앱 PID를 제외하고 새 테스트 앱만
  찾으며, 개선 후 기록은 `--attach <test-app-pid>` / 120초로 범위를 좁힐 예정이다.
  전체 기기 기록이 완료되지 않아 개선 전에도 같은 attach 드라이버를 빌드했다.
  양쪽 모두 fixture 로딩 후 같은 20초 대기를 제공하고 새 테스트 앱 PID에만 붙인다.
  정량 전후 비교의 현재 기준은 동일 조건으로 완료한 XCTest이며 상세 기록은 별도다.
- `before-interactions.trace`는 180초 기록 종료 뒤 kernel trace의 후처리가 진행 중이다.
  호스트 표본에서 `ktrace_stream_iterate_group` / `_session_process_events` 활동을
  확인했다. 약 12GB의 기록 파일이 생성됐고 후속 표본에서는 remote library signature와
  symbolication 처리로 단계가 바뀌었다. 잠금 상태도 false이다. 완료 전 TOC 내보내기 시도는
  `Document Missing Template Error` / 종료 상태 10으로 실패했으므로 완성된 trace로
  간주하지 않는다. 후처리가 25분 넘게 지속되어 SIGINT로 중단을 요청했고, 계속 살아 있어
  SIGTERM으로 진단 프로세스만 종료했다 (종료 상태 1). 이후 TOC 내보내기도 상태 10으로
  실패했다. 원본은 보존하지만 성능 근거로 사용하지 않는다. 변경 전/후 모두 앱에만
  붙는 방식으로 재시도한다. `before-wide-trace-interruption.json`에 경위를 남겼다.

Apple은 애니메이션 hitch와 입력 후 화면 반응 지연을 별개로 설명한다. 따라서
hitch 0회나 FPS만으로 100ms 목표 달성을 주장하지 않는다.
[Understanding user interface responsiveness](https://developer.apple.com/documentation/xcode/understanding-user-interface-responsiveness)

앱에만 붙는 첫 실행은 테스트 앱 PID 8366을 정확히 선택했고 조작 검사가 종료 상태
0으로 끝났다. 기존 앱 PID 7156은 프로파일 대상 선택에서 제외됐다. 두 사본의
준비 완료 표식/대기 구간 추가 빌드도 종료 상태 0이다. 동작 단계는
`before-attached-attachments/`의 JSON으로 보존했다. `--attach` 기록은 대상 앱의
종료를 인식해 종료 절차로 들어갔다. 이후 profiler가 종료 상태 2와 전송 파일 손상 오류를 반환했다. 아래에 별도 기록했다.

현재 보존된 격리 사본을 사용하는 재현 순서는 다음과 같다. 스크립트는 기존 결과를
덮어쓰지 않고 거부하므로 새 실행에서는 결과 접두사를 바꾼다. 일반 사용자 앱에 이
명령을 적용하지 않는다. profiler에는 fixture를 여는 테스트 앱의 새 PID만 전달한다.

```bash
# 먼저 서명된 before/after의 build-for-testing을 끝내고, 실행은 차례대로 한다.
python3 .local/performance/device/run-attached-trace.py before
python3 .local/performance/device/run-attached-trace.py after

DEVELOPER_DIR=/Applications/Xcode-27.0.0-beta.3.app/Contents/Developer \
  xcrun xctrace export \
  --input .local/performance/device/before-attached-interactions.trace \
  --toc --output .local/performance/device/before-attached-toc.xml
```

스크립트는 Xcode 27의 `PlanBase-iOS_PlanBase-iOS_iphoneos27.0-arm64.xctestrun`을
같은 Products 폴더의 별도 파일로 복사하고 runner 환경에
`PLANBASE_TRACE_ATTACH_DELAY_SECONDS=20`을 넣는다. fixture 로딩 완료 표식 후
새 테스트 앱 PID에 `Animation Hitches --attach <pid> --time-limit 120s`를 적용한다.
UI 테스트는 `PlanBaseResponsivenessTraceTests` 한 개만 선택한다. 기존 앱의 PID,
실행 앱 ID, 별도 저장소 확인과 원본 source/build manifest도 함께 유지한다.

### 전송 오류 후 프레임 중심 재시도

첫 app-only trace는 조작 검사 성공 뒤 대상 앱 종료를 감지했지만 profiler는
`Transferred trace file is malformed`와 종료 상태 2를 반환했다. 17MB 결과의 TOC는
열리지만 `hitches` table에는 행이 없었다. 이를 hitch 0회로 해석하지 않는다.
`before-attached-execution.json`, `before-attached-toc.xml`, `before-attached-hitches.xml`에
원본 상태를 보존했다.

후속 드라이버는 모든 조작 단계/attachment 작성 후 앱을 60초 더 열어두어 trace의
시간 제한 종료 및 전송이 대상 앱 종료보다 먼저 일어나도록 했다. 이 대기는 성능
phase 밖이며 배포 앱 코드에 들어가지 않는다. 양쪽 UI 드라이버 재빌드는 상태 0이다.
또한 기본 template의 전체 Time Profiler 수집을 빼고 공개 CLI가 제공하는
`Frame Lifetimes`, `Hitches`, `Hangs`, `Points of Interest`만 사용한다. 입력부터
화면 표시까지 연결되는 시스템 프레임 정보 때문에 이 네 계측기는 all-processes로
기록하되, 분석 대상은 fixture의 조작 구간과 테스트 앱이다. Hangs 문턱은 33ms,
Points of Interest의 일반 OS log 포함은 끈다. 앞선 넓은 기록과 같은 조건의 결과라고
주장하지 않으며, before/after 모두 이 동일 구성으로 실행한다.

```bash
python3 .local/performance/device/run-attached-trace.py before --mode frames
python3 .local/performance/device/run-attached-trace.py after --mode frames
```

### 프레임 드라이버의 입력/스크롤 분리

`before-frames-interactions.trace`는 120초 후 정상 종료(0)했지만 조작 드라이버는
상세 작업을 찾지 못해 실패(65)했다. 영상에서 스크롤 시점에 입력 후보와 키보드가
열려 있음을 확인했다. 이 실행의 스크롤은 일반 작업 목록 스크롤로 사용하지 않는다.
그 다음 `before-stable-frames-driver.xcresult`는 삭제 후 빈 입력 검증에서 실패했다.
영상 `before-stable-clear-failure.png`에서 `/pe`가 남아 있었다. profiler를 함께 실행한
개선 전 앱에서 삭제 7회가 모두 반영되지 않은 관찰이며, 입력 누락의 정확한 원인을
앱 또는 XCTest/OS 중 하나로 단정하지 않는다. profiler는 이 실행도 정상 종료(0)했다.

후속 드라이버는 탭→입력이 없는 작업 목록 스크롤→상세/집중→복귀→단축어 순서다.
입력을 마지막에 두어 남은 후보/키보드가 다른 단계에 영향을 주지 않게 하고,
삭제 후 실제 값과 `shortcutDeletionCompleted`를 JSON으로 보존한다. 앱 생산 코드는
바꾸지 않았으며 전후 모두 같은 테스트 파일로 재빌드한다. 이 기록은 기존 XCTest
정량 성능 테스트와 별도다. 기존 정량 검사의 다음 반복은 `/perf12` 정확 일치를
검증해 통과했으며, profiler 동시 실행에서 발생한 누락을 원래 측정으로 일반화하지 않는다.

공개 CLI 프레임 구성에서 앱 PID가 포함된 `hitches`와 `potential-hangs` 행을
확인했다. 이 구성에는 입력 dispatch와 첫 화면 표시를 잇는 HID table이 없으므로
100ms 초기 피드백 목표는 이 표만으로 판정할 수 없다. Instruments UI 접근도
손쉬운 사용 권한이 granted임에도 AX window 읽기가 막혔다. 기존 계측 결과는 유지한다.

### 순서를 분리한 최종 실기기 드라이버

`before-ordered-frames-driver.xcresult`와 `after-ordered-frames-driver.xcresult`는
각각 1개 성공/실패 0, 종료 상태 0이다. 양쪽 21개 단계가 기록됐고 마지막 단축어
입력·삭제의 `shortcutDeletionCompleted`는 모두 true다. 앞서 한 번 관찰한 `/pe`
잔류를 개선 전 앱에서 항상 재현되는 문제로 일반화하지 않는다.

개선 전 profiler는 정상 종료(0)했다. `before-ordered-summary.json`은 모든 단계가
trace 범위 안에 있음을 확인한 뒤 테스트 앱 PID 8504의 hitch/잠재 지연만 집계했다.
스크롤 5회의 누적 hitch 중앙값은 회당 342.0ms, 최댓값은 354.5ms이며 개별 hitch는
최대 20.85ms다. 단축어 단계는 누적 4,884.9ms, 개별 최대 2,067.1ms다. 33ms 이상
잠재 지연은 자동화의 접근성 snapshot 처리도 포함할 수 있으므로 터치 반응 지연으로
치환하지 않는다. `summarize-trace-phases.py`는 참조 ID를 해석하고 앱 PID/단계 구간을
확인하며, UI 드라이버와 profiler 모두 정상 종료했을 때만 요약을 생성한다.

개선 후 profiler도 정상 종료(0)했다. 라이브러리 정보 후처리가 오래 걸렸지만
기기 잠금 상태는 false였고, 완료 후 TOC와 두 table 내보내기 모두 정상 종료했다.
완료 전 TOC의 상태 10은 보존하며 완성 후 결과로 대체하지 않고 경위를 구분한다.
`after-ordered-summary.json`은 테스트 앱 PID 8518의 모든 21개 단계가 trace 범위 안에
있음을 확인한다. 최종 입력 삭제도 양쪽 모두 정상이다. 이 동안 생산 앱 코드는 추가로
바꾸지 않았고, 실제 사용자 앱 PID 7156은 유지했다.

| 별도 Instruments 비교 | 전 → 후 | 해석 |
|---|---|---|
| 단축어 입력·삭제 한 구간의 개별 최대 hitch | 2,067.1 → 25.0ms | 긴 화면 끊김 감소 확인. 각 빌드 한 구간 관찰이며 반복 실행의 p95가 아님 |
| 같은 단축어 구간의 누적 hitch | 4,884.9 → 79.2ms | 동일 조작·계측 조건의 별도 기록. XCTest CPU 결과와 합산하지 않음 |
| 탭별 누적 hitch 중앙값 (각 12회) | 22.94 → 12.51ms | 평균 25.72 → 19.11ms, p95 45.86 → 50.02ms; 느린 사례까지 모두 좋아졌다고 주장하지 않음 |
| 위/아래 스크롤 한 쌍의 누적 hitch 중앙값 (각 5회) | 342.0 → 321.1ms | 평균 335.3 → 310.3ms, p95 354.5 → 350.3ms; 최초 XCTest의 악화가 같은 방향으로 재현되지 않음 |
| 스크롤 개별 최대 hitch | 20.85 → 16.67ms | 짧은 끊김은 남음. 계측 구성·횟수가 다르므로 최초 hitch ratio와 직접 합산하지 않음 |
| 상세/집중/복귀 중 잠재 지연의 최댓값 | 상세 225.1 → 225.8ms / 집중 111.0 → 101.2ms / 복귀 267.7 → 227.3ms | 각 1회, 접근성 자동화 부담도 포함. 입력 지연으로 치환하거나 모두 개선됐다고 주장하지 않음 |

`before-ordered-groups.json`, `after-ordered-groups.json`과 각 원본 XML에 집계를 보존했다.
Hangs table의 33ms 이상 구간에는 자동화의 접근성 조회가 포함될 수 있다. 단축어 단계의
잠재 지연 최댓값은 개선 후에도 461.4ms이고 이것이 실제 터치 후 피드백 지연인지는
분리하지 못했다. 반대로 최대 hitch 25ms라는 이유로 입력이 100ms 안에 반응한다고
판정할 수도 없다. 이 구분이 남아 있어 Goal 완료 판정을 보류한다.

현재 검증된 범위에서는 시작·단축어의 병목을 수정했고 기능·데이터 안전성 회귀를
확인했다. 스크롤을 더 최적화하려면 동일한 프레임 계측과 CPU 표본에서 반복 재현되는
원인을 먼저 확인해야 한다. 100ms 목표는 HID 입력→최초 관련 화면 표시를 연결하는
별도 계측이 다음 검증 항목이다. 원인 없이 캐시·비동기화·애니메이션 제거를 추가하지 않는다.

## 변경 전 iPhone 시뮬레이터 결과

2026-09-04 18:32–18:39 KST. Release / DEBUG test hooks / ENABLE_TESTABILITY=YES,
arm64 iPhone 17 Pro Simulator 26.5. 세 성능 테스트 모두 통과.
원본: `.local/performance/baseline/phone.xcresult`, 개별 샘플: `phone-metrics.json`.
빌드 전 소스 해시: `baseline/source-manifest.json`.

| 측정 단위 | n | p50 | p95 | 의미 |
|---|---:|---:|---:|---|
| 저장소 준비 후 앱 프로세스 재실행 | 5 | 16.982초 | 17.285초 | ApplicationFirstFramePresentationResponsive |
| 탭 4회 이동의 앱 CPU 시간 | 10 | 3.629초 | 3.696초 | 캘린더→기록→메모→칸반 1회전 전체 |
| 탭 4회 이동 wall clock | 10 | 7.445초 | 8.247초 | XCTest 대기 포함, 입력 반응 지표 아님 |
| 위/아래 스크롤 앱 CPU 시간 | 10 | 1.023초 | 1.055초 | 두 제스처 전체 |
| 위/아래 스크롤 애니메이션 구간 | 10 | 2.366초 | 2.367초 | 제스처/감속 전체 길이, 끊김 지표 아님 |
| 탭 반복 시 절대 메모리 | 10 | 87,272 kB | 87,296 kB | CPU metric과 같은 측정 구간 |

중요한 계측 한계: 요청한 XCTHitchMetric 및 사용자 정의 TabArchive 구간은
이 시뮬레이터 결과에 측정값이 제공되지 않았다. 값이 없다는 것은 0회/0ms라는
뜻이 아니다. 프레임 끊김과 실제 touch-to-first-frame 100ms 달성은 미검증이다.
3개 테스트 통과는 성능 목표 달성을 의미하지 않는다.

## 변경 전 공통 코어 측정과 첫 개선

`PLANBASE_RESPONSIVENESS_PERFORMANCE=1 swift test --scratch-path .local/performance/core -c release -Xswiftc -DDEBUG --filter responsivenessCoreBaseline`
으로 같은 규모의 별도 파일 저장소를 측정했다. 원본 `baseline/core-run.log`,
샘플/분위수 `baseline/core-metrics.json`. macOS에서 실행한 코어 구간이며 UI 반응 시간이 아니다.

| 구간 | n | p50 | p95 |
|---|---:|---:|---:|
| 기존 탭 보관 명령 자체 | 50 | 약 0.36ms | 0.43ms |
| 작업 240개 보드 projection 1회 | 50 | 약 8.79ms | 9.23ms |
| 저장한 작업 1,000개 snapshot 로딩 | 20 | 약 94ms | 99.90ms |
| 시작 시 무결성 검사 + 저장 | 3 | 20,960.52ms | 21,066.55ms |
| 하루 기록 첫 30일 조회 (매회 새 서비스) | 5 | 약 418ms | 425.45ms |

핵심 발견: 반복 무결성 검사의 `report.hasChanges == false`인데
`context.hasChanges == true`였다. `assign(&model.property, value)`는 helper 안의
값 비교 결과와 별개로 SwiftData 속성의 inout writeback을 연다.
56개 무결성 할당 호출을 객체/키 경로 기반 비교로 바꾸어 동일 값에는 setter가
실행되지 않도록 수정했다. 실제 변경의 저장 및 rollback 경계는 유지한다.
수정 후 결과는 아래 전후 비교에 기록했다.

또한 탭의 빈 보관 검사 자체는 1ms 미만이므로 이를 단독 렉 원인으로 주장하지 않는다.
`ArchiveMaintenanceService`는 후보도 없고 pending edit도 없는 경우만 명령/알림을
생략한다. 알림에서 유발되는 후속 조회의 효과는 앱 전후 비교에서 판단한다.
복귀 시 진행 기록이 최신이 되도록 동일 작업 ID라도 비활성 세션의 재진입은 재조회한다.

Instruments 추가 시도: 시뮬레이터 Time Profiler의 launch 방식이 기록 시작 전에
앱을 stopped 상태로 두고 진행되지 않아 해당 기록을 명시적으로 종료했다.
확인 창은 없었다. Mac DevToolsSecurity는 disabled, 계정은 _developer 그룹이지만
이 설정이 원인인지는 입증하지 않았으며 설정을 변경하지 않았다.

## 첫 개선 검증

- 빈 보관 검사 40회가 알림을 만들지 않는지, pending edit 저장/알림 보존,
  지난 완료만 1회 보관, 기존 저장 실패 rollback, 복귀 후 같은 작업의 새 진행 이벤트
  반영, 무결성 검사의 실제 변경만 저장하는지 등 관련 8개 테스트 통과.
- 같은 코어 benchmark를 최적화 빌드에서 다시 실행했다 (`after/core-run.log`, `after/core-metrics.json`).
  무결성 검사+저장 p50 **20,960.52 → 1,801.05ms (약 91.4% 감소)**,
  p95 **21,066.55 → 1,810.30ms**. 반복 검사 후 context도 clean으로 유지됨.
- 나머지 개별 구간은 아직 최적화 효과를 주장하지 않는다. 보드 projection 자체,
  보관함 로딩, 하루 기록 조회의 결과는 원본 JSON에 함께 보존했다.
- 보드 UI는 한 번의 body 계산에서 작업 목록을 한 번만 정렬하고 상태별 개수/ID/열에
  재사용하도록 변경했다. 캐시를 유지하지 않아 날짜/상태/동기화 변경 시 기존 관찰로 다시 계산한다.
- 수정 후 iOS 앱 전후 계측은 아래와 같다. 전체 회귀 게이트와 다른 시나리오/플랫폼 검증은 별도로 진행한다.

## 첫 iPhone 앱 전후 비교

같은 iPhone 17 Pro Simulator / iOS 26.5 / 같은 파일 저장소 / Release 최적화와
DEBUG test hooks로 세 테스트를 다시 수행해 모두 통과했다. 원본 `after/phone.xcresult`,
샘플 `after/phone-metrics.json`, 해당 빌드 소스 해시 `after/source-manifest.json`.
앞선 계측 이후 Instruments 점검 과정에서 Simulator 창이 열렸으며 UI 창 상태는
첫 측정 당시 별도 기록하지 않았다. 실제 기기 결과나 프레임 지연으로 일반화하지 않는다.

| 측정 | 변경 전 p50 → 후 p50 | 변경 전 p95 → 후 p95 | 해석 |
|---|---|---|---|
| 재실행 후 첫 반응 지표 | 16.982 → 3.699초 | 17.285 → 3.836초 | p50 약 78% 감소 |
| 탭 4회 이동 앱 CPU | 3.629 → 2.000초 | 3.696 → 2.032초 | p50 약 45% 감소 |
| 탭 4회 이동 wall clock | 7.445 → 6.301초 | 8.247 → 6.679초 | 자동화 대기 포함 |
| 위/아래 스크롤 CPU | 1.023 → 1.000초 | 1.055 → 1.049초 | 뚜렷한 개선으로 주장하지 않음 |
| 스크롤 시 절대 메모리 | 84,855 → 69,929 kB | 85,150 → 69,946 kB | 해당 구간의 수치 |
| 탭 전환 시 절대 메모리 | 87,272 → 87,968 kB | 87,296 → 88,099 kB | 소폭 증가, 전체 메모리 개선 주장 안 함 |

추가 수정 (위 앱 계측 뒤): 기록 화면은 화면이 보이고 앱이 활성일 때만 저장 알림으로
재조회한다. 복귀/활성화 시 기존 재조회 경로로 최신 내용을 받는다. 메모는 탭의
빈 저장 알림에 의존하지 않고 화면 재진입 시 현재 검색어로 다시 조회한다.
이 추가 수정은 아래 최종 iPhone 실행에 포함됐다.

최종 iPhone 실행의 세션 로그에서는 2026-09-04 19:37:27 KST에 11개 테스트가 모두
성공했다 (일반 UI 7개 + 성능 4개, 실패 0). 이후 Xcode의 부가 `simctl diagnose` 수집은
600초 제한으로 종료됐으며, 테스트 명령은 종료 상태 0으로 완료됐다.
완성된 `phone-final.xcresult` 요약에서도 성공 11/실패 0을 확인했고
`phone-final-metrics.json`으로 원본 샘플을 추출했다. 부가 진단 수집 시간은 측정 구간 뒤여서
성능 수치에 포함되지 않는다. 별도 단축어 성능 1개까지
최종 코드의 iPhone 검증은 총 12개다. iPad 기능 검증은 이 측정 종료 뒤 시작했다.

iPad A16 Simulator 26.5에서도 5개 기능 테스트가 성공했다 (실패/생략 0).
큰 글자의 하루 기록, 집중 모드의 큰 글자·가로 화면, 네이티브 세로/가로 창,
단축어 후보·중복 입력어 거부, 작업 완료 후 알림 기록 보존을 확인했다.
`after/ipad-final.xcresult` 및 `after/ipad-attachments/manifest.json`에 보존했다.
후보의 예상 40분 표시, 큰 글자 집중 일시정지 화면, 기본 보드 캡처도 직접 확인했다.
iPad에서는 기능/레이아웃을 확인했으며 성능 전후 수치를 측정했다고 주장하지 않는다.

전체 게이트 `./scripts/verify-platform-builds.sh`가 종료 상태 0으로 완료됐다.
로그 `.local/performance/platform-gate.log`. 성공한 범위와 미검증 항목은 맨 위 표에 구분했다.

- 전체 게이트의 공통 테스트: Debug 396개, Release 395개 성공.
  도구의 총계 399/397에는 선택 실행 벤치마크 생략 3/2개가 포함된다.
  이 작업의 responsiveness 코어 벤치마크는 별도 명령에서 실행·통과했다.
  iOS/macOS Debug·Release와 내장 Watch 앱·위젯 빌드, 호환 bundle ID 및 privacy manifest 검증 통과.
  종료 상태는 `platform-gate-exit.json`에 보존했다. 이후 추가 변경은 UI 검증 코드,
  단축어 후보 화면의 중복 계산 제거 및 문서다. 마지막 UI 수정 후 iOS 계측용
  Release 빌드와 macOS 일반 Release 빌드도 종료 상태 0으로 통과했다.
- macOS Debug 빌드는 완료되어 `.local/performance/after/PlanBase-Debug.app`로 보존했다.
  `--ui-testing`으로 메모리 저장소/독립 집중 타이머/위젯 쓰기 차단이 적용되는 것을
  코드에서 확인한 후 실행했다. 실제 `/Applications/PlanBase.app`는 조작하지 않았다.
  Orca 화면 읽기는 `permission_denied`로 실패했다. 도구의 접근성·스크린샷 권한 조회는
  모두 granted였고 창 복원 후에도 AX 창 조회가 실패했다. macOS 화면 검증은 통과로
  표시하지 않으며 사용자에게 같은 권한 토글을 반복 요청하지 않았다.

## 대용량 단축어 입력에서 추가 발견한 병목

첫 개선 앱에서도 1,000개 보관함에서 `/perf12` 입력 후 7글자 지우기를 반복한 결과,
앱 CPU p50 15.330초 / p95 26.227초, wall clock p50 16.444초 / p95 27.293초였다(n=5).
이는 1회 입력·삭제 사이클의 합이며 한 글자의 입력 반응 시간이 아니다.
같은 앱의 상세 열기/닫기와 예상 30분 집중 설정 열기/닫기는 CPU p50 1.558초 / p95 1.600초였다.
원본은 `after/interaction-before-suggestion-fix.xcresult`와 metrics JSON에 보존했다.

측정 출처 정정: 처음에는 이 결과를 baseline 경로로 기록했으나, 설치된 Mach-O UUID를
확인한 결과 첫 개선 앱(`8BBEA393-D884-3F22-B603-1DF419DC1288`)이었다.
`UITargetAppPath`만 바꿔도 dependent product가 앱을 다시 설치하므로 이 결과를
`9c5a7df` 원본 비교로 사용하지 않는다. 원본 경로를 `after`로 옮겼으며 기존 시작/탭/스크롤
baseline 결과와는 별개다. Mach-O UUID 확인 전 파일명만으로 출처를 판단하면 안 된다.

별도의 진단 실행에서 3초 host `sample`에 성공했다.
`after/shortcut-main-thread.sample.txt`에서 메인 스레드의
`SavedTaskQuickEntrySuggestions.row` → `normalizedAlias` 반복 호출을 확인했다.
후보마다 전체 항목을 훑어 중복 입력어를 계산하고, 같은 body에서 후보 필터/정렬도
두 번 실행하고 있었다. 이 진단 실행의 시간은 샘플링 영향을 받으므로 전후 표에 사용하지 않는다.

추가 수정은 body당 후보 목록/중복 입력어 집합을 한 번 계산해 행에 전달한다.
검색·정렬·중복 표시 규칙과 모든 후보를 볼 수 있는 동작은 유지하며, 화면 갱신을 넘어서
유지하는 캐시는 추가하지 않는다. 양 플랫폼 빌드 후 같은 시나리오를 다시 측정했다.

| 단축어 입력·삭제 1회 (n=5) | 수정 전 p50 → 후 p50 | 수정 전 p95 → 후 p95 |
|---|---|---|
| 앱 CPU 시간 | 15.330 → 2.068초 (86.5% 감소) | 26.227 → 2.512초 |
| 자동화 대기 포함 wall clock | 16.444 → 3.169초 | 27.293 → 3.575초 |
| 절대 메모리 | 76,663 → 76,303 kB | 76,975 → 76,352 kB |

후 결과: `after/shortcut-final.xcresult`, `after/shortcut-final-metrics.json`.
진단 sample 없이 측정했다. 코드 해시는 `after/final-suggestion-source-manifest.json`.
첫 측정 때 사용한 앱은 `after/BeforeSuggestionFix.app`에 보존했다.
이 수치는 글자 7개 입력과 삭제 전체이며 100ms 터치 피드백 달성을 뜻하지 않는다.

## 재현 명령과 비교 조건

저장소 루트에서 아래 순서로 실행한다. 기존 결과 경로가 있으면 새 실행 이름으로
`after`와 결과 파일명을 바꾸어 보존한다. 성능 측정과 빌드는 동시에 실행하지 않는다.
시뮬레이터 ID는 `xcrun simctl list devices available`에서 현재 환경의 값을 확인한다.

```bash
xcodebuild -quiet -project PlanBase.xcodeproj -scheme PlanBase-iOS \
  -configuration Release \
  -destination 'platform=iOS Simulator,id=2F58896B-F7D6-441D-9979-65566A6E4191' \
  -derivedDataPath .local/performance/after/DerivedData \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG ENABLE_TESTABILITY=YES \
  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build-for-testing

xcodebuild -quiet -project PlanBase.xcodeproj -scheme PlanBase-iOS \
  -configuration Release \
  -destination 'platform=iOS Simulator,id=2F58896B-F7D6-441D-9979-65566A6E4191' \
  -derivedDataPath .local/performance/after/DerivedData \
  -resultBundlePath .local/performance/after/phone-new.xcresult \
  -only-testing:PlanBaseLaunchUITests/PlanBaseResponsivenessTests \
  -parallel-testing-enabled NO \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG ENABLE_TESTABILITY=YES \
  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO test-without-building

python3 scripts/summarize-responsiveness-metrics.py \
  .local/performance/after/phone-new.xcresult \
  .local/performance/after/phone-new-metrics.json
```

fixture는 최초 한 번만 생성된다. 생성일 기준 오늘 작업이 240개이므로 날짜가 바뀌면
동일 조건 비교가 되지 않는다. 실제 사용자 데이터를 삭제해 측정 조건을 맞추면 안 된다.
새 날짜의 데이터가 필요하면 기존 시뮬레이터의 사용자 저장소를 지우지 말고 전용 새
시뮬레이터를 사용한다. 최초 fixture 생성 시간은 앱 시작 비교에 넣지 않는다.

코어 측정은 매번 고유 임시 디렉터리에 로컬 fixture를 만들고 자기 디렉터리만 정리한다.

```bash
PLANBASE_RESPONSIVENESS_PERFORMANCE=1 swift test \
  --scratch-path .local/performance/core -c release -Xswiftc -DDEBUG \
  --filter responsivenessCoreBaseline
```

이 명령은 현재 코드를 측정한다. 변경 전 앱 바이너리와 원본 결과는
`.local/performance/baseline/`에 보존했고, 최적화 바이너리로 덮어쓰지 않는다.
소스 기준뿐 아니라 계측 hook/fixture의 차이도 manifest와 함께 확인한다.


## 사용자 요청에 따른 TestFlight build 70 — 2026-09-04

사용자가 현재 최적화 변경의 TestFlight 업로드를 요청했다. 버전은 1.0(70)이며 iPhone·iPad,
내장 Watch 앱·위젯 및 macOS universal 앱·위젯을 포함한다. V11 스키마와 백업 V10은 유지한다.
Xcode 26.6의 일반 Release 설정으로 서명 archive를 만들었으며, 계측용 DEBUG override를
사용하지 않았다. 전체 플랫폼 회귀 게이트 통과, 여섯 번들의 서명·공유 권한 확인,
iOS 186개·macOS 178개 컴파일 소스와 사전 snapshot의 해시 일치 및 성능 fixture 제외를 확인했다.

Xcode 재로그인 후 iOS 22:16:34, macOS 22:18:08 KST에 App Store Connect 업로드가 성공했고
이후 두 플랫폼 모두 Apple 패키지 처리가 완료됐다. 기존 내부 그룹 `지인`(2명) 연결과
한국어 테스트 안내 저장, 배포 서명의 CloudKit Production 권한도 확인했다. 실제 TestFlight
설치는 별도로 남는다. 자료와 정확한 소스 snapshot은 `.local/releases/build-70/`에 보관한다.
100ms 초기 피드백은 여전히 미검증이며, 이번 배포로 성능 Goal을 완료 처리하지 않는다.
