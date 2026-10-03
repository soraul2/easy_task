# PlanBase 최적화 실행 결과 — 실제 화면 검증 대기

작성일: 2026-10-02. Goal 실행 ID: `run-154826-ab8b66`.
2026-10-03 09:42 KST 사용자의 “진행해” 요청으로 남은 검증 작업을 재개했다. Goal 도구의 현재 반환은 이전 판정의 **blocked(차단됨)**이며, 상태가 active나 complete로 변경됐다고 표시하지 않는다. 이 문서는 진행 기록이며 완료 보고가 아니다. 실행은 [Goal 명세](OPTIMIZATION_2026_10_02_GOAL_PROMPT.md)와
[계획](OPTIMIZATION_2026_10_02_PLAN.md)의 전체 범위·완료 조건을 따른다.

**2026-10-03 후속 사용자 지시**: “화면 검증은 뒤에 하고 testflight 업로드 진행해”에 따라 실제 화면 인수는 후속으로 보류하고, 현재 채택본의 TestFlight 1.0(87) 배포를 진행한다. 이는 화면 인수 통과나 Goal 전체 완료 선언이 아니다. 업로드에 필요한 빌드 번호 증가·Release archive·배포 패키지 검증은 새로 승인된 범위이며, 이전02:39 Goal 도구 상태와 별도로 실행한다. 화면 인수 완료를 업로드의 선행 조건으로 요구하지 않는다. 배포 결과는 별도 release 기록에 남긴다.

[빌드87 배포 기록](../../releases/TESTFLIGHT_BUILD_87.md): 두 Release archive와 iOS·macOS Production 패키지의 여섯 번들·실행 파일을 확인했다. 버전 설정 후 전체 게이트764.430초 exit0, Debug689통과/36skip·Release684통과/10skip 및 종료 후409/373 source 연결을 확보했다. 최초 계정·Mac 설치 서명 오류는 보존했고, 로그인·서명 준비 후 같은 archive에서 iOS 13:14:21·macOS 13:16:38 KST 업로드 exit0 및 Apple 패키지 처리 시작을 확인했다. 설치 가능 상태와 실제 화면 인수는 미확인이다.

**2026-10-03 업로드 재개**: 외출 중 보류 요청에 따라 검증된 소스와 배포 준비 기록을 `e02eb9f70a267d7dfb08c82441cb727fddc002c3`로 commit·push한 뒤, 사용자가 로그인을 완료하고 업로드를 다시 요청했다. 재개 시 고정487파일과 현재409개 빌드 입력의 불일치0을 확인하고 두 플랫폼의 업로드를 완료했다. archive·배포 패키지·최초 실패·재시도 로그와 영수증은 Git에서 제외된 `.local/releases/build-87/`에 보존한다. 실제 화면 인수와 전체 Goal 완료 상태는 변경하지 않았다.

## 재개 후 확인 — 2026-10-03 10:04 KST

- 전용 iPhone `1D840800-EE82-4A80-B188-36B3298CECA9`의 fresh container 조회는 Shutdown 오류를 반환했다. 소유 등록을 대조한 뒤 이 기기만 boot·bootstatus exit0로 기동했고, Simulator native 화면 접근이 복구됐다. 재시작이나 erase는 수행하지 않았다. UI에서 안전 앱을 열어 `2026.10.03`의 빈 보드와 네 탭·`/` 안내를 확인했다.
- 기존 합성 snapshot의 단일 날짜 일정 두 개만 오늘로 이동해 오늘3개·전날1개·다음날1개의 데이터를 준비했다. 장기 일정·제목·logical/render ID·format5·31일 범위는 보존했다. 설치 앱/확장 SHA·strict signature·기기의 현재 group 경로·기존 합성 bytes를 검증한 뒤, 전용 Simulator의 JSON 한 파일만 원자 교체하고 새 SHA `76cd0494…`를 읽어 대조했다. 실제 사용자 App Group과 데이터는 접근하지 않았다. [준비 근거](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/widget-calendar-long-fixture-20261003-preparation.json), [적용·읽기 근거](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/widget-calendar-long-fixture-20261003-staging.json).
- 전용 iPhone의 실제 잠금 화면까지 도달했으나 사용자화·위젯 추가에는 진입하지 못했다. 세 모양의 provider load/render·제목/기간·privacy·tap·자정 인수는 여전히 미검증이다. seeded 위젯 JSON은 앱의 별도 메모리 Calendar 데이터와 구분한다.
- 소유 Watch `06FE96DC-0C95-4259-BF5A-28569B4A4D36`는 fresh 읽기 조회상 Booted이며 설치 앱/확장 SHA와 안전 group 경로가 기존 prelaunch 근거와 같았다. 이 조회에서 launch·쓰기·GUI 조작은 없었고 실제 Today/Focus·extension 읽기·컴플리케이션 인수는 남았다.
- 정확한 안전 Mac 앱 PID60391의3초 sample은 exit0이며 메인 스레드274표본 모두 이벤트 run loop의 Mach 메시지 대기였다. 이 구간에서 계속 연산하는 정체는 관찰되지 않았다. 창 존재·Focus 닫기 후 root 복귀·입력 지연을 증명하지는 않는다. [원시 sample](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/mac-safe-resumed-20261003-main-thread.sample.txt), [PID·명령·범위](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/mac-safe-resumed-20261003-main-thread-sample.json).

이후 화면 도구가 **Mac 잠금과 자동 해제 실패를 명시적으로 반환**했다. 사용자에게 직접 잠금 해제를 요청했으며, Watch·잠금 화면·Mac의 남은 실제 인수는 해제 후 이어간다. 제품/검사 소스는 변경하지 않았고 통과한 build/test를 반복하지 않았다. 아래02:39 차단 판정은 이전 실행의 기록이며, 재개 이후의 진척이나 새 차단 판정으로 덮어쓰지 않는다.

재개 시점의 [root 수동 화면 원장](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/resumed-20261003-native-ui-ledger.md)과 [현재409입력·373Swift 대조](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/resumed-20261003-turn-1-source-guard.json)를 보존했다. [위젯 JSON 적용 독립 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/calendar-lockscreen-20261003-staging-independent-review.md)는 provenance 일치와 실제 render 미검증을, [Watch fresh 읽기 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/watch-resumed-20261003-readonly-preflight.md)는 설치본 일치와 실제 launch 미검증을, [Mac 정적·sample 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/mac-focus-close-resumed-20261003-static-review.md)는 관찰 구간의 이벤트 대기와 창 복귀 미검증을 각각 확인했다.

## 이전 차단 판정 — 2026-10-03 02:39 KST

세 실제 Goal turn에서 남은 필수 native UI 인수에 접근할 수 없는 상태가 반복됐다. 이전 두 turn의 명시적 Mac 잠금과 달리, 이번 turn은 같은 safe 앱 full-path 두 조회·실제 running 목록의 bundle ID 조회 및 Simulator 조회가 모두 `timeoutReached(-10005)`였다. inventory 조회는 성공해 두 safe 앱과 Simulator가 실행 중임을 확인했다. **이번 시간 초과를 현재 잠금 상태·앱 종료·제품 결함으로 단정하지 않는다.** 같은 대상을 다시 조회했으며 프로세스를 재시작하지 않았다.

현재409개 build 입력은 최종 검사본과 모두 같고 live build/test 및 진행 중 subagent 작업은 없다. 사용자 안내와 독립 완료 감사도 마쳤으며 추가 필수 독립 소스·문서 작업이 없다는 검토를 받았다. [세 turn 차단 감사](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-local-validation-blocked-audit-turn-3.json)를 근거로 Goal을 blocked로 전환했다. 원래 범위·완료 조건과 남은 Mac/VoiceOver/OS IME·Lock Screen 세 모양·Watch 실제 인수는 그대로 유지한다. 화면 접근 복구와 기존 수동 accessory 진입 후 재개해야 한다. 아래 active 표현은 해당 시점의 실행 기록이다.

## 최신 검증 상태 — 2026-10-03 01:59 KST

**2026-10-03 02:21 KST 후속 안내**: 완료 조건 감사에서 빠졌던 [오늘 일정 잠금 화면 위젯 사용 안내](../../CALENDAR_LOCK_SCREEN_WIDGET_GUIDE.md)를 작성하고 문서 목록에 연결했다. 기능 포함 버전 설치·직접 추가 방법·세 모양·마지막 발행 데이터와 OS 갱신 한계·미확정 상태를 설명한다. 제품 코드 변경이나 검사 재실행은 없으며, 실제 Lock Screen/Watch·남은 Mac UI 인수와 Goal active 상태는 유지한다.

안내의 [root 소스·링크 대조](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/calendar-lockscreen-guide-root-source-validation.json)는409개 build 입력 불변·로컬 링크299개 정상·공식 추가/갱신 설명을 기록한다. 이후 [독립 안내 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/calendar-lockscreen-guide-independent-review.md)에서도 현재 제품 분기·버전 전제·갱신 한계·실제 화면 대기 표현의 차단 문제는 없었다. 기록별 문서 SHA는 해당 검토 시점의 값이다.

**02:31 KST 완료 조건 감사**: [원문 요구별 독립 감사](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/completion-audit-continuation-2.md)는9영역 조사·개선 판단·최종 로컬 게이트·결과 기록을 범위 내 충족으로 판정하고, 완료 조건2의 실제 화면 인수는 미완료로 유지했다. 100ms 직접 계측의 허용된 미검증, Archive/hitch 원시 지표 누락과 전체 bundle invalid, Watch memory/PID 진단본의 재실행 복원 한계를 별도로 기록한다. 후자는 제품 결함이나 새 격리 persistent 모드 구현 요구로 단정하지 않는다. 안내 누락은 위 후속 가이드로 해결했으며 추가 생산 코드 변경 권고는 없다.

**S2lite, S4, M2split512와 S2batch는 main 채택 완료다.** 초기 full S2와 M2-256은 거부했다. S2batch는 두 독립 실제 backfill 비교, 자동 저장 활성 memory/local-file 8조건 및 batch11 optimized 전체729개 통과 뒤 정확한 2파일을 채택했다. 이전 시제품의 미채택 상태와 실패 로그는 당시 기록으로 보존한다. [S2batch 채택](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/S2batch-main-adoption.json), [S2lite/S4 채택](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/S2lite-S4-main-adoption.json), [512 채택](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/M2-separated-512-main-adoption.json).

현재 main에는 메모 저장 실패의 **Back 옆 아이콘 재시도**, 필기 화면 종료 시 **도구 정리**, iPad 캘린더 헤더의 **시스템 창 제어기 영역 반영**이 채택됐다. 마지막 두 수정은 candidate 생산2파일·최소 UITest25줄을 검토하고 기능6개 및 native 인수 후 적용했다. 현재 MobileMemoView SHA `989532…`, MobileCalendarGrid `b9decc…`, 최소 UITest `b42540…`다. 새 main409개 입력·Swift373개 roster guard와 별도 main build-for-testing187.827초가 exit0다. 실제 생성 runner의 안전 prelaunch·기존 checker/dylib·AX5 환경변수 하나의 차이도 확인했다. 최소 main phoneDrawing1/0 PASS58.181초와 iPadCalendar1/0 PASS50.926초가 모두 exit0다. root와 독립 검토가 새 첨부의 목록·필기·좁은 헤더·넓은 캘린더·일정6개 화면을 확인했고 새 전체 플랫폼 게이트768.191초가 exit0다. gate 후409/373 source guard도 exit0다. 기능 시간은 반응성 측정값이 아니다. [실제 마지막 채택](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-main-ui-palette-calendar-remedy-actual-adoption.json), [후보 기능6개 인수](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ui-palette-calendar-remedy-candidate-root-functional-acceptance.json), [새 main 검증 계획](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-main-ui-palette-calendar-remedy-build-for-testing-plan.json).

재시도 UI의 실제 main default1/0 PASS85.126초·AX5 1/0 PASS81.971초와 제목/footer/Done 비겹침은 이전 product411fc6…·testad8252…에서 확인한 근거로 보존한다. 이후 추가된 수정은 필기 canvas 수명주기와 CalendarHeader이며 Retry/초안/저장 분기는 그대로다. [기존 main 쌍 독립 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-main-memo-leading-retry-independent-main-pair-review.md).

이전 keyboard/native-preset freeze와 최종 성능 pair는 당시 product247개가 main29f80…와 일치한 증거다. 현재는 그 가운데 MobileMemoView와 MobileCalendarGrid 두 파일이 후속 UI 검증으로 바뀌었고 나머지245개는 그대로다. 반응성 class marker부터 EOF의 suffix SHA `94cf9ae1582b882204888df3ba2e6e2d3817b4249d482d5441d04ffcfe1f2c00`와10metric methods는 변하지 않았지만, 과거 pair를 새 UI binary의 측정으로 재분류하지 않는다. 최신 일반 게이트는 palette-calendar 수정 뒤 exit0이며, 현재 main 두 UI 검사·gate 전후409/373 guard가 연결된다. 앞선 after-keyboard 게이트는 당시 증거다.

[최신9영역 재평가 v6](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-nine-area-decision-registry-v6.md)는 기존 성능·기각·작은 회귀와 새 UI 인수를 구분해 검토했다. 추가 구현 권고는0개다. v6 검토 당시 running이던 전체 게이트는 이후 exit0로 종료했고 수동 Mac·Lock Screen·Watch 인수는 남았다. [최신 로컬 인수·종료/소스 연결](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-main-ui-palette-calendar-remedy-local-validation-acceptance.json). 이전 registry와 실행 실패는 당시 기록으로 보존한다.

| 검증 | 실제 상태 | 증거·판정 범위 |
|---|---|---|
| 일반 `verify-platform-builds.sh` | **현재 main palette-calendar gate exit0 완료** | Debug725개(689통과·36skip)/26.459초, Release694개(684통과·10skip)/24.254초·실패0. iOS/macOS Debug·Release 네 build, 위젯6·내장 Watch2·Privacy12·diff 경계까지 정상 script768.191초 exit0다. 별도 UI build와2검사는 앞서 통과했고 gate 후409/373 source guard도 일치한다. [최신 종료](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-platform-after-palette-calendar-remedies-status.json), [최신 로컬 인수](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-main-ui-palette-calendar-remedy-local-validation-acceptance.json), [이전 after-keyboard gate](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-platform-after-keyboard-status.json). |
| 최신 main UI 최소 검사 | **phone1·iPad1 통과/실패0/건너뜀0, exit0** | 현재 생산989/b9 및 최소 UITest25줄 b425를 별도 build-for-testing187.827초 exit0로 컴파일했다. phone58.181초·iPad50.926초 기능 통과와 원래 native6PNG파일(고유5)/1TXT를 확인했다. 삭제한 진단93줄의 candidate 캡처·TXT나 과거 성능 pair와 구분한다. [phone root 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-main-phone-palette-remedy-functional-root-native-review.json), [iPad root 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-main-ipad265-calendar-remedy-functional-root-native-review.json), [독립 사전 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-main-ui-palette-calendar-remedy-independent-preflight-review.md). |
| iOS hosted | **34개/실패0, exit0** | widget12·backup7·Live Activity 상태12·Notification fake3의 실제 hosted 통과를 보존한다. 추가 keyboard toolbar의 기능 인수·OS render/실제 알림 전달과는 별도다. [로그](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-hosted-mobile-tests.log). |
| 독립 Watch scheme·격리 runtime binary | **Debug/Release 두 build·safe Debug build exit0; 정적 서명 검증 통과** | 최종 Watch build 검증 이후 Watch 생산 소스 변경 없음. owned Watch26.5/23T570 `06FE96DC-0C95-4259-BF5A-28569B4A4D36`의 boot·bootstatus·install과 안전 App Group container 조회4명령은 exit0다. 앱 등록·컨테이너 경로 해석까지 확인했으며 launch는 아직 없다. 격리 app/extension 모두 strict codesign verify exit0이며 이 Simulator binary의 signature XML은 비어 있고 Mach-O `__TEXT,__entitlements`의 진단 group은 양쪽 일치한다. 앱의 안전 group 컨테이너 해석 성공과 extension runtime access·snapshot 공유·실제 Watch/컴플리케이션 조작·장시간 수명은 구분한다. 후자는 미검증이며 Mac 잠금으로 GUI가 중단됐다. [기존 Debug](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-debug-build-status.json), [기존 Release](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-release-build-status.json), [safe Debug](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-runtime-safe-debug-build-status.json), [서명·실제 section 근거](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-runtime-safe-signed-bundles.json), [boot](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-owned-runtime-boot-status.json), [bootstatus](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-owned-runtime-bootstatus-status.json), [install](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-owned-runtime-install-status.json), [group 조회](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-owned-runtime-containers-status.json), [정확한 안전 group 경로](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-owned-runtime-containers.log). |
| 새 keyboard iOS UI source 빌드 | **TEST BUILD SUCCEEDED, exit0** | 최신 생산247개가 main과 같고 Release+DEBUG/testability build-for-testing 통과. 이전486파일 UI freeze의 “main 일치”는 그 생성 시점이며 새 keyboard source와 구분한다. 거부256 binary를 쓰지 않는다. [빌드 상태](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ui-adopted-keyboard-build-status.json). |
| 메모 iPhone 기능6검사 | **6통과/실패0, exit0** | iOS27.0 전용 phone의 actual keyboard dismiss→Calendar→Memo→실패 초안→retry→저장 재열기/삭제를 포함한 cooperative 검사78.049초 PASS. drawing42.813초 포함6개 전체238.037초 PASS. 입력 latency/취소 in-flight/frame 측정은 아니다. [원본 로그388행](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-iphone-memo-keyboard-functional.log:388), [종료 상태](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-iphone-memo-keyboard-functional-status.json). |
| iPad26.5 adaptive9검사 | **3통과/4실패/2건너뜀, exit65** | rotation/checklist/quickentry 통과. bigText·VoiceOver skip은 통과가 아니다.4 window 검사는 Dock Settings icon 준비의 존재 기대(frozen707/944행)에서 실패했다. 실제 narrow/side-by-side 내용 인수 완료를 주장하지 않는다. [원본 결과1711행](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-adaptive-ui-tests.log:1711), [종료 상태](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-adaptive-ui-tests-status.json). |
| iPad27.0 초기 adaptive 실행 | **runner2회 재시작·2통과/3assertion 실패/2skip; exit−15** |9선택 중 로그 summary7개. post-suite finalization588.230초 stall 뒤 소유 xcodebuild만 SIGTERM. 원본 로그/불완전 xcresult를 보존하며 전체9통과·제품 데이터 실패로 바꾸지 않는다. [종료 근거](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad27-post-suite-finalization-stop.json). |
| test-only window-coordinate 보정 | **build exit0; 실제4검사 모두 실패, exit65** | XCTest187.652초/xcodebuild190.046초. 3개는 Settings Dock icon 준비(frozen942행), Memo는 native hide 후64pt Keyboard가 남아 hidden 검사(frozen666행)에서 실패했다. actual Board MP4는 `좌우` tap만으로 이미 두 반폭 창이 배치되고 후속 Dock swipe가 창을 들어 올린 전환 상태를 만든다는 근거다. Memo MP4는 동일 편집 화면/본문/저장됨을 유지한 채 완료 accessory가 남음을 보인다. [원본 결과899행](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-window-coordinate-functional.log:899), [종료 상태](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-window-coordinate-functional-status.json), [107첨부 manifest](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-window-coordinate-attachments/manifest.json), [영상 판정](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/ipad-windowing-second-retry-review.md). |
| test-only native-preset Sendable 보정 | **build exit0; owned reboot 후 실제4통과/0실패, exit0** | 추가 Dock 단계 제거·명시적 keyboard 닫기 우선으로 기존 width320…600/content·두 window non-overlap/hittable·keyboard-hidden 기대를 유지했다. Board/Focus85.700초·Calendar/Archive94.272초·Memo resize/tiling58.640초·actual narrow wrapping44.631초 PASS, XCTest283.243초/xcodebuild292.931초. 첫 self capture compile 실패(exit65)와 UI 시작 전 설치 MIG 대기265.417초/실행0/−15를 보존했다. only-owned iPad shutdown→boot 후 retry했으며 erase는 하지 않았다. [수리 build](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ui-native-preset-sendable-build-status.json), [검사 시작 전 중단 근거](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-install-wait-stop.json), [실제4검사 summary1521행](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-reboot-functional.log:1521), [종료 상태](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-reboot-functional-status.json). [독립 oracle 보존 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad-native-preset-oracle-review.md), [성공 화면11개 직접 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-visual-review.md), [새 native 첨부26개 manifest](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-success-attachments/manifest.json), [전체26개 SHA·관찰 범위](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-success-attachments/review-manifest.json). |
| 격리 Mac compile·실제 Mac/Lock Screen | **일부 실제 저장·재열기·Focus 흐름 관찰; 다시 명시적 host lock으로 중단** | normal safe 앱과 저장 실패 진단 variant의 관찰은 아래 잠정 ledger 범위로 기록한다. Unicode본문·D1 연속 저장·실패 초안 탭 복귀/retry를 확인했으나 캘린더 상세 진입·Focus 종료 후 root 복귀·실제 위젯·spoken VoiceOver/OS IME는 미확인이다. 잠금 해제 요청은 대기이며 Goal active를 유지한다. [Mac 빌드 상태](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-mac-ui-safe-build-status.json), [variant build exit0](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-mac-ui-accessibility-save-failure-safe-build-status.json), [variant source proof](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-mac-ui-accessibility-save-failure-safe-source-proof.json). |
| 메뉴·초기 로딩 실제 UI10조건 전후 pair | **first pair 완료: 양쪽10통과/0실패·exit0; 전체 지표 묶음은 `invalid`** | baseline XCTest856.572초/xcodebuild863.888초, candidate838.294초/840.285초는 전체 실행 시간이다. 각 raw10records, 15제품+3history entity의 columns/count/full-row SHA와 날짜 UI 기대가 일치한다. 컨테이너 UUID/경로는 달라 같은 물리 경로를 주장하지 않는다. 첫 pair p50에서 초기 내용 준비 clock−5.51%·추천 입력−12.85%, 기존 warm4탭+3.70%·스크롤+2.90%를 관찰했다. 양쪽 Archive signpost1건·hitch6조건 누락/지원 미확인과 최초 메뉴3조건 CPU·메모리/PID·peak 제외를 유지한다. 독립 UI 반복·100ms 입력/frame은 미검증이다. [candidate 종료](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-candidate-ui-metrics-status.json), [원시 pair](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-metric-pair-comparison.json), [내용 비교v2](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-fixture-pair-comparison-v2.json). |
| current-source A1/W1 Core 독립 반복 | **4command 모두 실제 검사 PASS/exit0, raw 완료** | W1 public4조건 full digest 동일·16raw행 검증, A1 10pairs의 aggregate/ordered sample digest 동일·20raw행 검증. A1 review-only p50−80.03%/−78.13%, W1 actual public경로−56.68%/−35.23%/−7.52%/−28.36%를 해당 입력 범위에서 관찰했다. DispatchTime elapsed이며 operation CPU·에너지·UI frame·Watch runtime 인수를 뜻하지 않는다. [W1 요약](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-current-watch-repeat-3-summary.json), [A1 요약](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-current-archive-repeat-2-summary.json), [소스·격리 proof](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-a1-w1-repeat-isolation-source-proof.json), [완료 시점 owned기기 proof](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-a1-w1-repeat-completion-device-proof.json), [W1 최종 독립 리뷰 SHA460e74…](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-current-watch-repeat-3-review.md), [A1 최종 독립 리뷰 SHA481786…](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-current-archive-repeat-2-review.md). |

일반 after-keyboard gate의 Swift Testing 집계725/694는 각각 성공689+건너뜀36, 성공684+건너뜀10으로 구성된다. 건너뛴 선택적 성능·진단 검사를 모두 실행한 것으로 표시하지 않으며,48개의 parameterized 함수/235개 사례를 검사 수에 다시 더하지 않는다.

batch11 optimized729개 기본 병렬 통과(26.259초)는 정상 Debug/Release 검사와 별도 빌드 조건의 증거다. 검사 수를 더해 UI나 Watch 통과로 주장하지 않는다. 메모의 외부 저장/미저장 편집·취소·재시도, 첨부3개 공개 서비스 검사와 원자 명령 rollback은 통과했으나 전체 Goal은 계속 진행 중이다. 통합 선택과 비교 조건은 [9영역 registry v5](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-nine-area-decision-registry-v5.md)에 남아 있다. v5는 최종 first UI pair와 A1/W1 독립 반복·규모별 증가·미검증 범위를 반영한 독립 읽기 검토이며, 이번 실제 화면 후속 관찰은 아래 별도 잠정 기록이다.

## 기준과 비교 조건

- 시작 HEAD: `b7e524a0038df84a6b5b84864cb1774b9199cabf`, TestFlight 1.0(86).
- macOS 27.0 (26A428), Xcode 26.6 (17F113), Swift 6.3.3, arm64, 32GiB.
- 시작 제품·문서 430개 파일과 SHA-256 manifest를 고정했다. 기존 생산 소스의 기준 사본은 수정하지 않는다.
- 합성 데이터와 메모리/전용 로컬 저장소만 사용한다. 실제 사용자 데이터·CloudKit·iCloud Drive·안전 백업에는 접근하지 않는다.
- CPU 비교는 Release 최적화 + DEBUG + testability 계측 빌드다. 일반 배포 Release 검증과 별개다.
- 상속된 CommandLineTools SDKROOT는 해당 명령 환경에서만 제거한다.
- 기준과 후보를 순차 실행하고 성능 검사 중 빌드·다른 benchmark·UI 검사를 병행하지 않는다.
- 원본 증거 루트: `/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/`.
  `baseline/manifest.json`, `baseline/comparison-harness-manifest*.json`, 명령별 `.command.json`/`.status.json`/`.log`와
  `results/`의 조사·설계 기록을 보존한다. 자원 통계는 전체 명령과 준비 비용을 포함하며 작업별 메모리로 해석하지 않는다.

## 초기 기준 계측 — 당시 기록

아래는 변경 전 함수 시간이다. 앱 첫 화면·입력 지연이나 개선 결과가 아니다.
30개 표본은 준비 실행 후 독립 작업을 반복한다. n=5 조건의 p95는 안정적 꼬리 지표로 주장하지 않는다.

| 구간·합성 규모 | 표본 | 기준 중앙값 | 해석 |
|---|---:|---:|---|
| 빠른 입력 1,000개, input 변경+후보 읽기 100회 | 30 batches | 828.41ms/batch | 평균 8.284ms/operation; 개별 입력 p95가 아님 |
| 같은 `/` query, 강조 이동+후보 읽기 100회 | 30 batches | 225.50ms/batch | 평균 2.255ms/operation |
| 같은 prefix query, 강조 이동+후보 읽기 100회 | 30 batches | 1,757.74ms/batch | 평균 17.577ms/operation; 라이브러리 준비는 구간 밖 |
| 메모 200/2,000/10,000개, 무결과 검색 | 각30 | 17.00/218.26/2,617.23ms | 전체 본문·checklist 검색, local warmed context |
| 메모 10,000개, 마지막 본문/체크리스트만 일치 | 각5 | 2,598.69/2,578.89ms | 전체 검색 완료와 정렬·cursor·summary 검사 |
| 메모 10,000개, 빈 query | 5 | 9.91ms | 첫40개 목록; 희소 검색과 다른 경로 |
| 백업 100/1,000/10,000작업, 부모10/100/1,000개 | 30/30/5 | 45.63/640.69/27,227.61ms | package contents 준비, digest 검증은 타이밍 밖; 사진·file dialog 제외 |
| 35일 달력, 일정30/200/1,000개 날짜별 개수 | 각30 | 상세 로그/16.76/82.98ms | 물리 중복 포함; 정확성 수정 후 같은 결과를 기대할 수 없는 조건은 별도 비교 필요 |
| 일정1,000개, lane layout / 제목 wrap+layout | 각30 | 15.18/28.40ms | 고정 geometry/font11; 실제 회전·Dynamic Type는 UI 확인 |

`baseline-quick-entry-1`, `baseline-memo-search-1`, `baseline-backup-export-1`,
`baseline-calendar-month-1`은 통과했다. 이 표는 첫 기준 실행의 기록이며 현재 비교·채택 상태는 아래 표에 구분한다.
`baseline-lifecycle-1`은 fixture 첫 수렴에서 일정 색상180개가 정규화되어 warmup의 no-op 기대가 실패했다.
원본 실패 로그를 보존하고 test-only warmup을 준비 구간으로 옮겼다. 이 원본 실행 전체를 후속 성공으로 바꾸지 않는다. 이후 준비 구간 보정과 실제 비교 결과는 별도 로그에 남아 있다.

## 통합 9영역 결정

제품의 저장 의미·화면 상태를 보존하면서 비용이 확인된 경로를 채택했다. 아래 유지 결정도 조사 결과이며 기능 제거·안전 검사 생략이나 새 장기 cache를 일괄 적용하지 않았다.

| 영역 | 채택·구현 | 유지·거부 결정 | 증거와 남은 범위 |
|---|---|---|---|
| 1 시작·복귀·탭·무결성 | S1 positive-only backfill, pending/freshness 공통 reader 보완, S2lite, S4, S2batch default 경로 | 비활성 revision·활성 탭 refresh, no-op command/archive skip, import 후 수렴·save/rollback 유지. 직접 public record와 explicit callback은 dynamic 조회. | 누락2760 backfill 약15.458초→0.501~0.522초. 일상 복귀·captured 완료·첫 화면과 다른 조건이다. 최종 UI10조건 first pair 완료; 요청 bundle invalid·fresh3 resource 제외·독립 UI 반복과100ms는 미검증. |
| 2 보드·상태·이월·진행 | 공통 reader 정확성 보완으로 pending 활동·진행·기록 값 보호 | 당일 완료 유지·이후 archive, 실제 완료/undo 시각, 이월과 checklist 독립 유지. BT2/3 projection cache, checklist 접기·메뉴 통합 미채택. | 서로 다른240작업의2-event getter3.78ms와 동일250-event history를240회 읽는549ms는 다른 조건. formatter240호출79.20ms만으로 layout 효과를 주장하지 않는다. |
| 3 저장 작업·입력어·루틴 | BT1 동일 query 결과 공유, BT4-A 준비된 library 값별 alias 정규화 재사용 | 일반 제목 입력 시 library 미준비, `/`·IME·순위·즐겨찾기·최신 실행 재조회·실패 초안·독립 Task 복사 유지. TTL/sort/library dictionary·multi-date cache·메뉴 통합 미채택. | 1k library/100input batch −82.33%; 첫 slash 준비 +5.48%도 기록. 최신 safe Mac에서 NFD `/운동`·Down 선택·Return 적용·0/2 표시를 관찰했다. OS IME 조합·입력 지연과는 구분. |
| 4 캘린더·추천·템플릿 | C1 최신 active logical 대표→기간/visibility 및 범위 밖 최신본 조회, C2 **iOS 월 cell count** render-scoped projection | inclusive DayKey, linked Task·최신 template 확인, 추천200 pool/최대5·200ms debounce·generation·메모 보호·undo/retry 유지. 장기 layout/session cache·보조 UI 제거 미채택. | 35/42일×30/200/1000의6 paired 조건 digest 같음. iOS counts의 개선이며 Mac layout/wrap28ms·화면 frame은 별도. 실제 Calendar/Archive 두 앱 창 내용 보존과 narrow wrapping은 통과했다. Mac6주/긴 제목/+4 표시는 관찰했으나 좌표 클릭 뒤 상세 창 진입은 미확인; 큰 글자·접근성은 남았다. |
| 5 기록·활동·회고·사진 | A1 review-only refresh 조건부 index 보존, D1 Mac 제목/본문 우선·summary 접힘, S4 단일 첨부 inspection | exact pending signature/generation/coverage·task/unknown/import 무효화, 별도 ActivityOverviewReader, paging·search·선택 유지. MIME·size·decode·SHA·원본과 bounded thumbnail cache 유지. | 최종 A1 review-only −80.03%/−78.13%, task/unknown +1.59~2.06% 및 service control +5.17~6.56%. S4 100합성PNG 약47% 감소. 최신 safe Mac D1 저장·재열기/사진3개 관찰과 operation peak memory는 구분. |
| 6 메모·텍스트·체크리스트·스케치 | M1 adaptive100→512, cooperative session, saved ID paging/pending 부모·자식 overlay/clean freshness·drawing metadata, M2split512 | full body/checklist·페이지 깊이·취소/generation/retry, 600ms autosave/flush·draft/scroll/선택·세 생성 유형·PencilKit 원본 유지. **256 거부**, 스케치 삭제·전역 canvas cache·자동 텍스트 생성 미채택. | whole read 약3.26초, slice p95/max59.756/120.418ms;100ms 보장 아님. 실제 Session ready +2.23~7.10%. 이전12검사 중 기대1실패·test-only 보정2실패와 coordinate4실패를 보존했다. 메모6기능·정상 after-keyboard gate·actual Memo resize/side-by-side 내용 유지가 통과했고 큰 글자·접근성·입력 frame 검증은 남았다. |
| 7 Focus·알림·Live Activity·Intent | 기능 유지, hosted 상태 검증 및 이전 Mac Focus CUA 일부 확보 | timer/token/revision/deadline·paused time·checklist, 원자 lifecycle·실패 retry·stale Intent 거부 유지. 새 microcache 미채택. | candidates3.584ms/today summary0.124ms는 준비 함수. hosted state12/fake3 및 최신 safe Mac 시작·정지·재개·종료18초/휴식은 실제 OS 전달·장시간 수명·배터리와 구분. 종료 후 root 복귀는 미확인. |
| 8 위젯·Watch | C3 대표→visibility 정확성, W1 Watch 하루 summary. 추가 요청한 별도 오늘 일정 Lock Screen widget 및 unknown metadata/privacy/terminal 자정 처리 | 기존 kind·JSON format5·App Group·count/preview cap·Calendar8일 계약,150ms merge·sequence·동일 write skip·theme/import·자정 유지. | W1 actual n30의4조건 개선. 최종 hosted widget12·독립 Watch 두 build 통과와 signed 합성 seed는 실제 추가/render/tap/privacy/자정·standalone Watch runtime 통과가 아니다. W1 current-source 독립 반복 완료·최종 독립 리뷰 확인; 실제 Watch/잠금 화면 호스팅은 별도다. |
| 9 백업·병합·호환성 | B1 export invocation-local child grouping/attachment index 공유, 공통 reader 보완·S4 reconcile | **두 reconcile**, count/error/save 순서, 비파괴 merge·최신 대표·중복 수렴·DTO/codec/MIME/hash/path/rollback 유지. V1~V11·bundle/CloudKit/AppGroup/UTI 불변. | current export 10kTask −83.32%,1kTask −32.50%;100Task p95 +2.70%도 기록. 합성 hosted7과 기능 export/import 성공을 실제 사용자 백업·운영 migration으로 확장하지 않는다. |

S2batch의 Set은 callback 없는 `@MainActor` 동기 default 호출 한 번에만 유효하다. saved natural-key 권위 조회는 매번 fresh/uncapped이며 absence cache가 없고 즉시 insert primitive를 유지한다. autosave=true 4함수×2storage 검사·실제 명령 rollback·default/explicit false 동등성·205Task 경계와 callback 도중 외부 save를 통과했다. `contextID` assert는 mutation/reentrancy guard가 아니다. 미래 await/save/caller callback/raw mutation이 추가되면 이 닫힌 범위를 다시 검증하거나 dynamic 경로로 돌아가야 한다. untyped 함수 참조의 overload ambiguity는 소스 API 한계이며 저장소 호출에서는 발견되지 않았다. [독립 소스 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/S2batch-independent-prototype-review.md), [8조건 인수](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/S2batch-focused-acceptance-1.json).

initial full S2는 growing-pending에서 약2.09% 개선만 얻어 거부했다. Foundation range matcher 치환, 추가 보드/템플릿/날짜 cache는 현재 채택본에 넣지 않았다. 초기 probe의 출력 누락·bundle 직접 실행 실패와 메모256을 포함했던 이전 메뉴 후보 build는 후속 성공으로 덮어쓰지 않는다. 백업 두 번째 reconcile의 생략은 채택하지 않았다.

## 최신 성능 비교와 한계

아래 시간은 모두 ms다. 함수/서비스 구간·실제 원자 명령·협력 slice·화면 완료 시간을 구분한다. 각 독립 invocation은 따로 표기하며 n을 합산하지 않는다. 결과 digest 검증은 타이밍 밖이다. 실제 완료 harness의 canonical digest에서만 새 stop의 logical/physical UUID·createdAt/updatedAt clock과 completion의 physical UUID를 검증 후 역할로 정규화했고, raw digest에는 실제 생성값을 모두 남겼다. Task 필드·진행 stop occurredAt·완료 시각/dayKey/origin·old captured 값은 canonical에서도 실제값을 유지한다. 원본 bytes 보존 기대도 약화하지 않았다.

### S2batch: 실제 default backfill만

| 조건 / eligible | n / warmup 각 반복 | S2lite p50 | batch11 반복1 p50 / p95 | 반복2 p50 / p95 |
|---|---|---:|---:|---:|
| clean-already-captured / 100 | 30 / 1 | 7.533521 | 7.610458 / 7.919792 | 6.724750 / 7.243792 |
| legacy-missing-new-context / 100 | 30 / 1 | 32.299667 | 18.966104 / 20.992375 | 18.015917 / 19.236334 |
| clean-already-captured / 1000 | 10 / 1 | 77.175959 | 72.842041 / 75.219291 | 70.745104 / 75.085500 |
| legacy-missing-new-context / 1000 | 10 / 1 | 1320.951062 | 180.823021 / 254.657375 | 175.508250 / 181.368750 |
| clean-already-captured / 2760 | 5 / 1 | 233.852333 | 221.127083 / 221.627375 | 211.581000 / 212.436542 |
| legacy-missing-new-context / 2760 | 5 / 1 | 8905.752292 | 521.518417 / 523.531667 | 500.662959 / 546.898041 |

각 반복6개 name/eligible/n/digest가 baseline·S2lite와 같고 두 후보 실행은 PASS다. 누락100/1000/2760의 초기 baseline p50는35.911/2111.826/15457.661ms였다. clean은 규모별 prepared context를 반복 읽고 missing은 warmup/sample마다 새 context다. backfill만 측정해 save·fixture 준비는 제외한다. 첫 clean100 +1.02%는 반복2에서 감소해 작은 조건의 일관된 개선/퇴행으로 단정하지 않는다. n5/n10 p95는 여기서 maximum이고 안정적인 tail 보장이 아니다. 초기 baseline은6개 timing 출력 뒤 dirtyPending 별도 control4issues로 전체 실패했으므로 baseline 전체 PASS로 쓰지 않는다. [첫 측정·baseline 매칭](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/S2batch-first-measurement-review.md), [반복2 원본](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/batch11-backfill-2.log).

### B1: current export pipeline 독립 반복

| 부모 / Task | n | baseline p50 → candidate | Δ p50 | baseline p95 → candidate | Δ p95 |
|---|---:|---:|---:|---:|---:|
| 10 / 100 | 30 | 46.992375 → 46.263792 | −1.55% | 47.942917 → 49.237084 | **+2.70%** |
| 100 / 1000 | 30 | 657.955583 → 444.122292 | −32.50% | 664.855042 → 453.112875 | −31.85% |
| 1000 / 10000 | 5 | 29261.259875 → 4879.595500 | −83.32% | 29781.048292 → 4953.604875 | −83.37% |

3조건 payload digest가 같다. small100 p50 개선과 p95 증가를 함께 남기며, n5 p95는 maximum이다. current export pipeline의 채택 조합 결과를 grouping 하나의 효과로 전부 귀속하지 않는다. 사진/file dialog·작업별 memory는 측정하지 않았다. [원본/요약](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/batch11-backup-calendar-independent-repeat-summary.json).

### C2: iOS 월 cell counts 독립 paired 반복

| 일수 / storedEvents | n pairs | frozen loop p50 → actual projection | loop p95 → projection | Δ p50 |
|---|---:|---:|---:|---:|
| 35 / 30 | 30 | 2.422541 → 0.290625 | 2.543083 → 0.335875 | −88.00% |
| 35 / 200 | 30 | 16.378959 → 1.287083 | 17.903417 → 1.470750 | −92.14% |
| 35 / 1000 | 30 | 90.138834 → 5.942708 | 92.458958 → 6.739375 | −93.41% |
| 42 / 30 | 30 | 2.965333 → 0.345000 | 3.415916 → 0.464500 | −88.37% |
| 42 / 200 | 30 | 18.476583 → 1.373542 | 20.829417 → 1.541042 | −92.57% |
| 42 / 1000 | 30 | 103.609334 → 6.522458 | 106.565500 → 7.027250 | −93.70% |

logical ID가 unique인 canonical fixture, active30/194/968개·placements3/20/100개·Asia/Seoul이다. algorithm별 준비1회 후 순서를 교대로30pairs 측정하고6조건 digest를 동일하게 확인했다. 이 별도 invocation의 repeatLabel=2이며 independentInvocationCount=1이다. 초기 transient physical duplicate count83ms와 혼합하지 않고 Mac lane/wrap28ms, SwiftUI frame/input 속도로 확장하지 않는다. [원본 paired log](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/batch11-calendar-count-paired-2.log).

### 다른 채택 경로와 규모별 퇴행

| 경로·분모 | 결과 | 해석·한계 |
|---|---|---|
| S2lite 직접 record9조건: pending 증가/매번 fresh empty/이미 captured ×100/1000/2760 | growing2760 p50 wall15469.901→10173.854, CPU15433.021→10159.226ms. fresh empty2760 wall395.116→429.952(**+8.82%**), saved captured450.767→474.325(**+5.23%**). | name·count·sample·phase·digest로9조건을 매칭했다. 직접 dynamic 반복의 N² 비용은 남으며 default-only S2batch와 다른 경로다. CPU는 process CPU. 이 batch10 값을 post-S2batch public API의 새 계측으로 표시하지 않는다. |
| S2lite actual atomic doing→done: 1/100(n30),1000(n5) | perform+save wall p50:1.385438→1.291083 /84.178771→77.489688 /3877.846750→2830.121792ms. 단일 Task wall p95 **+1.51%**, CPU p95 **+8.82%**. | 준비1회·sample별 새 fixture, save 포함. saved started→stopped·completion·Task 전체 값과 independent reader/반복no-op/rollback을 시간 밖에서 검증했다. 총65samples/arm이며 transition 수가 아니다. |
| S4 actual public full reconcile:0/20/100 distinct1024×1024PNG,각n5 | 반복1 wall p50:1.034750→1.046917(**+1.18%**) /413.983167→208.642625 /2005.102042→1056.283667ms. 반복2:1.100959→1.028208 /435.566208→210.604833 /2019.803500→1078.879666ms. | warmup/sample마다 fresh local store; setup·image 생성/decode·fixture save 제외. 100PNG CPU p50도 반복1 약2004.838→1053.079ms. 두 pair full report/값 digest 동일, 각 store bytes/PID 보존. n5 p95는 **보고하지 않았다**. whole process RSS는 준비 포함이고 두 반복의 방향이 달라 memory 개선으로 쓰지 않는다. |
| M2split512:10k Memo+10k checklist,51,318,890 UTF-8 bytes,absent query,n30 | pooled slice p95/max101.237/204.785→독립 반복59.756/120.418ms. cooperative whole p503259.298ms,163checkpoints/read. | 전체 읽기는 약3.24~3.26초이며 split 자체의 추가 throughput 승리를 주장하지 않는다. clock/checkpoint instrumentation 포함. slice pool percentile은 read wall/frame percentile과 다르고 max가100ms를 넘는다. |
| M2-256:같은 expensive fixture,n30 | whole4011.952ms,slice p9562.718/max165.343ms,201checkpoints/read. | 512 대비 whole약**+24%**, slice tail 개선 없음으로 **거부**. 초기 원본6406ms와 비교해 채택하지 않는다. |
| 실제 MemoQuerySession:local2000rows,page40,empty/dense×depth1/5/10,n30 | refresh→ready p50가 sync 대비 **+2.231~7.099%**,6조건 full/published digest 동일. | async return0.007~0.010ms는 완료 시간이 아니다. yield/polling 비용 포함; UI frame·입력 latency 미측정. |
| A1 actual review-only Archive refresh | 1kTask/10kProgress n30:562.380→121.162ms;10k/100k n5:5955.713→1353.257ms. | 10조건 full/sample digest 일치. task/unknown 전체 refresh **+4~6%** 포함. 모든 Archive 동작의78% 개선으로 확장하지 않는다. |
| BT1/BT4 독립 반복:1k library/100input batch,n30 | p50828.413→146.357,p95870.048→155.612ms. first slash96.032→101.293(**+5.48%**),specific113.743→103.207ms. | 100-operation batch·library 첫 준비·한 keystroke/frame을 구분한다. 첫 준비 p95 약+6.1%도 원본에 남았다. |

분모·raw key·전체 출력은 [S2lite/S4 원본 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/S2lite-S4-measured-decision-review.md), [M2 독립 반복](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/batch8-memo-same-fixture-paired-2.log), [실제 Memo Session](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/batch10-memo-session-refresh-1-metrics-summary.json), [A1 실제 refresh](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/batch7-archive-refresh-1-metrics-summary.json), [빠른 입력 반복](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/quick-entry-repeat-decision.md)에 남겨 합성 규모별 이득과 퇴행을 함께 확인한다.

## 1차 전체 조사 범위 — 당시 기록

9영역의 1차 코드 조사 당시 방향을 보존한다. 현재 채택·거부·유지 결정은 위의 통합 결정표가 갱신한다.

| 영역 | 조사 증거 | 당시 방향 |
|---|---|---|
| 시작·복귀·탭·무결성 | `results/startup-focus-widget-audit.md` | 기존 비활성 revision/범위 재사용 유지; 실제 수렴·snapshot 비용 분리 |
| 보드·상태·이월·진행 | `results/board-template-audit.md` | 데이터 의미/undo/체크리스트 독립 유지, 준비·표시 비용 추가 계측 |
| 저장 작업·입력어·루틴 | 같은 audit | BT1 및 최신 실행 재조회 유지; 여러 날짜 적용 후속 계측 |
| 캘린더·추천·템플릿 | `results/calendar-audit.md` | C1 정확성 우선, C2 반복 계산 후보; 추천200/5 제한·초안/Undo 보호 유지 |
| 활동·회고·사진 | `results/memo-archive-backup-audit.md` | 기존 ModelActor/thumbnail cache 유지, 깊은 검색/페이지와 무효화 비용 평가 |
| 메모·필기 | 같은 audit, `results/memo-design.md` | M1부터 검증; 600ms autosave·flush·실패 draft·스케치 원본 보존 |
| Focus·알림·Live Activity·Intent | startup audit | 원자 저장·timer/token·failure 보존, bounded query 비용 확인 |
| 위젯·Watch | startup audit | 기존150ms 병합/sequence/동일쓰기 생략 유지, pure CPU와 쓰기/reload 구분 |
| 백업·병합·호환성 | memo/backup audit | B1; package V10/schema V11/UTI/비파괴 merge 유지 |

## 검증과 남은 작업

- keyboard UI 추가 전의 정상 gate, hosted34/0, 독립 Watch Debug·Release build 통과는 보존한다. 새 MobileMemoView 이후 정상 after-keyboard gate도 일반 Debug725/27.380초·Release694/24.138초와 전체 platform script exit0로 완료했다. native-preset test-only build의 첫 self capture 오류는 수리 build exit0 뒤 actual4검사도 모두 통과했다. 이 기능 검사 전체시간을 frame latency로 해석하지 않는다.
- 새 keyboard source의 메모6기능은 모두 통과했다. 원래 cooperative 검사78.049초·drawing42.813초, 실패 초안/retry·재열기/삭제를 포함한다. 이전12기능11/12와491.801초 finalization stall 후SIGINT→SIGTERM(exit−15), query-submit 보정 실패와 Cancel-name 보정 실패(exit65씩)는 과거 실패로 보존한다.
- iPad26.5 초기9개는3통과/4Dock 준비 실패/2skip이고, window-coordinate affected4 재실행도 exit65(3Dock 준비 실패·1Memo64pt accessory 조건 실패)였다. 새 test-only native-preset Sendable source의 실제4검사는 owned iPad reboot 후 모두 통과했다. 제품247개·반응성 suffix와 기존 width/content/full predicate는 유지했으므로 앞선 Dock/icon 준비 실패를 제품 내용 보존 실패로 분류하지 않는다. 첫 compile 오류·UI 시작 전 install MIG 대기0실행/−15·iPad27 초기 runner2재시작·3assertion실패·2통과·2skip·588.230초 finalization stall/−15 및 raw 첨부는 계속 보존한다. bigText/VoiceOver2skip을 통과로 바꾸지 않는다.
- 메뉴/첫 로딩 기존5+신규5는 양쪽10검사 exit0/실패0인 첫 pair와 전체 entity 내용 해시 일치를 확보했다. 유한한9 clock+2launch native 행은 개별 비교하되, 양쪽 요청 metric 묶음은 Archive signpost1건·hitch6조건 누락/지원 미확인으로 `invalid`다. 최초 기록·캘린더·메모3조건의 앱 CPU·메모리 대상 연결/구간 peak를 개선 근거에서 제외한다. first pair의 증가·감소를 아래 함께 기록했으며 독립 UI 반복과 100ms 첫 반응·frame·배터리 인수는 남았다. current-source A1/W1 독립 반복4command는 모두 실제 검사 PASS/exit0와 raw 완료를 확보했다. 아래 Core elapsed 표와 UI 첫 pair는 다른 측정 범위다. 거부256 또는 기존 iOS27 기능 시간을 이 pair 성능으로 합산하지 않는다. [PID 감사](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu-fresh-process-pid-audit.md), [파서 독립 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu-metric-parser-review.md).
- iPad 실제 resize·side-by-side Board/Focus·Calendar/Archive·Memo·narrow wrapping4검사는 통과했다. 성공 native 첨부26개 중11PNG를 직접 보았고 원본/SHA를 보존했다. 큰 글자/VoiceOver·Mac OS IME·일부 날짜/복귀 인수와 standalone Watch runtime은 남았다. current-source A1/W1 Core 독립 반복과 최종 독립 리뷰는 완료됐다. owned Watch26.5 `06FE96DC…`의 boot·bootstatus·install·안전 group container 조회는4exit0이나 launch·extension runtime access·snapshot 공유·실제 화면은 미검증이다. Mac은 일부 actual 조작 후 CUA가 명시적 잠금 오류를 반환해 중단됐으며 root 잠금 해제 요청을 기다린다.
- owned signed Simulator의 App Group 등록·오늘3일정/긴 기간 합성 seed와 hosted widget12 통과는 확보했다. 실제 Lock Screen 위젯 추가/render·긴 제목/기간·privacy·tap/deep link·자정·iPad accessory 검증은 수동 진입 대기이며 PASS가 아니다. Apple 공식 문서는 accessory를 앱 실행 후 수동 추가하도록 안내하고 `_XCWidgetFamily`는 accessory가 아닌 크기만 명시한다. 일반 extension Run이나 합성 Preview를 실제 세 잠금 화면 family의 대체 인수로 쓰지 않는다. [공식 문서 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-lockscreen-widget-run-official-docs-review.md), [Apple Debugging widgets](https://developer.apple.com/documentation/widgetkit/debugging-widgets). 위젯은 SwiftData/CloudKit을 직접 열지 않는 경계를 유지한다.
- 100ms 입력 첫 시각 반응·실제 frame/작업별 peak memory는 아직 검증하지 않았다. n5 tail·협력 slice·XCTest IPC/wait·AX audit collector·snapshot reload closure를 frame latency·spoken VoiceOver·실제 OS reload/delivery로 사용하지 않는다. 실기기 배터리·실제 알림 전달·운영 CloudKit 왕복·장시간 수명은 별도 외부 인수다.
- 이 문서 갱신은 상태·소스·원본 계측 artifact 읽기만으로 작성했다. 새 build/test/perf/UI·실제 사용자 데이터 접근은 하지 않았다. 커밋·push·PR·버전 증가·TestFlight는 이 Goal에 포함하지 않는다.

아래 중간 기록은 각 실행 시점의 상태·실패·미채택 판단을 그대로 보존한다. 이후 채택/통과 여부는 위의 최신 표와 해당 후속 원본 증거가 갱신하며 과거 실패를 성공으로 바꾸지 않는다.

## 1차 개선 검증 중간 기록

- 고정한 experiments/batch1-source에서 관련 검사175개가 통과했다. C1 기준 실패 반례, 빠른 입력 최신 선택·Observation, 메모 페이지 경계, 백업 payload·첨부·부모 순서·저장 경계를 포함한다.
- M1 첫 비교: 10k 무결과 검색 n30 중앙값1,159.94ms/p95 1,191.44ms, 기준2,617.23/2,762.32ms와 digest 일치. 바로40개가 일치하는 검색은 n5 중앙값12.73→31.11ms로 느려졌다. 첫100개 후 희소할 때512개로 확장하는 대안을 검증한다. 남은1.16초 동기 점유는 취소·협력 실행 후보이며 UI 개선으로 단정하지 않는다.
- 합성 Mac 회고 창은 작업 요약이 펼쳐져 제목이 첫 화면 하단, 본문은 그 아래로 밀렸다. 제목·본문을 먼저 배치하고 요약을 접는 D1을 채택했다. 수동 펼치기·사진·저장·실패 초안·연속 작성을 보존하며 후보 화면 확인 전 완료로 표시하지 않는다.
- BT1/B1 전후 비교, C2 월 count projection, 깊은 메모 refresh·필기·활동 무효화와 Widget/Watch 대표 반례가 다음 검증이다.

Mac 증거: results/mac-baseline-ui-findings.md와 mac-baseline-*.json/png. 기준 UI CPU/IPC 포함 clock/peak physical memory는 results/baseline-ui-metrics.json에 분리했다. 후보 UI·hosted 검사·최종 플랫폼 gate는 남아 있다.

## 2차 계측·검증 기록

- M1 adaptive 및 C2 고정 소스 관련66검사 통과. 첫100개 후 희소할 때512개로 확장하여 dense10k 첫page는13.87ms(기준12.73ms, n5), 무결과는1,171.46ms(기준2,617.23ms, n30)였다. 최초512안의31.11ms 회귀를 줄였으나 작은 조건/p95 잡음 및 약9% dense 증가는 독립 반복과 최종 비동기 경로에서 추가 확인한다. 모든 메모 search 결과 digest 일치.
- C2 canonical35/42일 × 30/200/1000일정 30쌍 비교 통과. 42일1000개는 frozen cell loop95.55ms → 실제Core projection6.12ms, 35일은81.68→5.96ms. 기준 사본의 같은 canonical 결과 digest와 모두 같았다. UI frame 지연 개선으로 해석하지 않으며 별도 반복/화면 검증은 남아 있다.
- baseline lifecycle warmup 수정 후 전체 opt-in검사 통과. steady startup integrity3000은 n5 중앙값1,571.24ms. unchanged archive reentry0.368ms, Focus candidates3.584ms, today summary0.124ms. 이 경로에는 기존 최적화를 유지한다.
- 메모2000 깊이10 동기 refresh n30은 empty64.89ms/dense92.97ms. 페이지깊이·선택identity·각sample digest 검사가 통과했고 M2협력 실행과 전후 비교할 기준이다.
- Widget/Watch 최신대표 반례: 기준6중4실패16assertions, 추가LockScreen/Watch1실패. superseded/latest 및 distinct logical ID controls통과. C3구현 중이다.
- M3필기 CLI 첫 실행은 PencilKit replica preferences의 nil bundle ID로 signal5, 번들 실행기 시도는 Testing.framework 로딩 경로에서 실패했다. 실제 필기 비용은 아직 얻지 못했다. 원본 crash와 시도 로그를 보존하며 전용ID와 명시framework환경으로 안전한 대안을 확인한다. 제품 필기 실패로 분류하지 않는다.
- Mac 화면검사 뒤 예상 밖으로 raw diagnostic build 산출물의 별도PID57704(보이는argv에UIflag없음)를 발견해 종료했다. 원인/저장소접근여부는 확인하지 않았고 실제 저장소를 검사하지 않았다. 이 격리 한계는 results/diagnostic-process-followup.json에 기록했다. 이후 diagnostic소스사본은 모든 관련 argument검사를UIfixture상수로 고정해 인자가 없어도 memory/preferences/Focus/widget안전경계가 적용된다. 안전사본build통과, 추가실행은미실행이다. 일반production/baseline소스는이용도를위해변경하지않았다.

## 3차 계측·안전 검사 기록

앞선 상태 표는 당시 중간 기록이다. 아래 결과도 최종 검증을 뜻하지 않는다.

- BT4는 alias의 고정 정규화 결과를 라이브러리 세션에서 준비한다. 1,000개에서 입력 변경+후보 읽기100회 n30 중앙값은 기준828.41ms → 후보142.63ms였다. 순위·선택 digest가 일치했다. 최초 `/` 전체 출력까지 포함한 준비 비용은90.89→97.75ms, 특정 `/perf12`는107.41→97.97ms였다. 일반 제목은 라이브러리를 준비하지 않는다. 준비 비용을 포함하지 않는 이전 update-only 표본은 이 비교에서 제외한다. 최초 전체 목록의 약7.5% 증가와 후보 max128.84ms는 독립 반복에서 재검토한다.
- M2의 실제 협력 scanner 검사에서 10k memory/긴 Unicode 조건 n30 wall 중앙값3,064.87ms, slice 중앙값18.37ms/p9592.43ms/max122.11ms, 제어된 checkpoint 취소부터 작업 종료까지 중앙값0.652ms였다. 이는 기존 M1 local-file/body fixture와 다른 조건이며 전후 개선율로 사용하지 않는다. 같은 fixture의 동기·협력 처리를 추가 비교한다. UI 첫 반응·프레임 시간을 측정한 결과도 아니다.
- M2 회귀 묶음은 통과하지 않았다. 동일 saved Memo에 미저장 본문을 두 번 변경한 단독 검사에서 `makePage`의 중복 physical instanceID dictionary가 trap했다. 부모/자식 변경7사례와 clean 동기 oracle6사례는 개별 통과했다. 기존 동기 baseline에도 있는 offset/pending 조회 문제인지 새 비동기 경로의 문제인지 최소 재현과 raw descriptor로 구분 중이다. 결과 dedup만으로 cursor 누락을 감추지 않는다.
- 기존 backfill dirty control은 기준에서도 실패했다. 같은 context의 `includePendingChanges=false` model fetch 뒤 기존 Task의 미저장 완료일·상태·superseded 값이 저장된 값으로 돌아갔다. 기본 fetch와 별도 context reader/일반 저장 명령 control은 통과했다. clean/missing 여섯 계측 조건의 digest는 맞았지만 전체 baseline backfill 검사는 실패이므로 전체 통과로 표시하지 않는다. 다른 활동·진행·Focus·기록 조회와 무결성 경로에서도 같은 SDK 동작을 검사 중이다.
- A1 기준: 실제 ArchiveQuerySession의 회고만 변경한 refresh는1k Task/10k progress n30 중앙값562.38ms,10k/100k n5는5,955.71ms였다. unchanged reentry는각0.010/0.028ms였다. task progress cache의 소유·무효화 개선 구현 후 pending/cancellation/실패/페이지 상태와 같은 fixture의 후보 비교를 수행한다.
- M3는 전용 ID/무권한 번들 실행기로 실제 PencilKit 검사를 완료했다. 작은/중간/큰 필기의 serialize 중앙값0.025/0.260/1.998ms, decode0.040/0.311/2.140ms,240px bitmap1.144/1.022/3.456ms였다. 원본 bytes·geometry·pixel 검사가 통과했다. 실제 canvas callback 또는 표시 행의 반복 빈도는 측정하지 않았고 추가 cache는 채택하지 않는다. 앞선 CLI/프레임워크 실패는 제품 오류로 분류하지 않는다.
- W1 기준 paired 가설은20/240개 Task와2/180개 입력 일정의 네 조건 모두 digest가 같았다. 실제 Watch day fetch와 같은20 Task/2입력 일정에서8일 집계0.824ms→하루 집계0.329ms,240/2에서는14.687→9.063ms였다. Watch의 하루 집계 구현을 별도로 검증하고 실제 production API로 반복한다.

### 오늘 일정 잠금 화면 추가

사용자의 후속 요청에 따라 별도 `PlanBase 오늘 일정` 위젯을 구현했다. 기존 위젯은 유지하며,
inline은 첫 일정·잔여 수, circular은 전체 수, rectangular은 제목 최대 두 개·종일/기간·잔여 수를 표시한다.
현재 모델에는 일정 시각이 없으므로 시각을 합성하지 않는다. 클릭은 오늘 캘린더로 이동한다.
calendar-only snapshot, 전체 count와 capped preview, 읽기 실패와 확정0개의 구별, 자정 timeline,
개인정보 숨김 시 접근성에서도 상세 제거를 검사한다. Core와 실제 publication의 hosted 검사는 준비됐고
아직 실행하지 않았다. 전용 Simulator의 실제 extension 화면과 최종 빌드가 남아 있다.
사용자가 잠금 화면에서 위젯을 한 번 직접 추가해야 하며 실제 기기의 장시간 갱신은 별도 인수다.

### Mac 진단 격리 후속

인자 없는 실행도 fixture로 강제하는 safe source overlay의 앱은 별도 runtime ID로 실행했다.
CUA 접근성·스크린샷에서 회고 제목과 본문이 요약 아래로 밀리는 기준 화면과 메모 글 생성·Unicode 자동 저장을 확인했다.
이전에 사용한 두 raw diagnostic bundle은 원래 Info.plist를 보존한 뒤 LaunchServices 등록과 실행 경로를 비활성화했다.
실제 사용자 저장소를 조사하지 않았으므로 앞선 예상 밖 PID의 저장소 접근 여부는 계속 미확인이다.
safe 진단 증거는 `results/mac-safe-baseline-ui-*`, 비활성화 이력은 `results/unsafe-diagnostic-launch-disable.json`이다.

### 계측 프로세스 점검 보완

시작 경로의 대소문자와 OS가 반환하는 `PlanBase` 경로가 달라, 기존 exact-path 검사에서 강제 memory 진단 앱 PID76547이 남은 것을 놓쳤다. 관찰 시 CPU는0.0%였으나 과거 background 작업 부재를 추정하지 않는다. 해당 프로세스만 종료하고 대소문자에 안전한 검사로 보완했다. 17:27:48 이후 batch3 다섯 중간 계측(빠른 입력 준비·입력·협력 메모·refresh)은 독립 반복 전 잠정 수치로 취급한다. `results/safe-mac-process-guard-case-fix.json`과 새 반복 로그로 구분한다. 제품/사용자 앱을 종료하지 않았다.

## 격리 재측정: 18:00–18:08

별도 진단 Mac 앱 종료 및 대소문자 무관 프로세스 검사 후 측정했다. 아래는 원본 로그의 독립 실행이며, 앞서 표시한 batch3 잠정값을 덮어쓰지 않는다. 새 파생 `*-metrics-summary.json`은 원본 표본을 보관하는 log의 요약이다.

- 빠른 입력 BT4: 1,000개/100번 실제 input changes median **146.357ms**, p95 155.612ms, max 193.333ms. 최초 baseline 828.413ms 대비 약 **82.3%** 감소. 준비 후 결과를 읽는 동일한 30회 독립 실행이며 순위/선택 digest 일치. 한 글자의 시각 반응이나 프레임 목표와는 별도다.
- 라이브러리 준비 포함 최초 `/`: 1,000개 baseline 96.032ms → candidate 101.293ms(+5.5%), p95 100.086→106.158ms(+6.1%), max 101.324→106.422ms(+5.0%). 최초 specific `/perf12`: 113.743→103.207ms(-9.3%). 100개 전체 9.126→9.578ms(+4.9%), specific10.888→9.457ms(-13.1%). ordinary input0.001ms, 준비 없음, 값 digest 일치. 준비 비용을 입력 후 반복 개선과 별도로 평가한다.
- S1 완료 기록 보완: 이미 captured가 있는100/1,000/2,760개 median18.603/192.012/551.660→**7.277/75.234/227.820ms** (61%/61%/59% 감소). 기록이 없는 legacy 신규 생성35.911/2111.826/15457.661→37.261/2110.572/15812.433ms (약+3.8%/-0.1%/+2.3%). 신규 기록 생성의 O(N²) 본래 비용까지 개선했다고 주장하지 않는다. 전체 harness dirty/prefetch 한도/잘못된 ID·day/물리 tie/취소 rollback controls까지 통과. 원본 baseline harness 전체 실패는 별도로 보존하며 6개 clean timed digest는 일치.
- W1 실제 채택 구현: `batch4-watch-actual-1`은 잘못된 flag/filter로 선택 검사 0개였으므로 계측으로 사용하지 않는다. 수정한 `batch4-watch-actual-2` 실제 production Watch.make가20Task/2Event0.345ms,240Task/2Event9.942ms이고 full-array20/1803.531ms,240/18013.127ms. 기존 fixed label `actual-watch-eight-day`는 새 구현에서도 그대로 찍히지만 현재는 one-day production이다. baseline0.824/14.687/3.757/17.659ms와 full snapshot digest 일치. 독립 재현은 최종 source 안정 후 진행한다.
- M2 같은 fixture 대조의 원래 synchronous baseline: 10,000개/긴Unicode51,318,890UTF8bytes/체크리스트10,000/무결과 검색 n30 median **6406.407ms**, p95 6513.182ms, CPUmedian6371.832ms. independent sample 원본 `baseline-memo-same-fixture-paired-1.log`. 이전 M1 fixture나 candidate-only M2 fixture와 비율을 계산하지 않는다. 최신 candidate paired 비교는 미실행이다.

source별 최종 build와 pending model/query tests를 진행 중이다. 위 수치만으로 Goal 완료를 선언하지 않는다.

## 추가 반례: 외부 저장 최신 값과 yield 후 범위 확인

비교용 baseline v12에 실제 공개 API를 사용하는 `GoalSavedReaderExternalContextTests`와 `GoalTaskRecordInterleaveTests`를 test-only로 추가했다. 원 baseline 제품은 수정하지 않았다.

- 외부 context가 saved activity day/task/time 또는 clean Memo body/date를 저장하고 source context에 다른 Memo draft가 있는 실제4조건: 원 baseline은 모두 통과했다(`baseline-external-and-interleave-v12.log`). 조회 전에 원 registered clean 객체가 예전 값을 유지하고 있음을 합성 로그로 관찰했다. candidate batch5는 ID만 읽고 registered clean 객체를 반환해 activity day2결과가 없거나 oldday1값을 반환하고 Memo 최신본문 검색도 빈결과였다. draft는 보존했지만 fresh값 요구를 충족하지 못해 **채택 상태를 미검증으로 유지하고 수정**한다. saved page의 clean physical IDs만 대상으로 false model fetch hydration을 추가 중이며, dirty/deleted original PID는 이 model fetch에 포함하지 않는다. 이 generic public SDK primitive를 별도의 기존 baseline control로 compile/runtime검증한다.
- 실제 TaskRecord256행 페이지 yield에서257번째행 taskId를B로이동하거나 superseded: 원 baseline은 pending fields까지되돌려7issues, batch5는fields보존했지만최신scope에서탈락한행을A기록에포함해2issues. 최종현재pending/deleted와sourcepredicate를반영하는 TaskRecord return필터를수정했다. 동일검사통과전완료로표시하지않는다.
- batch5 selectedsafety61functions는51완료로그가보인뒤idlewait였다. own PID88624를sample하고종료, bufferedstdoutflush후Memo2appendgate cases만미완료임을확인했다. gate가checkpoint4만가정하지만denseappend가2checkpoints안에완료할수있는test-harness경계로조사중이다. 그밖Archive/Memo/원pending23cases의부분pass는완전회귀pass로집계하지않는다. original log/sample/stop.json 보존.
- batch5 최초compile3개test문법문제(optionaloffset/arrayexpecttype/Taskorder)는test-onlyoverlay로수정후236.83sbuild통과. 본문이나expectation을완화하지않았다.

## 최종 안전성 묶음과 hosted 재검증

- batch7 고정 소스의 optimized Core build와 iOS build-for-testing 통과. Foundation import와 throwing macro 두 문법 문제는 수정해 별도 실패 로그를 보존했다.
- pending/external-save/yield/메모 협력/Archive cache/위젯 timeline/Watch/backfill 관련 **115검사 통과**. 전체 optimized Debug-conditional 공통 실행은 **707검사 통과**. 아직 일반 Debug/Release 및 플랫폼 전체 gate의 대체 결과는 아니다.
- `batch7-ios-hosted-widget`는 앱 launch가 실패했다. test-only xctestrun 복사에서 상속된 PERFC/RPAC instrumentation을 제거하고 hosted app을 memory UI args로 고정해 실제 테스트 실행까지 도달했다. 이것만으로 초기 launch 원인을 확정하지는 않는다.
- `batch7-ios-hosted-widget-clean`의 새 publication 검사에서 helper-owned memory container가 해제된 뒤 caller가 CalendarEvent.instanceID를 읽어 SwiftData reset trap이 발생했다. 네 assertion 위치는 동일 fixture UUID 값으로 대조하도록 test-only 수정했다. 제품 publication 결과는 값 snapshot이며, 이 실패를 제품 저장소 손실로 분류하지 않는다. 전체 hosted 묶음은 수정 소스에서 다시 실행할 예정이다.
- Goal 완료, 배포, commit/push는 아직 수행하지 않았다. actual accessory extension 화면과 최종 성능/플랫폼 검증을 계속한다.

### Hosted와 Mac 실제 화면 후속

- test-only lifetime 수정 후 실제 hosted 34검사가 모두 통과했다. Calendar publisher/store/Widget 해석12검사와 backup/Live Activity/알림 관련 검사를 포함한다. forced UI mode가 notification fake도 차단하는 첫 실행은31통과/3실패4issues로 남겼다. 재실행은 기존 DEBUG notification fixture gate를 열어 fake client의 추가·취소 ID를 검사했으며, 실제 전달이나 기본 calendar trigger 타입 증거가 아니다. `hosted-repair-mobile-all-fixed.log/.xcresult`와 구성 SHA를 보존했다.
- 강제 memory/별도 runtime ID Mac의 회고 첫 sheet에서 제목·본문이 먼저 보이고 요약은collapsed였다. 실제 Command-S→계속본문작성→버튼저장→닫기/재열기 원문을 확인했고, 요약의7작업/이월 의미와사진3장중1→2전환이 보존됐다. Focus 시작·일시정지·재개·종료·휴식도 실제 UI로 확인했다. `results/mac-candidate-d1-ui-findings.md`와 CUA AX/screenshot transcript가 근거다.
- 사용자가 Mac을 잠금 해제해 화면 검증을 재개했다. 진단앱을 종료하고 소유 Simulator를 shutdown한 뒤 순차 성능 queue를 시작했다.

### S2 원인 분리 계측

- 공개 TaskActivityService.record(.legacyBackfill) 호출 구간만 합산한 baseline harness9조건 통과. pending 누적100/1000/2760 median33.104/2203.008/15469.901ms; 각호출새context·빈pending control14.522/144.650/395.116ms; 이미captured16.506/163.597/450.767ms. 100조건n30,1000/2760 n5,준비1회. 두insert조건의canonical출력 digest 일치. context준비·검증은측정밖이므로empty-pending시간을새 backfill 전체속도로주장하지않는다. fetch/SQL횟수는미측정.
- 큰비용은미저장객체가누적되는context조건과함께증가함을실측했다. Core자연키완전saved-ID조회와매호출currentpending/deletedoverlay를쓴S2시제품을별도파일에준비했다. absence cache/단순canonicalID/200prefix제한은사용하지않는다. 현재main제품은수정하지않았고시제품은미컴파일·미채택이다. origin/key/dirty/external-save/205중복tail/rollback/actualcapturedcompletion을검증·비교한뒤판단한다.

## 후속 검증 기록: batch7·batch8 준비

- batch7 optimized 전체 Core 검사 707개와 별도 안전 회귀 115개 통과. hosted 테스트 수명 fixture를 value ID로 보정한 뒤 모바일 전체 34개 통과(위젯 발행/store 12개 포함). 최초 hosted 환경 RPAC/PERFC launch 실패, fixture container 수명 trap, UI 테스트의 알림 억제 guard로 인한 세 검사 실패는 원본 로그와 함께 별도 보존했다. 전용 설정은 기존 notification-delivery DEBUG flag와 mock center를 사용하며 실제 전달 검증은 아니다.
- Mac 격리 앱에서 회고 제목/본문 우선 배치·저장 후 이어 작성·재진입 원문·사진 3장/2번째 전환·작업 요약 펼침을 실제 화면으로 확인했다. Focus 시작/정지/재개/8초 실제 집중 기록/휴식/건너뛰기 확인. 증거 `results/mac-candidate-d1-ui-findings.md`; 고정 fixture의 실제 알림/배터리 인수로 확대하지 않는다.
- 동일 51,318,890 UTF-8 bytes 메모 조건의 원본 sync 중앙값 6,406.407ms → batch7 sync 3,279.396ms/cooperative 3,285.882ms(n30). cooperative 119 checkpoints/읽기지만 slice p95 101.237ms/max 204.785ms가 남아 parent fetch와 child fetch의 분리 실험을 준비했다. 이는 화면 프레임/100ms 응답 확인이 아니다.
- 기록 review-only 새 비교: 1,000 Tasks/10,000 progress n30 중앙값 121.162ms, 10,000/100,000 n5 1,353.257ms. 변경 없는 재진입은 0.012/0.025ms, 실제 Task/unknown import 변경은 전체 refresh 600/6,216ms 수준을 유지한다. raw digests/locale는 `results/batch7-archive-refresh-1-metrics-summary.json`; 관련 baseline locale·전체 digests와 최종 비교 예정이다.
- 원본 실제 record .legacyBackfill에서 pending 증가 조건 2,760건 중앙값 15,469.901ms, per-key 새 context의 empty pending control 395.116ms. control은 context 준비/save가 제외된 진단으로 전체 backfill 개선율로 사용하지 않는다. batch8 prototype은 dirty context의 전체 natural-key saved identifiers와 현재 pending/deleted PID를 합쳐 존재 여부를 조회하고 clean path는 유지한다. 제품 채택 전 비교·회귀 대상이다.
- batch8 원본/후보 compile 통과 및 natural-key/origin·24 pending 조건·외부 writer 20조건·205개 초과 제외된 물리 복사본 뒤의 tail·rollback·Task 원자적 완료를 검사하는 7개 parameterized regression이 양쪽에서 통과했다. 후보는 아직 main 제품에 채택하지 않았으며 full suite/실제 완료 perf/새 메모 단계 검증이 남았다.
- 메뉴/초기 로딩은 첫 내용·메뉴 첫 진입·예열 후 내용 준비까지 측정하는 UI 시나리오 5개를 보강했다. 기존 prepared launch 지표 평균 5.172s(n5)와 4탭 전체 XCTest clock 9.410s(n10)는 탭당 입력 지연이 아니다. 새 시나리오는 아직 실행 전이다.

## UI 후속 기록 — 키보드와 iPad window 경계

- 최초 iPhone12검사는11통과/1실패였다. calendar-month-title 기대 실패 뒤 결과 수집491.801초 stall을 관찰해 해당 소유 xcodebuild에 SIGINT, 종결되지 않아 SIGTERM했고 exit−15와 원본 불완전 xcresult를 남겼다. [초기 종료](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-iphone-post-suite-finalization-terminate.json).
- 첫 test-only query-submit 보정은 새 메모 진입 helper의 label 매칭에서 실패(exit65), 두 번째 Cancel-name 보정은 keyboard 표시 뒤 탭 기대에서 실패(exit65)했다. 두 로그를 후속 성공으로 덮어쓰지 않았다. [보정1 원본](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-iphone-memo-query-repaired-ui.log), [보정2 원본](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-iphone-memo-query-repaired2-ui.log).
- 제품 MobileMemoEditorView 글 편집의 keyboard toolbar에 완료 버튼을 추가해 focus만 해제한다. 실제 UI 검사에서는 버튼으로 키보드를 닫고 Calendar→Memo 복귀, 저장 실패 초안 유지·retry·저장 재열기·삭제를 확인했다. cooperative78.049초를 포함한6개 함수 전체238.037초/실패0/exit0이며 drawing clear/type 보존도 통과했다. save 실패 주입·재시도 기대를 제거하지 않았다. 이 XCTest 전체시간은 입력/탭 지연이나 cooperative in-flight 취소의 성능값이 아니다.
- 최신 keyboard freeze의247개 생산 Swift는 manifest/main/frozen SHA가 같고 desktop29개는 이전 채택 UI source와 byte 동일했다. `MobileMemoView.swift` SHA=`29f80e47e457ab411f8ebf0b270bcfe2f726e188303d39125999550f53ca1411`. metric class SHA=`94cf9ae1582b882204888df3ba2e6e2d3817b4249d482d5441d04ffcfe1f2c00`과10methods 동일은 manifest 기록이다. old final gate/hosted/Watch 증거는 유지하고 새 모바일 UI의 정상 affected/final gate는 다시 확인한다.
- 전용 iPad26.5 F4EF93E7…는9개 실제 실행3PASS/4FAIL/2SKIP였다. rotation·checklist·quickentry는 통과했고 bigText/VO는 skip이다.4실패는 Dock Settings icon 준비707/944행으로 실제 side-by-side 내용/긴 일정 폭 검사를 통과했다고 주장하지 않는다. 원본 xcresult의 attachments를 [별도 export](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-ui-attachments)해 screenshot/AX 근거를 보존했다.
- iPad27은 두 runner 재시작 후 log summary7개 중2PASS/3assertFAIL/2SKIP였고,588.230초 post-suite diagnostic finalization stall을 끝내기 위해 해당 소유 xcodebuild만 SIGTERM했다.−15는 검사 통과가 아니다. Window coordinate helper는 orientation/floating origin 관찰을 반영한 test-only 시도로 production·metric methods를 바꾸지 않는다. 보정 build는 exit0/SUCCEEDED로 완료했으며 affected4UI 재실행과 final 결과를 기다린다.

## UI 후속 기록 — 21:38 native-preset 준비

- 위 당시 “affected4 대기”는 이후 actual 재실행에서 **4실패/exit65**로 확정했다. 3개는 frozen helper942행의 Settings Dock icon 존재 검사, Memo는 frozen666행의 keyboard-hidden 검사에서 실패했다. XCTest187.652초/xcodebuild190.046초다. 원본 log·status·107개 첨부는 보존하며 초기 adaptive9개와 합산하여 통과 수를 만들지 않는다.
- Board 원본 MP4의 native menu34/35s와 preset 직후36s를 실제 픽셀로 확인했다. 36s 요청의 실제 frame은 `21595/600=35.991667s`, test log의 후속 Dock swipe t36.07s 직전이며 PlanBase 왼쪽·Settings 오른쪽 두 반폭 창이 이미 보인다. swipe 뒤37/39s에는 PlanBase가 바닥에서 들어 올려진 창/카드 상태로 바뀌며 Dock icon이 없다. 새 좌표를 추측하는 대신 불필요한 추가 Dock 단계를 제거한다. [배치 직후 픽셀](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/ipad-windowing-second-retry-video-frames/board-36s.png), [원본과 전체 SHA/시간 근거](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/ipad-windowing-second-retry-review.md).
- Memo 영상25s에는 입력 본문·저장됨·전체 키보드가 보이고 native hide 뒤27/30s에는 같은 Memo 편집 화면/선택 본문/저장됨과 완료 accessory가 남는다. 64pt Keyboard 로그와 일치하지만 Main-only AX tree의 underlying Board를 Memo teardown 또는 새 데이터 오류로 해석하지 않는다. 제품의 focus 해제 버튼을 우선 누르고 native fallback 뒤 원래 keyboard-hidden 조건과 계속 입력/재열기 검사를 유지한다. [hide 이후 픽셀](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/ipad-windowing-second-retry-video-frames/memo-27s.png).
- root는 공통 helper와 Memo 중복 흐름의 Dock 단계만 제거하고 명시적 `memo-text-keyboard-dismiss`를 우선 사용하는 test-only source를 고정했다. 원래 width320…600·non-overlap·두 window hittable, keyboard-hidden·본문 전체값·추가 입력과 재열기 기대는 그대로다. native preset 직후 frame/settings/system tree/screenshot 첨부도 추가했다. Settings.activate 대안은 구현하지 않았다. native-preset build-for-testing은 진행 중이고 실제4검사의 후속 통과 여부는 미검증이다.
- 최신 native-preset manifest의247개 생산 Swift는 이전 window-coordinate 체크 SHA·main·새 frozen SHA 모두 같고 반응성 class suffix SHA=`94cf9ae1582b882204888df3ba2e6e2d3817b4249d482d5441d04ffcfe1f2c00`도 byte 동일이다. 이는 source 확인이며 새 binary의 build 성공이나 actual UI 성공을 뜻하지 않는다. 메뉴10조건 실행 계획의 candidate는 완료된 window-coordinate performance binary이며 제품247개/metric suffix 동일성을 별도로 확인했다. 새 functional helper build를 실제 metrics 결과로 바꾸지 않는다.
- 정상 after-keyboard gate는 일반 Debug725/27.380초와 Release694/24.138초가 통과한 뒤 앱 build 진행 중이다. 전용 Watch26.5 `06FE96DC-0C95-4259-BF5A-28569B4A4D36`는 생성만 했고 boot/install/launch는 없다. 메뉴10조건 명시적 선택자·환경 clean proof/preflight는 준비됐지만 실제 성능·fixture 진단은 미실행이다. Mac locked actual 검증과 실제 widget families 수동 인수도 대기다. 전체 Goal 완료로 바꾸지 않는다.
- **21:42 종료 상태 추가:** 정상 after-keyboard gate는 전체 exit0로 완료했다. native-preset 첫 build는 test643/867행 teardown `@Sendable` closure에서 `self.dismissAdaptiveKeyboard(in:)`가 non-Sendable XCTestCase를 capture해 compile 실패(exit65)했다. 검사 수행 전 실패이며 실제4검사의 새로운 window/content 결과는 없다. 최초 로그·상태를 보존하고 root의 test-only 보정과 후속 실제 실행을 별도 증거로 기다린다.

## UI 후속 기록 — 21:59 native-preset 실제 인수

- teardown에서 XCTestCase `self`를 capture하지 않고 동일 dismiss 동작을 inline한 Sendable 수리 source의 build-for-testing은 **exit0/TEST BUILD SUCCEEDED**다. 생산247개는 main·이전 candidate manifest·수리 freeze와 같고 반응성 suffix SHA=`94cf9ae1582b882204888df3ba2e6e2d3817b4249d482d5441d04ffcfe1f2c00`도 동일하다. 원래 width320…600·non-overlap·양쪽 window hittable과 모든 내용 기대를 유지했다. [수리 manifest](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/experiments/final-ui-native-preset-sendable-manifest.json), [build 성공2445행](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ui-native-preset-sendable-build.log:2445), [full sideBySide 원문](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/experiments/final-ui-native-preset-sendable-source/mobile/Tests/PlanBaseLaunchUITests.swift:939).
- 첫 actual4 실행은 **UI test 시작0개**인 상태에서 CoreSimulator `installApplication`/`host_support_mig_install_app_with_info`에265.417초 대기했다. 소유 xcodebuild의 stack sample과 원본 불완전 xcresult를 보존하고 해당 프로세스에만 SIGTERM, wrapper exit−15를 기록했다. 설치 대기를 기능 검사 실패4개 또는 runtime 데이터 실패로 세지 않는다. only-owned F4EF93E7… iPad만 shutdown→boot했고 erase 없이 같은 source/binary로 재시도했다. [중단 판단/동작](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-install-wait-stop.json), [실제 stack58행](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-launch-wait.sample.txt:58), [최초 실행 종료](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-functional-status.json).
- 재시도는 **4검사/실패0, XCTest283.243초, xcodebuild292.931초, exit0**다. Board/Focus85.700초, Calendar/Archive94.272초, Memo 실제 resize/tiling58.640초, 실제 narrow calendar wrapping44.631초 PASS. 입력 초안 이어쓰기·한 Task/일정 유지, Focus 진행/중지 값, 회고 검색/날짜/필터, Memo resize/동시 창 계속 입력/재열기와 캘린더 폭 기대를 검사했다. 소유 Settings를 나란히 실제 배치하고 본래 full frame/content predicate를 통과했으며 추가 Dock 단계만 없앴다. 이 XCTest 전체시간은 메뉴 입력 latency·frame 개선율이 아니다. 이전4실패를 덮어쓰지 않고 준비 단계 보정 후 실제 인수 증거로 구분한다. [각 통과와 최종 summary](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-reboot-functional.log:1519), [실행 종료](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-reboot-functional-status.json).
- 별도 owned Watch safe Debug build는 exit0/BUILD SUCCEEDED다. 실제 app·extension의 `codesign --verify --strict`는 양쪽 exit0이고 이 Simulator binary의 signature XML entitlements는 `{}`다. 최초 signature-only group lookup의 키 누락은 진단 방식의 한계였다. 실제 Mach-O `__TEXT,__entitlements`에는 두 bundle 모두 `group.com.soraul2.planbase.goal.run154826ab8b66.watchruntime` 진단 group이 일치한다. 이 static 확인은 runtime group 등록을 확인한 결과가 아니며 **boot/install/launch 미실행**·실제 standalone Watch/컴플리케이션 대기를 유지한다. [safe Debug 종료](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-runtime-safe-debug-build-status.json), [actual binary SHA/서명/section proof](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-runtime-safe-signed-bundles.json).
- 메뉴10조건은 아직 실제 metrics 결과가 없다. 실행 계획의 candidate는 window-coordinate performance binary로, 이후 기능 helper 수리와 무관하게 최신 제품247개와 동일 반응성 suffix를 포함한다. 명시적10선택자·같은 runtime/SDK·clean UI target 조건과 fixture 진단이 필요하며 실제 전후 pair를 실행하기 전 두 역할을 성능 PASS로 만들지 않는다. Mac locked actual 검증·실제 widget families 수동 인수·큰 글자/VO skip·W1 독립 반복도 그대로 남았다. 전체 Goal은 진행 중이다.

## UI 계측 후속 기록 — 22:24 baseline 완료

- 실제 baseline은 **10검사/실패0, XCTest856.572초, xcodebuild863.888초, exit0**다. 이는 전체 검사 실행 시간이며 단일 메뉴 latency가 아니다. candidate는 session50142에서 단독 계측 중이며 이 checkpoint에서 완료·개선율을 주장하지 않는다. [실제 baseline summary2344행](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-baseline-ui-metrics.log:2344), [baseline 종료](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-baseline-ui-metrics-status.json), [candidate 진행](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-candidate-ui-metrics-status.json).
- 최초 owned fixture 감사는 `Unverified SwiftData entity/table mapping: CHANGE`로 **exit1 안전 중단**했다. 실제 owned schema catalog는 `ACHANGE`·`ATRANSACTION`·`ATRANSACTIONSTRING` 세 persistent-history table을 증명했다. v2는 명시적 mapping과 nonempty-row `Z_ENT` 확인을 추가하고 기존 소유 기기·경로·symlink·read-only/query-only·transaction·출력 제한을 유지해 **exit0/`countsMatch=true`**다. Task3000, progress6000, completion activity2760, template1000/item1000, event180, Memo200이며 나머지 제품 모델은 모두0이다. 각 entity의 전체 행 해시는 확보했지만 두 역할의 내용 동일성은 candidate 감사 전까지 미검증이다. 날짜 근거는 per-test localMidnight/timeZone/오늘 작업0000 기대이며 SQL 날짜 열을 추정하지 않는다. [최초 중단 로그](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-baseline-fixture-audit.log), [owned catalog](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-baseline-fixture-catalog.json), [v2 감사 결과](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-baseline-fixture-audit-v2.json), [v2 소스·guard proof](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu-fixture-audit-v2-source-proof.json).
- baseline raw JSON은 **10records**, SHA=`09de64598dabbfff4ff341f119055a2e50dae0a6110ed4be57acee43ed4285bd`다. 유효성 결과의 `invalid`는 요청된 전체 지표 묶음의 판정이다. `testRepeatedTabNavigation`의 Archive signpost 누락1건(error), hitch 미수신 또는 미지원 미확인6조건(review), 메모리 변화량0 관련4건·음수 변화량5건(info)이 남았다. info9건은 유효한 변화량일 수 있어 오류·0값 대체로 취급하지 않는다. 9개 clock 행과 launch2행(PreparedStoreLaunch·PreparedStoreInitialContentLoad)은 각각 예상 n5/n10·유한성 검사의 `numerically_valid_with_external_limits`이며 full bundle 성공·PID 연결·100ms 첫 frame을 증명하지 않는다. hitch 누락을0으로 채우지 않고 n5/n10 nearest-rank p95가 최대 표본인 한계를 유지한다. [원시10records](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-baseline-ui-metrics.raw.json), [기존 export proof](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-baseline-metrics-export-proof.json), [원시 유효성 결과](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-baseline-metric-validity.json), [파서 독립 검토 SHA32cfee…](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu-metric-parser-review.md).
- 최초 기록·캘린더·메모3조건은 각6건, 총18건의 peak reset 실패가 있고 reset 경고 PID와 후속 종료 로그의 앱 PID가 다르다. 매 새 앱 PID에 CPU·메모리가 연결됐다는 증거가 없어 해당3조건의 앱 CPU·메모리 개선 확정과 수동 구간 peak 비교를 제외한다. CPU provider 내부 실패를 단정하거나 다른 warm/launch/clock 행까지 자동 폐기하지 않는다. 숫자 sanity, 화면 준비 기대, 요청 지표 누락, 대상 프로세스 검증을 따로 유지한다. 원래 iPad4 기능 oracle 보존은 별도 정적 검토로 확인했고 기능 전체시간을 성능 표본으로 바꾸지 않는다. 전후 효과·동일 fixture 내용 해시 및 A1/W1 current-source 독립 반복은 아직 없다. [PID 감사 SHA93df30…](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu-fresh-process-pid-audit.md), [iPad oracle 검토 SHA6178ad…](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad-native-preset-oracle-review.md).


## UI 계측 후속 기록 — 22:36 first pair 완료

candidate도 **10검사/실패0, XCTest838.294초, xcodebuild840.285초, exit0**로 종료했다. raw10records SHA=`5109ca25f2207671073218be7b1ece6b5cd6c6f91cab209d31b5e0ab6e41ccb2`이며 baseline raw SHA=`09de64598dabbfff4ff341f119055a2e50dae0a6110ed4be57acee43ed4285bd`와 별도로 보존한다. 양쪽 validator는 같은 Archive signpost 누락1건·hitch6조건(review)으로 전체 요청 묶음 `invalid`, info는 변화량0 관련4건·음수 변화량5건이다. 기능 PASS·숫자 sanity·전체 묶음 유효성은 다른 판정이다. [candidate summary2342행](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-candidate-ui-metrics.log:2342), [candidate raw10](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-candidate-ui-metrics.raw.json), [candidate 유효성](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-candidate-metric-validity.json).

이 표는 **같은 owned iPhone/runtime에서 완료한 한 번의 matched pair**다. 각 행은 원래 `Clock Monotonic Time, s` 또는 `Duration (ApplicationFirstFramePresentationResponsive), s`의 median(p50)이며 서로 다른 metric·메서드를 합치지 않는다. 양쪽 표본 수를 별도로 적었고 9clock+2launch=11행은10개 공개 테스트에서 나온다. 변화율은 반올림 전 원시 median의 `(candidate/baseline−1)×100`이다. [전체 원시 pair·p95·제외 기록](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-metric-pair-comparison.json).

| 조건 | native metric | n baseline / candidate | p50 초: baseline → candidate | 변화 |
|---|---|---:|---:|---:|
| 초기 내용 준비 | clock | 5 / 5 | 7.273 → 6.873 | -5.51% |
| 같은 검사 responsive signpost | responsive signpost | 5 / 5 | 3.777 → 3.461 | -8.36% |
| 기존 launch responsive signpost | responsive signpost | 5 / 5 | 3.705 → 3.447 | -6.98% |
| 최초 Calendar 내용 준비 | clock | 5 / 5 | 3.273 → 3.268 | -0.17% |
| 최초 Archive 내용 준비 | clock | 5 / 5 | 4.655 → 4.649 | -0.14% |
| 최초 Memo 내용 준비 | clock | 5 / 5 | 3.140 → 3.088 | -1.66% |
| 기존 warm4탭 전환 | clock | 10 / 10 | 6.482 → 6.722 | +3.70% |
| warm4탭 내용 준비 | clock | 10 / 10 | 13.063 → 13.011 | -0.39% |
| 보드 스크롤 | clock | 10 / 10 | 5.345 → 5.500 | +2.90% |
| 저장한 작업 추천 입력 | clock | 5 / 5 | 2.854 → 2.488 | -12.85% |
| 작업 상세·Focus 진입 | clock | 5 / 5 | 7.134 → 7.200 | +0.92% |

- 스크롤의 앱 CPU Time p50은1.080→1.138초(**+5.45%**), Memory Peak Physical p50은63,474.064→54,544.784kB(**−14.07%**)다. 추천 입력은 CPU1.486→1.203초(**−19.01%**), peak57,706.920→59,492.776kB(**+3.09%**)다. 감소와 증가를 함께 남기며 CPU·memory·clock의 native 의미를 바꾸지 않는다. p95에는 스크롤 clock **+3.76%**, warm4탭 clock **+0.43%**, warm4탭 내용 준비 **+1.21%**, 상세·Focus **+1.83%** 증가도 있다. n5/n10 nearest-rank p95는 각 최대 표본이므로 정밀 tail/지속적 퇴행의 확정치는 아니다.
- 두 fixture 감사의 **15제품+3persistent-history entity 전부** columns/count/full raw-row SHA가 같다(`allEntityFieldsEqual=true`, 양쪽 `countsMatch=true`). physical PK·UUID·`Z_OPT`·timestamps까지 포함한 저장 내용 일치와 per-test localMidnight/timezone/오늘 Task0000 기대를 확인했다. 컨테이너 UUID·store 경로는 다르고 감사 metadata는 oldStore 없음/newStore 있음을 기록한다. 같은 물리 경로를 주장하지 않는다. installer relocation은 내용 일치와 경로 변경에 근거한 추론이며 실제 메커니즘을 관찰한 증거는 없다. 초판의 “same installed data container” 설명 오류를 삭제하지 않고v2의 정정으로 구분한다. [오류 설명을 보존한 초판](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-fixture-pair-comparison.json), [전체내용·경로 비교 정정v2](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-fixture-pair-comparison-v2.json).
- 최초 Calendar/Archive/Memo3조건의 fresh-process CPU·메모리 전부와 구간 peak는 PID 재연결/초기화 미입증으로 개선 근거에서 계속 제외한다. 위 clock과 launch 수치는 보존하지만 OS responsive signpost, XCTest IPC·대기·내용 표시 기대를100ms 입력 반응·실제 UI frame·배터리 개선으로 사용하지 않는다. warm4탭 합계 clock을 한 번의 메뉴 tap 지연으로 나누어 해석하지 않는다. 같은 source A/B에는 여러 채택 변경이 함께 있어 한 개 변경의 인과 효과도 입증하지 못한다. hitch/Archive signpost 누락을0으로 보충하지 않고, 현재 first pair를 독립 UI 반복 완료로 바꾸지 않는다. current-source A1/W1 독립 반복은 준비/시작 예정이며 새 수치는 미확보다. [PID 감사](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu-fresh-process-pid-audit.md), [파서 독립 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu-metric-parser-review.md).


## Core 독립 반복 후속 기록 — 22:48 A1/W1 완료

baseline/current candidate 각각의 W1·A1 총 **4command가 finished/exit0이며 각 실제 선택 검사1개가 PASS**다. 0suite는 global Swift Testing 함수의 표기이며 검사0개 skip이 아니다. W1 전체 raw16행과 A1 raw20행이 완료돼 표본 수·유한성·원래 통계를 검증했고, W1 public4조건 full Codable digest와 A1 10pairs의 aggregate 및 순서 있는 모든 sample digest가 같다. 기존 첫 UI pair의10조건/원시값/누락 지표·PID 제한은 그대로 유지하며 Core 수치와 합산하지 않는다. [W1 repeat3 전체 raw·public 비교](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-current-watch-repeat-3-summary.json), [A1 repeat2 전체 raw·10pairs 비교](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-current-archive-repeat-2-summary.json), [4종료 상태·완료 시점 owned inventory](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-a1-w1-repeat-completion-device-proof.json).

W1은 저장 Task3000/Event180에서 입력으로 받은 Task20/240·Event2/180을 분리한다. 아래는 **public production branch끼리**의 n30·warmup1 비교다. baseline은8일 생성 후 첫 summary, current candidate는 실제 `makeTodaySummary` 한 날짜 경로다. frozen raw의 `actual-watch-eight-day`·`candidateKind=test-only-hypothesis` 문구는 보존됐으므로 candidate의 실제 경로를 그 label로 오해하거나 private helper 수치를 생산 결과로 대체하지 않는다. p50은 sorted30의 index15인 **상측 중앙값**이며 중앙 두 값의 평균을 쓰는 A1과 다르다.

| 입력 Task / Event | 입력 정책 | public p50 ms: baseline → candidate | 변화 |
|---|---|---:|---:|
| 20 / 2 | watch-bounded-day | 0.835584 → 0.361958 | -56.68% |
| 240 / 2 | watch-bounded-day | 14.665958 → 9.499125 | -35.23% |
| 20 / 180 | full-array-baseline | 3.800542 → 3.514792 | -7.52% |
| 240 / 180 | full-array-baseline | 17.655375 → 12.647750 | -28.36% |

W1 30 alternating pairs는 각 프로세스 안에서 public/private 순서를 바꾼 표본이며30개 독립 프로세스가 아니다. 이번 별도 baseline1/current candidate1 실행은 이전 측정과 독립인 반복 근거다. private control240/2의 max9.178166→10.586208ms(**+15.34%**)도 별도 보존한다. 이는 public candidate max9.588541ms와 다른 branch이며 원인을 규명한 제품 퇴행으로 단정하지 않는다. 입력2event 조건은 실제 bounded-day 유사 입력,180event 조건은 full-array 입력으로 각각 유지한다. 실제 Watch query I/O·snapshot 쓰기·WidgetKit render/reload·활성 Focus·배터리·frame은 이 clock 안에 없다. [W1 public/control·고정 label 독립 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-current-watch-repeat-3-review.md).

A1은 실제 async refresh 완료까지의 elapsed다. 범위2026-09-03…2026-10-02·depth1·synthetic memory·locale `ko_TR`·이미지 없음 조건이다. p50은 n30에서 **중앙 두 값 평균**, n5에서는 중앙값이며 W1의 상측값과 합치지 않는다. 각 역할 warmup1,1kTask/10kprogress는 n30,10kTask/100kprogress는 n5다.

| 조건 | 1kTask / 10kprogress p50 ms | 변화 | 10kTask / 100kprogress p50 ms | 변화 |
|---|---:|---:|---:|---:|
| 회고만 저장(review-only) | 555.329 → 110.916 | -80.03% | 5859.912 → 1281.542 | -78.13% |
| Task 변경 | 558.974 → 569.255 | +1.84% | 5860.275 → 5953.420 | +1.59% |
| unknown import 알림 proxy | 557.518 → 568.976 | +2.06% | 5860.384 → 5971.743 | +1.90% |
| 서비스 cache 유지 control | 109.134 → 116.288 | +6.56% | 1261.177 → 1326.344 | +5.17% |
| 변경 없는 재진입(no-read) | 0.009229 → 0.008584 | -7.00% | 0.025125 → 0.024834 | -1.16% |

회고 저장만 바뀌는 refresh의 비용 감소를 확인했고, Task 변경·unknown proxy는 기존 강한 재조회 정책을 유지하며 p50의 작은 증가도 남겼다. service control의+6.56%/+5.17%는 A1 session 이득으로 바꾸지 않는다. 변경 없는 재진입은 no-read 정책의 수십 마이크로초 값이다. n5 p95는 max이며 tail/규모별 퇴행 확정에는 한계가 있다. unknown 알림은 실제 CloudKit 왕복이 아닌 proxy,depth1 결과는 여러 페이지·이미지 decode나 전체 Archive 화면 준비 비용을 증명하지 않는다.

두 반복은 **per-operation DispatchTime elapsed**이며 operation CPU·에너지·입력100ms·UI frame 측정이 아니다. command process 자원에는 setup/query/검증/런타임도 포함되어 이를 operation 자원으로 대체하지 않는다. 최종 채택 Core A/B 전체 비교라 W1/A1 단독 변경의 인과 효과를 분리하지 않는다. 실행 전 proof의 Core166·PlanBaseCore1·Tests121이 batch11 compiled source와 같고 `Package.swift`도 동일하며, 양쪽 재사용 binary SHA를 확인한 provenance를 연결한다. 이전 isolation proof의 ownedDevices state는21:59 ownership catalog에서 복사한 과거 상태이며 현재 inventory가 아니다. 완료 proof의 실제 시점에는 owned6대 모두 Shutdown이다. 사용자 프로세스 부하0·전역 shutdown/erase/uninstall을 주장하지 않는다. Mac·Lock Screen·실제 standalone Watch/컴플리케이션 UI와100ms/frame/배터리 검증은 계속 미완료다. [실행 전 소스·binary·격리 proof](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-a1-w1-repeat-isolation-source-proof.json), [4종료 상태·완료 시점 owned inventory](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-a1-w1-repeat-completion-device-proof.json).


## 최종 독립 검토와 실제 화면 후속 — 23:14 잠정

현재 Goal은 **active**다. current-source A1 repeat2와 W1 repeat3의 양쪽 실제 검사 PASS·exit0, 원본 표본·전체 출력 digest 일치 및 최종 독립 리뷰를 확인했다. 위의 Core elapsed 표와 first UI pair는 완료 상태이며, 모든 요청 metric/100ms/frame·실제 widget 인수까지 완료됐다는 선언은 아니다. 아래 증거의 SHA를 직접 재확인했다.

| 최종 검토·native 원본 | SHA-256 |
|---|---|
| [A1 repeat2 독립 리뷰](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-current-archive-repeat-2-review.md) | `481786f6ef94ad00340b3c469768bd139b89abf019c918a126b556df24bfd8dd` |
| [W1 repeat3 독립 리뷰](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-current-watch-repeat-3-review.md) | `460e74e8dbeb29f94dc607a59c8978ce9340d8fe7dcff3c740c87e1feb3c22a6` |
| [9영역 registry v5](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-nine-area-decision-registry-v5.md) | `93257e61fd8989b42f232231836aa833e1911d43db7bbeeb286b02393db072c9` |
| [iPad 성공 native 화면 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-visual-review.md) | `714c6a95552e9ef8c5a3547081f2bea420b0e87825e6191078ffa83524229871` |
| [성공 native 첨부 manifest](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-success-attachments/manifest.json) | `30e465a02d8378e1b1d1a242fcbe2c97dd52b833ad416efddfce5e42fa35c118` |
| [전체 첨부 SHA·관찰 manifest](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-success-attachments/review-manifest.json) | `72dfdd08c8488e782ab1a75c6ad83069e64a3c723995fe19be9ce1525e92890e` |
| [Apple 공식 widget 실행 범위 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-lockscreen-widget-run-official-docs-review.md) | `ad6dbb6f762095388ef7fc8c7ff0dce2a45d934a19f2ed3ac1d773cff55dd2d0` |
| [Mac 실제 CUA ledger](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-mac-live-cua-observations-2308.md) | `8bfcd3800f7185198a6004a1be10dc358d66265cdbe4e411f85a9e4f02744c79` |
| [Watch 설치 후 prelaunch proof](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-installed-runtime-prelaunch-proof.json) | `34edb00e1cf096b0f9b5b8b3373dd6eba7f8bf02fbb63552a49432329eb76fa0` |

성공한 iPad4검사는26첨부(18PNG/8TXT), 실패 연결 첨부0개다. 직접 본11PNG와 native frame TXT는 두 앱 각각561.5pt/간격10.5pt, 메모 실제 floating375pt, 본문2→3줄 이어쓰기 및 캘린더4preview+2overflow/6개 상세를 확인한다. 나머지7PNG도 원본/SHA를 보존하되 직접 보았다고 하지 않는다. strict320…600pt·non-overlap·hittable·전체값·재열기 oracle은 유지됐다. 화면의 저장 중은 자동 저장 순간이며 controlled save failure/rollback/fixed dirtyMemo나100ms 검증이 아니다.

메뉴 소폭 증가를 다시 소스 대조했으나 실제 구간의 호출·elapsed/CPU·frame 연결 근거가 없어 추가 cache나 정확성 경계 완화를 채택하지 않았다. 대표 완성 query의 추가 비용 후보와 관측 증가를 보존한다. [독립 소스 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu-regression-source-closure-review.md).

### iPhone 메모 native 화면의 추가 반례 — default·AX5 인수, 후속 회귀 진행

앞선 iPhone6기능 PASS의 native 원본10PNG를 보존하고6장을 직접 검토했다. 실패 초안의 탭 복귀 화면 한 장에서 키보드 **완료**의 glass가 **다시 시도** 일부를 덮는 장면을 발견했다. 이 한 frame은 지속 겹침이나 터치 실패를 입증하지 않는다. 기존 검사는 첫 단계 Done→keyboard hidden과 전체 초안·저장·재열기를 확인했지만, 복귀 후 Retry를 최대2회 허용하므로 첫 터치의 효과는 별도 확인이 필요하다. 두 번째 저장 실패가 아직 남아 있을 수 있어 첫 터치 후 실패 상태만으로 miss를 단정하지 않는다.

동일 formal XCTest의 격리 test-only probe를 빌드·실행해 **1검사/실패0/87.759초·exit0**를 확보했다. 0.508646초의 공개 XCTest sampled equality 관찰 뒤 Done `(329.333,504,51.667,36)`와 Retry `(306.333,480,79.667,44)`의 교차 높이20pt/면적1033.333pt² 및 native PNG의 partial label 가림을 다시 확인했다. 원래 screenshot 뒤3.5초가 지난 새 화면에서도 가림이 남았다. 이는 관찰 지점의 안정 재현이며 모든 rendering frame·입력 latency 증거는 아니다. **첫 기존 Retry 터치는 저장에 성공했고 exact 본문·키보드/Done을 유지했다.** 따라서 visual overlap을 수정 대상으로 삼으며 실제 touch failure나 Done-only closing을 주장하지 않는다. 제품247개는 main·frozen과 그대로이고 원래 최대2회 retry·본문/재열기/삭제 oracle을 보존했다.

첫 runner 준비는 native absolute Products 경로와 기존 `__TESTROOT__` 차이를 안전하게 거부했다. 상대 script 호출의 대소문자 경로 guard도 쓰기 전에 거부됐으며 정확한 절대 경로의 v2 호출로 준비했다. 환경5개 경로만 같은 Products를 가리키도록 정규화하고 **prelaunch `--ui-testing`**를 복원한 뒤에만 검사를 실행했다. per-method4인자와 기존 checker/injection은 유지했다. 전용 owned7DEFC iPhone만 사용하고 CUA host 잠금 우회·일반 GUI driver·erase/uninstall은 없었다. 기존 원본과 실패/수리 chronology를 보존한다. [probe 실제 결과](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-phone-done-retry-overlap-probe-functional-status.json), [추가 before PNG](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-phone-done-retry-overlap-probe-native-attachments/09D65B54-94C3-435E-BD74-0506BE6C3877.png), [독립 검토 SHA52ac1a…](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-phone-done-retry-overlap-probe-independent-review.md), [7첨부 전체 SHA](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-phone-done-retry-overlap-probe-independent-attachment-sha.json).

이 반례는9영역 registry v5 이후 발견됐다. 첫 topBarTrailing 글자형 Retry 후보는 default1/0 PASS/89.898초·exit0였고 겹침 없이 첫 저장에 성공했다. 그러나 native before PNG에서 상단 메모 제목이 완전히 사라져 **읽기 인수에서 기각**했다. 가장 큰 글자 실행·main 채택은 하지 않았다. source의 min44 label과 별개로 native AX Retry frame은77.333×36pt였으므로44pt 실제 hit bounds를 입증했다고 하지 않는다. 현재는 기존 Back 옆 topBarLeading의 아이콘 Retry·명시적 접근성 이름으로 균형을 맞추는 새 후보를 준비한다. footer 안내·동일 failed/flush/ID·Done focus·자동 저장을 유지하고 default/AX5·좁은 iPad의 제목/버튼 노출·본문/재열기를 검증한 뒤 채택 여부를 결정한다. [기각 후보 actual before PNG](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-phone-memo-toolbar-retry-candidate-default-native-attachments/935BEBCC-F2D3-4016-BD18-220F29165B57.png), [기각 후보 기능 결과](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-phone-memo-toolbar-retry-candidate-default-functional-status.json). [원본 native 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-iphone-memo-keyboard-native-visual-review.md), [원본 겹침 PNG](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-iphone-memo-keyboard-functional-native-attachments/4D0EB73A-C9CB-4F02-9261-24AF2D1C8A9D.png), [좁은 후보 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/iphone-memo-toolbar-remedy-source-review.md).

새 leading 아이콘 후보는 build-for-testing exit0 뒤 **default1/0 PASS·89.421초, AX5 1/0 PASS·87.694초 및 각 명령 exit0**를 확보했다. root가 양쪽의 원본 before/after PNG를 직접 읽었다. 실패 상태의 중앙 제목은 길이에 따라 생략되지만 실제 표시되고, Retry 아이콘과 footer 오류 문구 및 키보드 Done은 겹치지 않았다. 첫 Retry 뒤 동일 전체 본문 값·키보드/Done을 유지하며 저장됨으로 전환하고 Retry는 사라졌다. AX5의 오류 안내는3줄로 읽을 수 있고, before 본문은 편집 끝까지 스크롤되어 일부가 화면 밖에 있으므로 전체 본문을 동시에 표시했다고 하지 않는다. 전체 본문 보존은 기존 value oracle로 확인했다. native AX Retry는 default37×36pt·AX5 42.333×36pt여서 source min44를 실제44pt target 증거로 바꾸지 않는다. [default native root 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-phone-memo-leading-retry-candidate-default-root-native-review.json), [AX5 native root 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-phone-memo-leading-retry-candidate-ax5-root-native-review.json), [독립 source 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-iphone-memo-leading-retry-candidate-independent-source-review.md).

후보의 나머지 phone6/0 PASS·192.883초와 iPad5/0 PASS·306.042초 및 두 명령 exit0를 확보했다. iPad의 회전 전 실패 초안 화면은 제목 전체·본문·오류 footer·Back 옆 Retry와 Done의 분리를 보여 주고, 회전 후 동일 본문·저장됨을 확인했다. 실제 좁은 창의 제목은 말줄임 표시되고 이어쓴 본문을 읽을 수 있다. root 인수 뒤 생산1파일과 기존 cooperative 테스트의 최소15비공백 줄(AX3·geometry8·title4)을 main에 채택했으며 probe의124진단 줄은 제외했다. main build 입력409개·Swift roster373개 SHA guard exit0, 별도 build-for-testing190.015초 exit0 및 actual main default1/0 PASS85.126초·AX5 1/0 PASS81.971초/각 exit0를 확보했다. main의 최소 테스트에는 after-first-tap probe 첨부가 없으므로, 같은 product411fc… 후보에서 확인한 첫 tap/저장 뒤 native 화면을 별도 증거로 유지하고 main에서 새로 first tap을 검증했다고 하지 않는다. [실제 채택](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-main-memo-leading-retry-actual-adoption.json), [phone6 native 독립 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-phone-memo-leading-retry-candidate-post-native-review.md), [iPad5 실제 결과](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-memo-leading-retry-candidate-post-functional-status.json). 일반 플랫폼 script는 UI test target을 컴파일하지 않으므로 후속 main 최소 테스트의 별도 build-for-testing·formal 선택 실행과 전체 플랫폼 게이트를 구분한다. [새 v2 후속 계획](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-memo-toolbar-post-candidate-validation-plan-v2.json), [미적용 최소 패치 증거](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-main-memo-leading-retry-adoption-proof.json).

필기 목록 팔레트와 Calendar window-controls 가림은 동일 생산247개·최소 UITest에93줄만 추가한 결합 freeze로 재확인했다. Release+DEBUG/testability 한 번의 build-for-testing193.746초 exit0 뒤 owned phone27 drawing1/0 PASS56.265초, owned iPad26.5 narrowCalendar1/0 PASS59.521초와 각 exit0를 확보했다. 원래 필기 저장·재열기·clear·유형 및 Calendar 제목 높이·6개 일정 상세·overflow·원창 복구 oracle을 보존했다. [결합 계획](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ui-palette-calendar-header-probe-plan.json), [root 소스 guard](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ui-palette-calendar-header-probe-root-prebuild-proof.json).

Phone에서는 canvas가 없는 메모 목록의 접힌 필기 팔레트가 칸반 tab 위에 남은 native 원본을 root가 확인했다.0.530700초(IPC 포함)의 AX geometry 샘플이 동일했고 원래 thumbnail와 후속 PNG도 같은 paint를 보인다. 이 범위의 잔류는 재현됐으나 연속 paint·영구 잔류·실제 메뉴 touch failure·latency로 확대하지 않는다. Kanban AX isHittable=true도 시각 겹침을 부정하는 근거가 아니다. canvas teardown의 picker 숨김·observer 해제 및 늦은 queued 표시를 막는 최소 후보를 준비하며 drawing callback·저장·clear는 유지한다. [root 원본 판정](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-phone-palette-combined-probe-root-native-review.json).

Calendar에서는 기존 original4PASS와 같은561.5×744pt tiled 창의 시스템 glass가 이전 달 arrow/연도 앞부분을 가리는 시각 문제가 반복됐다. 공개 이전 달1tap은2026년9월에 도달했고 다음 달1tap은2026년10월을 복구했으므로 month touch failure는 입증되지 않았다. 기존 moveMonth 의미상 선택day는 월1일로 바뀌므로 초기 선택day 복구까지 주장하지 않는다. Retry 변경 전후 Calendar 관련4파일은 동일하다. 창 제어기 영역을 제공하는 iOS26+ 공개 geometry API와 iOS18 fallback을 활용하는 좁은 후보를 준비한다. 이 baseline 뒤 두 제품 후보를 별도로 검증했으며 아래 기록이 현재 채택 상태를 갱신한다. baseline 실패/관찰 원본은 보존한다. [Calendar source 감사](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/ipad-calendar-header-source-audit.md), [root 원본 판정](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-calendar-header-combined-probe-root-native-review.json).

두 최소 후보의 build-for-testing은 exit0다. 같은 freeze에서 phone 필기1/0 PASS56.781초, iPad Calendar1/0 PASS60.579초, phone Calendar/템플릿3/0 PASS180.707초, iPad 필기1/0 PASS51.726초 및4명령 모두exit0를 확보했다. 각 시간은 기능 시나리오 전체 시간이며 입력 latency나 새 성능값이 아니다. root가 phone·iPad의 목록 복귀 native에서 팔레트 제거·칸반 표시·필기 thumbnail 보존을 확인했고, 공개 팔레트 부재 predicate와 칸반1tap→빠른 입력→메모 복귀·기존 재열기/clear/유형 oracle도 통과했다. iPad 필기 창의 실제 frame은 `(0,171,561.5,652.5)`이며 Calendar tiled561.5×744와 같은 창 조건으로 합치지 않는다. [phone 원본 인수](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-phone-palette-remedy-candidate-root-native-review.json), [phone 독립 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-phone-palette-remedy-candidate-independent-native-review.md).

iPad Calendar 후보의 이전 달/제목 x는 baseline2/48→68/114로66pt 이동했고 시스템 controls AXframe은 그대로였다. root와 독립 검토에서 native 화살표·전체 연도/월 제목이 glass에 가리지 않음을 확인했다. 이전/다음 달 각1tap과 원 wrapping/6개 일정 상세/overflow가 통과했고 after-fill PNG는 읽을 수 있는 Calendar panel과6개 상세를 보여 준다. 실제 복원 oracle는 width>800이며 정확한 after-fill AXframe/raw inset0·연속 paint까지 주장하지 않는다. phone의 normal/xxxLarge/AX5 회전·마지막 날짜 scroll/상세, 템플릿 날짜 선택·추가·이번만 조정과 최대 글자 요약도 통과했다. AX5 template Calendar header의 적용 전 native 첨부는 없어 실제 날짜/추가 동작 PASS와 구분한다. [iPad 원본 인수](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-calendar-remedy-candidate-root-native-review.json), [iPad 및 선택 phone 독립 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-calendar-remedy-candidate-independent-native-review.md).

root는 검토된 product2개와 새 테스트25줄만 main에 채택했다. palette40줄·Calendar53줄 진단과 after-fill PNG 한 줄은 candidate에만 남긴다. Swift6/SDK26.5 컴파일은 후보에서 통과했으며 iOS18–25 fallback/RTL는 source 검토이고 실제 해당 OS/방향 runtime 통과가 아니다. raw geometry 측정·100ms 반응·새 UI shipping Release 성능·실제 OS VoiceOver/IME는 미검증으로 유지한다. [정확한 최소 패치 증거](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ui-palette-calendar-remedy-minimal-main-adoption.proof.json), [Calendar 소스 독립 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-calendar-corner-insets-independent-source-review.md).

### Mac 실제 조작 — root CUA 관찰 ledger

다음은 [root의 실제 CUA 관찰 ledger](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-mac-live-cua-observations-2308.md)를 읽어 연결한 범위다. normal safe 앱 실행파일 SHA `6015c494…a0937`와 저장 실패·AX 진단 variant loader SHA `3576c3ca…73af8`를 구분한다. 이 값은 PID가 아니다. [독립 provenance 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-mac-ui-accessibility-save-failure-provenance-review.md)에서 Core166·desktop29·re-export1 및26파일57치환·486manifest 불일치0, 격리 등록/entitlement와 실제 코드 debug dylib `e084f3be…1dcde`의 file-backed section 일치를 확인했다. 원장은 수동 관찰 근거이며 원시 PNG 재검토·별도 XCTest PASS·직접 frame/elapsed 측정이 아니다. 일반 배포 binary·전체 접근성/성능 인수로 표시하지 않는다.

- normal Mac 캘린더는6주·긴 제목·`+4`를 실제 표시했다. 좌표 클릭 뒤 추가 window를 얻지 못했으므로 날짜 상세 진입 성공은 미입증이다. 메모는 `café` 포함3줄 본문의 저장·재열기·전체값과 결과 없음 검색을 관찰했다.
- D1 회고 편집에서 제목·본문이 먼저 보였고 요약 접힘→펼침을 확인했다. screenshot raster는 회고1200×1468/root1800×1424이며 logical600×734/900×712는 Retina2x 전제를 둔 추정이다. 직접 window frame·최소/최대 폭·resize 인수는 아니다. Command-S 뒤 editor에 머무르며4번째 줄을 이어 쓰고 다시 저장→닫기→재열기했을 때4줄 전체값과 사진3개가 남았으며2번째 실제 그림과3번째 AX image/count·이전/다음 표시도 관찰했다. 이는 모든 크기/원본 bytes/operation memory를 검증한 결과는 아니다.
- 저장한 작업 `GOAL 운동 café 👩‍💻`의 alias 운동을 사용해 Unicode NFD `/운동` 후보를 Down으로 선택하고 Return으로 적용한 뒤 작업의 `0/2` 표시를 확인했다. OS IME 조합·spoken VoiceOver·입력 지연과 구분한다.
- Focus 시작→일시정지 및 checklist1/2→재개→종료18초→5분 휴식→건너뛰기를 관찰했다. Task 자동 완료는 일어나지 않았다. Focus를 닫은 뒤 getApp timeout이 있어 root 복귀 성공은 입증하지 못했다.
- 저장 실패 variant의 최초 exploratory paste 시도는 빈 초안만 보여 입력 검증 실패였다. 비어 있지 않은 초안 보존 PASS나 내용 손실 bug로 분류하지 않는다. 실패 횟수를 소비한 뒤 별도 신규 세션의 본 검사에서 `GOAL Mac 실패 복귀 2306`의3줄 실패 초안→Calendar→Memo 복귀가 같은 전체값을 유지했고 retry 뒤 새 저장 목록 행을 확인했다. 복귀 때 도구 AX 오류는 getApp 재접속으로 회복했다. 도구 오류를 제품 저장 실패나 복귀 성공의 별도 증거로 대체하지 않는다.
- 이후 Calendar 클릭 때 CUA가 Mac 잠금 및 자동 잠금 해제 실패를 **명시적으로 반환**했다. 앞선 timeout을 잠금으로 추론한 것이 아니다. GUI 작업을 중단했고 기존 수동 잠금 해제 요청은 대기다. Goal blocked/complete로 전환하지 않는다.

### Watch 준비와 잠금 화면 경계

owned Watch06FE96DC…의 boot/bootstatus/install 및 native `get_app_container groups` 조회는4명령 모두exit0다. [설치 후 prelaunch proof](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-installed-runtime-prelaunch-proof.json)에서 설치된 app/extension의 실행파일 SHA가 signed source와 모두 같음을 확인했다. 원본 container log는 안전 진단 group `group.com.soraul2.planbase.goal.run154826ab8b66.watchruntime`를 owned06FE의 Shared/AppGroup/AAE81CBB… 경로로 해석한다. **앱 등록·컨테이너 해석만 확인**했으며 extension runtime access·snapshot 공유·Watch launch/GUI·complication render는 미확인이다. Mac 잠금 이후 Watch launch는 없었다. 이를 생산 App Group 또는 사용자 저장소 접근 증거로 확장하지 않는다.

Apple의 extension Product > Run은 일반 Home/Today/Mac 호스트를 지원하지만 `_XCWidgetFamily`는 accessory 제외 크기만 열거하며 잠금 화면/Watch accessory는 앱 실행 뒤 수동 추가로 안내한다. `_XCWidgetKind`는 종류 선택, `_XCWidgetDefaultView`는 Mac simulator 표시 모드다. Preview는 실제 timelineProvider도 받을 수 있지만 Xcode canvas이고 현재 PlanBase Preview 입력은 합성 fixture다. 환경 변수만으로 세 accessory family를 직접 띄우는 공식 경로가 입증되지 않았으므로 기존 수동 추가 요청과 실제 render/privacy/deep link/자정 확인을 남긴다. [Apple Debugging widgets](https://developer.apple.com/documentation/widgetkit/debugging-widgets), [Apple Previewing widgets](https://developer.apple.com/documentation/widgetkit/previewing-widgets-and-live-activities-in-xcode).
