# PlanBase 성능과 사용 흐름 최적화 계획

작성일: 2026-10-02. 기준 소스: `b7e524a0038df84a6b5b84864cb1774b9199cabf`, TestFlight 1.0(86).
상태: **사용자 요청으로 검증 작업 재개(2026-10-03 09:42 KST)**. Goal 도구는 이전02:39 판정의 blocked를 반환하며 active나 완료로 변경됐다고 표시하지 않는다. 9영역 조사·채택·반례·메뉴/초기 로딩10조건 전후 비교와 현재 main 최소 UI2개·전체 플랫폼 게이트 exit0 검증을 확보했다. 재개 후 소유 iPhone 기동으로 Simulator 화면 접근을 복구하고 오늘 일정3개 합성 JSON을 전용 group에 적용·읽기 대조했다. Mac sample은 관찰 구간의 연산 정체를 보이지 않았으며 Watch 설치본의 fresh 읽기 대조도 마쳤다. 이후 화면 도구가 현재 Mac 잠금을 명시적으로 반환해 직접 해제를 요청했다. 실제 Lock Screen·Watch·일부 Mac 및 VoiceOver/IME 인수는 남았고, 누락 지표/100ms 직접 계측은 미검증이다. [재개 후 확인](OPTIMIZATION_2026_10_02_RESULTS.md#재개-후-확인--2026-10-03-1004-kst)과 [이전 차단 판정](OPTIMIZATION_2026_10_02_RESULTS.md#이전-차단-판정--2026-10-03-0239-kst)을 구분한다. 아래 active 표현은 해당 시점의 실행 기록이다.

목표는 작업 입력과 탭 이동의 반응을 확인하고, 실제 비용이 큰 처리와 불필요한 조작을 줄이는 것이다.

**2026-10-03 사용자 후속 지시**: 실제 화면 검증을 뒤로 미루고 현재 변경분의 TestFlight 업로드를 먼저 진행한다. 남은 화면 항목을 통과로 바꾸지 않으며 후속 확인 대상으로 유지한다. 버전1.0·빌드87의 Release 배포와 필요한 설정 검증은 이 명시적 지시에 따른 별도 실행이다.

**2026-10-03 최신 사용자 지시**: 외출 중인 사용자의 요청으로 업로드를 보류하고 현재 변경분을 `git add`, commit, push한다. 이는 초기 Git 변경 제외 조건의 명시적 예외다. Xcode 계정·설정은 사용자가 직접 준비하며 남은 화면 인수와 업로드를 완료로 표시하지 않는다.

먼저 최신 버전의 기준값을 수집하고, 측정에서 확인한 성능 후보와 화면 비교에서 확인한 흐름 후보를
작은 단위로 적용한다. 한 번에 효과와 검증 범위가 분명한 후보 2~3개를 처리하고,
전후 비교 후 남은 후보와 다음 병목을 재평가해 다음 묶음을 이어간다. 전체 작업량의 상한은 아니다.
Goal 실행 범위와 지속 작업 조건은 [실행 프롬프트](OPTIMIZATION_2026_10_02_GOAL_PROMPT.md)를 따른다.

실행 중 사용자가 오늘 캘린더 일정의 잠금 화면 표시를 확인하고 가능하면 진행하라고 요청했다.
이 명시적 후속 요청으로 별도 캘린더 잠금 화면 위젯 추가를 범위에 포함한다.
처음의 새 기능 확장 제외 조건에 대한 한정된 예외이며, 다른 기능 확장이나 배포를 허용하지 않는다.

## 최신 실행 상태와 남은 필수 검증 — 2026-10-03 01:59 KST

전체9영역을 조사하고 batch11까지 반복 구현·반례·비교를 진행했다. 현재 main은 BT1/BT4-A, C1/C2/C3, A1/D1, M1/cooperative 메모·M2split512, B1, S1/S2lite/S4와 **S2batch의 callback 없는 default 범위**, W1을 채택했다. initial full S2와 M2-256은 거부했다. 과거 첫 묶음 기록과 실패 원본은 보존하며, 현재 수치·퇴행·범위는 [진행 결과](OPTIMIZATION_2026_10_02_RESULTS.md)와 [9영역 registry v5](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-nine-area-decision-registry-v5.md)를 따른다. 전체 Goal 완료 선언은 아니다.

사용자의 추가 요청인 **메뉴 변경·초기 로딩 버벅임 확인, 문제면 최적화**를 명시적 후속 범위로 포함한다. 코드의 동기 처리 경로, 서비스 비용 감소, 화면 첫 반응·내용 준비 완료를 각각 검증한다. 실제 UI 결과 없이 모든 메뉴 지연의 원인을 특정하거나 체감 개선을 선언하지 않는다. 오늘 일정 Lock Screen 위젯 추가는 아래의 별도 후속 범위로 유지한다.

현재 확보한 검증:

- [x] 시작 HEAD·430파일 기준 사본·환경·합성 fixture·원본 표본·SHA manifest를 보존했다.
- [x] batch11 optimized 기본 병렬729개/26.259초 통과. locale fixture만 autosave=false로 보정했고 제품 저장 정책은 유지했다.
- [x] 최종 main 일반 Debug725개/29.584초·Release694개/26.250초와 `verify-platform-builds.sh` exit0. iOS/macOS 각 Debug·Release 및 내장 Watch/위젯·Privacy 검증을 포함한다. [게이트 상태](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-platform-regression-status.json).
- [x] **독립 Watch scheme Debug·Release 두 빌드 exit0**. 실제 Watch 앱/컴플리케이션 조작·장시간 수명 통과로 간주하지 않는다. [Debug](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-debug-build-status.json), [Release](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-release-build-status.json).
- [x] 최종 iOS hosted34개/실패0. widget12·backup7·Live Activity 상태12·Notification fake3이며 OS render/실제 전달은 별도다. [hosted 상태](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-hosted-mobile-tests-status.json).
- [x] 최신 메모 키보드 닫기 제품 소스의 iOS build-for-testing 성공. 뒤이은 window 좌표 helper 보정본도 컴파일 통과했으며 제품247개와 responsiveness class는 그대로다. [생산 소스 대조](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu-production-247-source-check.json), [최신 빌드](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ui-window-coordinate-build-status.json).
- [x] **키보드 닫기 수정 뒤 iPhone 메모6검사 모두 통과/exit0**. 검색 query 변경·취소, 실패한 초안, 탭 복귀·재시도, 백그라운드 복귀, 저장 재실패, 필기 유형 및 조회 실패 재시도를 포함한다. cooperative query/초안 검사78.049초는 기능 시나리오 전체 시간이며 성능 수치가 아니다. 최초12검사11통과/1실패·결과 수집 stall/−15와 test-only 보정 두 실패는 원본에 남긴다. [메모 결과](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-iphone-memo-keyboard-functional-status.json).

남은 필수 검증:

- [x] **iPhone 메모 버튼 겹침·도구 수명과 iPad 캘린더 헤더 수정·로컬 인수**: 동일 formal probe1/0 PASS/exit0·87.759초에서0.508646초 sampled equality 뒤 Done/Retry 교차 높이20pt와 native label 가림을 재현했다. 첫 기존 Retry는 exact 본문/키보드를 유지하며 저장에 성공했으므로 touch failure는 입증되지 않았다. 원래 최대2회 retry·본문/재열기/cleanup을 유지했다. 첫 topBarTrailing 글자형 후보는 default PASS에도 native 제목이 사라져 기각했고 AX5/main 채택은 하지 않았다. 새 leading 아이콘 후보는 default1/0 PASS·89.421초, AX5 1/0 PASS·87.694초와 native 제목 표시·footer 가독성·버튼 비겹침/초안 저장을 인수했다. 나머지 phone6/0 PASS·192.883초와 iPad5/0 PASS·306.042초 뒤 생산1파일·최소15비공백 테스트 줄을 main에 채택했다. main 입력409개·Swift373개 SHA guard exit0, 별도 main UITest build-for-testing190.015초 exit0, main default1/0 PASS85.126초·AX5 1/0 PASS81.971초/exit0를 확보했다. 당시 후속 전체 플랫폼 게이트는 미실행이었고 최신768.191초 gate로 마쳤다. 생산247개 동일·원래 oracle 보존 결합 probe phone1/0 PASS56.265초·iPad1/0 PASS59.521초/각exit0에서 필기 목록 팔레트 잔류와 기존561.5pt Calendar 제목 가림을 재현했다. Calendar prev/next 각각1tap은 성공해 touch failure로 주장하지 않는다. 후속 두 최소 후보는 phone필기1/0 PASS56.781초·iPadCalendar1/0 PASS60.579초·phone관련3/0 PASS180.707초·iPad필기1/0 PASS51.726초/4명령exit0와 native 비가림/내용 보존 인수 후 product2개·추가 최소25줄 테스트를 main에 채택했다. main989532…/b9decc…/b42540…이며 새409입력·373Swift guard exit0, 별도main UITest build187.827초 exit0와 phoneDrawing1/0 PASS58.181초·iPadCalendar1/0 PASS50.926초/각exit0 및 actual native 목록·헤더·내용 인수를 확보했다. gate 전후409/373 guard exit0, 최신 일반 전체 gate768.191초 exit0 및 Debug689통과/36skip·Release684통과/10skip·iOS/macOS4build/내장 번들/Privacy 검증까지 완료했다. [최신 로컬 인수](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-main-ui-palette-calendar-remedy-local-validation-acceptance.json). 기존 성능 pair는 후속 새 UI binary의 측정으로 바꾸지 않는다. [재현 독립 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-phone-done-retry-overlap-probe-independent-review.md), [후보 source 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/iphone-memo-toolbar-remedy-source-review.md).
- [x] **키보드 UI 수정 뒤 전체 플랫폼 게이트 exit0**: Debug725개/27.380초·Release694개/24.138초 및 iOS/macOS Debug·Release, 내장 Watch/위젯·Privacy 검증을 통과했다. 이 당시 native iPad 배치/정리 변경은 UI test-only였고 생산247개와 metric class는 같았다. 이후 Retry·팔레트·Calendar 수정은 위 최신 gate/소스 연결로 구분한다. [최종 게이트](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-platform-after-keyboard-status.json).
- [x] **iPad native 창 배치4검사 모두 통과/exit0**: Settings 옆 보드·Focus 유지85.700초, 캘린더·기록94.272초, 메모 초안·편집·다시 열기58.640초, 실제 좁은 캘린더44.631초다. 내용·hittable·두 앱 비겹침과320~600pt 창 조건을 유지했다. 기능 시나리오 시간이며 메뉴 성능값이 아니다. 중복 Dock 단계를 제거하고 명시적 키보드 닫기를 사용한 test-only 수리 후 빌드 exit0, 첫 설치 MIG 대기에서는 검사0개/−15로 종료했다. 해당 owned iPad만 erase 없이 재시작한 후4/0 PASS를 확보했다. 이전 iOS27 runner 종료·iOS26.5 좌표/assert 실패·Sendable 컴파일 실패와 설치 대기는 원본 및 진행 결과에 보존한다. VoiceOver/AX opt-in2개 건너뜀은 실제 접근성 통과가 아니다. [최종 iPad 결과](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-reboot-functional-status.json), [성공 native 화면11PNG 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-visual-review.md), [원본26첨부 manifest](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-success-attachments/manifest.json), [전체 SHA·관찰 범위](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-ipad265-native-preset-success-attachments/review-manifest.json). 직접 본 화면은 각각561.5pt 두 창과375pt floating Memo·이어쓰기/overflow를 보이며 controlled save failure·fixed dirtyMemo/100ms 증거로 확대하지 않는다.
- [x] **메뉴·초기 로딩 실제10조건 전후 실행·원시 비교 확보**: 같은 dedicated iPhone/iOS26.5의 양쪽10/0 PASS/exit0, original9clock+2launch native 배열은 각n5/10·finite를 확인했다. product15/history3개 전체 columns/count/full-row SHA가 동일하나 Xcode 설치 후 container UUID/path는 달라 같은 물리 경로라고 표현하지 않는다. 초기 내용 중앙값7.273→6.873초(−5.51%)·추천2.854→2.488초(−12.85%)를 관측했고, 반복4탭6.482→6.722초(+3.70%)·scroll5.345→5.500초(+2.90%)도 남긴다. **전체 요청 지표 bundle는 양쪽invalid**(TabArchive1·hitch6 누락)이며 최초3메뉴 CPU/메모리18행은 PID/interval peak 연결 미입증으로 개선 근거에서 제외한다. 한 pair·n5/10 p95=max와 XCTest IPC/wait를 실제100ms 입력 반응·배터리·단일 패치 인과로 확장하지 않는다. [실제 비교](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-metric-pair-comparison.json), [데이터 비교 v2](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-menu265-fixture-pair-comparison-v2.json).
- [ ] **최종 Mac 실제 조작의 남은 인수**: 최신 safe normal 앱에서6주·긴 캘린더 제목/+4, `café` 포함3줄 메모 저장·재열기/전체값·결과 없음 검색, D1 제목/본문 우선·요약 펼침·연속 저장/4줄 재열기·사진3개 전환, NFD `/운동` Down/Return 적용 및 Focus 정지/재개/종료18초/휴식을 관찰했다. 저장 실패 variant는3줄 failed draft의 Calendar→Memo 복귀 동일값·retry 새 저장 행을 확인했다. 날짜 상세 좌표 진입·Focus 닫기 후 root 복귀는 미확인이고 spoken VoiceOver/OS IME 조합·직접 timing·모든 크기/회전·system preferences도 미검증이다. 이후 CUA가 명시적 Mac 잠금/자동 해제 실패를 반환해 GUI를 중단했고 기존 수동 잠금 해제 요청을 기다린다. [variant 독립 provenance 검토](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-mac-ui-accessibility-save-failure-provenance-review.md)는 소스·26파일57치환·486manifest·격리 설정 및 실제 debug dylib section 연결까지 불일치0으로 완료됐다. 수동 원장은 원시 PNG 재검토나 XCTest 결과와 구분한다. root/회고 screenshot1800×1424/1200×1468에서 논리 폭900/600은2x 전제를 둔 추정이며 직접 frame·resize 인수가 아니다. [실제 root CUA ledger](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-mac-live-cua-observations-2308.md), [후속 상태](OPTIMIZATION_2026_10_02_RESULTS.md#mac-실제-조작--root-cua-관찰-ledger).
- [x] **current-source A1/W1 Core 독립 반복과 최종 독립 검토 완료**:4command 모두 실제 검사PASS/exit0. A1 raw20행/10pairs의 ordered sample·aggregate digest 동일, review-only1k/10kProgress555.329→110.916ms(−80.03%)·10k/100k5859.912→1281.542ms(−78.13%). task/unknown +1.59~2.06%·service control +5.17~6.56%도 보존한다. W1 public4조건 n30 full digest 동일이며20Task/2Event0.835584→0.361958ms·240/2 14.665958→9.499125ms다. 이 값은 DispatchTime elapsed이고 operation CPU·Watch frame/배터리가 아니다. W1 상측 중앙값과 A1 중앙 두 값 평균·n5 p95=max를 구분한다. [A1 최종 독립 리뷰 SHA481786…](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-current-archive-repeat-2-review.md), [W1 최종 독립 리뷰 SHA460e74…](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-current-watch-repeat-3-review.md).
- [ ] **실제 Lock Screen 위젯과 Watch 앱/컴플리케이션**: owned signed Simulator/App Group·합성 snapshot 준비 및 hosted 검사는 확보했다. owned Watch06FE의 boot·bootstatus·install·안전 group container 조회4명령은exit0이며 앱 등록/경로 해석을 확인했다. extension runtime access·snapshot 공유·launch/GUI·complication/장시간 Focus는 미검증이고 Mac 잠금 뒤 Watch launch는 없었다. 실제 잠금 화면 추가/render·긴 제목/기간·privacy·tap/deep link·자정·iPad family는 기존 수동 진입 요청을 유지한다. Apple 공식 accessory 경로는 앱 실행 뒤 수동 추가이며 일반 extension Run/`_XCWidgetFamily`·합성 Preview로 세 family 실제 인수를 대체하지 않는다. [native group 해석](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-owned-runtime-containers.log), [설치 app/extension SHA·prelaunch proof](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-watch-installed-runtime-prelaunch-proof.json), [공식 문서 범위](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-lockscreen-widget-run-official-docs-review.md), [Apple Debugging widgets](https://developer.apple.com/documentation/widgetkit/debugging-widgets).
- [ ] **100ms 첫 시각 반응·작업별 peak memory**: 직접 대응되는 frame/자원 증거를 확보하거나 미검증으로 명시한다. n5 tail·pooled cooperative slice·XCTest IPC/wait·whole-process RSS를 frame latency나 operation memory로 대체하지 않는다. 실기기 배터리·실제 알림·운영 CloudKit·장시간 수명은 별도 외부 인수로 구분한다.

아래의 시작 환경, 초기 후보·수용 기준과 첫 묶음 경과는 작성·실행 당시 기록이다. 오래된 “미측정/진행 중” 문구는 현재 채택 상태를 되돌리지 않으며 최신 표와 후속 원본 증거가 상태를 갱신한다.

## 계획 작성 당시 범위 — 시작 기록

| 기준 기록 | 이미 적용된 내용 | 이번 계획에서의 처리 |
|---|---|---|
| [9월 22일 최적화 결과](OPTIMIZATION_2026_09_22_RESULTS.md) | 루틴·회고 반복 계산, 백업 부모 조회, 불필요한 보드 관찰, 위젯 지연 테마 수정 | 같은 최적화를 다시 구현하지 않고 관련 기능을 회귀 확인한다 |
| [9월 28일 탭과 Focus 결과](TAB_RESPONSIVENESS_AND_FOCUS_2026_09_28_RESULTS.md) | 비활성 탭 갱신 연기, 범위 조회 재사용, 통계의 별도 실행 영역, Focus 갱신 범위 축소 | 당시 실기기 성능 계측이 없었으므로 입력·탭 반응과 상태 보존을 우선 측정한다 |
| [9월 29일 일정 추천 결과](CALENDAR_RECOMMENDATION_USABILITY_REVIEW_2026_09_29.md#9-승인된-개선안-구현-결과-2026-09-29) | 최근 200개 조회·5개 표시, 오래된 결과 차단, 메모 보호·되돌리기, 키보드·접근성 조작 | 정확성을 유지하면서 반복 조회와 보조 UI의 공간 사용을 평가한다 |
| [build 86 배포 기록](../../releases/TESTFLIGHT_BUILD_86.md) | `/` 발견 안내·접근성 힌트, Debug 511개·Release 507개 테스트와 플랫폼 게이트 통과 | 빌드·테스트 통과를 체감 성능 측정으로 간주하지 않는다 |

계획 작성 당시에는 코드와 기존 기록만 확인했다. 아래의 지연 원인과 개선 효과는 계측 전 가설이며,
이전 버전의 개선율을 build 86의 성과나 목표 달성값으로 사용하지 않는다.

## 실행 진행 기록

실행 ID: `run-154826-ab8b66`. 증거 경로는 `.local/optimization-20261002/run-154826-ab8b66/`다.
시작 HEAD와 사용자 문서 변경을 보존했고, 제품·문서 430개 파일의 고정 사본과 SHA-256 manifest를 만들었다.
macOS 27.0, Xcode 26.6, Swift 6.3.3, arm64, 메모리 32GiB 조건이다.
상속된 CommandLineTools `SDKROOT`만 실행 환경에서 제외하고 Xcode developer directory를 명시한다.
기준 사본의 전용 scratch에서 공통 Debug 511개 검사가 통과했다. 이는 성능 수치가 아니다.

| 영역 | 조사·후속 증거 | 현재 채택·유지 결정 | 남은 검증 |
|---|---|---|---|
| 1 시작·복귀·탭·무결성 | `startup-focus-widget-audit.md`, `menu-startup-source-audit.md`, S2/S4 adoption | S1 positive guard·pending/fresh reader·S2lite·S4·S2batch default 채택. 무결성·save/rollback·최신 import·비활성 revision 유지. 직접 record/explicit callback은 dynamic. | 최초 내용·first/warm 메뉴10조건 first pair 완료; requested bundle invalid/fresh18 resource 제외·독립 UI 반복/100ms 미검증. 동기 서비스와 화면 준비 완료를 분리 |
| 2 보드·상태·이월·진행 | `board-template-audit.md`, progress/flow 비교 | 공통 reader 정확성 채택. 완료/undo·이월·checklist 독립 유지. BT2/3 장기 projection cache·접기·메뉴 통합 미채택. | visible row/tick·정렬/formatter 실제 호출과 입력/스크롤·keyboard 회귀 |
| 3 저장 작업·입력어·루틴 | 같은 audit, `quick-entry-repeat-decision.md` | BT1 동일 query 후보 공유·BT4-A alias 정규화 재사용 채택. 일반 입력의 library 미준비·IME·rank·latest 실행·독립 Task 복사 유지. 추가 cache/2→3단계 메뉴 미채택. | iPhone/iPad 기능 및 safe Mac NFD `/운동`·Down/Return 적용 관찰. OS IME 조합·큰 글자/100ms는 미검증. batch 개선과 첫 slash 준비 +5.48%를 구분 |
| 4 캘린더·추천·템플릿 | `calendar-audit.md`, C1/C2 설계·실제 paired 로그 | C1 최신 active 논리 대표→기간/visibility 및 범위 밖 최신본, C2 **iOS 월 cell counts** projection 채택. 추천200/5·200ms·메모/undo·linked Task 유지. 장기 layout/session cache·보조 UI 제거 미채택. | canonical35/42일×30/200/1000의6pair 값 일치와 iPad actual narrow/overflow 확보. Mac6주/긴 제목/+4 관찰, 상세 좌표 진입과 남은 날짜/접근성 인수는 미확인 |
| 5 활동·회고·사진 | memo/archive audit, A1/S4 실제 service 비교 | A1 review-only index 유효성·D1 Mac 제목/본문 우선과 접힌 요약·S4 단일 inspection 채택. pending stamp/generation/coverage·unknown 무효화·MIME/decode/SHA·원본 유지. | 최종 A1 review-only −80.03/−78.13%, task/unknown +1.59~2.06%·service control +5.17~6.56% 분리. safe Mac D1 4줄 저장/재열기·사진3개 관찰과 operation memory/모든 크기 검증 구분 |
| 6 메모·필기 | `memo-design.md`, pending/external/yield 반례,512 adoption | M1 adaptive100→512·cooperative paging·pending 부모/자식·clean fresh hydration·drawing metadata·M2split512 채택. **256 거부**. 전체 body/checklist·깊이·600ms autosave/flush·draft/유형/PencilKit 원본 유지. | iPhone6기능·iPad4창 인수 완료; safe Mac 저장 실패 초안 복귀/retry 잠정 관찰. 큰 글자/VO/OS IME 미검증. whole3.26초/slice max120.418ms·Session ready +2~7% 한계 유지 |
| 7 Focus·알림·Live Activity·Intent | startup audit, hosted state·이전 safe Mac CUA | 원자 lifecycle·timer/token/revision/deadline·failure retry/stale Intent 유지. 새 microcache 미채택. 최종 hosted state12/fake3 통과. | safe Mac 시작/paused/check1/2/resume/end18초·휴식/skip 관찰, root 복귀 미입증. Watch 실제 UI·background/OS 전달·기본 trigger·배터리/장시간 수명 별도 |
| 8 위젯·Watch | snapshot representative repro·W1 actual·Lock Screen 구현 | C3 대표→visibility·W1 하루 summary·별도 오늘 일정 Lock Screen 구현. Calendar8일·format5·kind/AppGroup·count cap·150ms merge·sequence/write skip 유지. 독립 Watch 두 build 통과. | W1 current-source 독립 반복·최종 리뷰 완료. owned Watch 설치/앱 safe group 해석4exit0; extension 실행/공유·실제 추가/render/privacy/자정/tap·standalone Watch 조작은 미검증 |
| 9 백업·병합·호환성 | memo/backup audit, B1 current export 반복 | B1 invocation-local grouping/index·reader 보완·S4 채택. **두 reconcile**·count/error/save·비파괴 merge·latest/superseded·rollback·V1~V11/식별자/UTI 유지. | n5 대량 약83% 감소와 small100 p95 +2.70% 분리. 최종 로컬 UI·실패·운영 데이터/CloudKit 외부 인수 구분 |

### 초기 실행 경과 — 당시 기록

비교용 새 test-only harness는 기준 사본에도 같은 파일로 추가하고 별도 SHA를 기록한다.
고정한 기존 제품 파일은 수정하지 않는다. 제품 개선은 변경 전 계측 후 결정한다.
측정용 Release에는 DEBUG hook과 testability를 함께 사용한다. 최초 testability 누락 및
새 harness의 compile 오류 로그는 보존했고 옵션/검사 코드를 보완 중이다.
iOS 최적화 측정 앱의 `build-for-testing`은 통과했으며 Goal 전용 시뮬레이터 두 대를 만들었다.
아직 측정 효과와 UI 통과를 주장하지 않는다.

후속 상태: [진행 결과](OPTIMIZATION_2026_10_02_RESULTS.md)에 원본 표본·실패 로그와
후보별 판정을 기록한다. 빠른 입력 결과 재사용(BT1), 메모 희소 검색 batch(M1),
백업 invocation-local child grouping(B1)을 첫 묶음으로 채택했다.
캘린더 물리 중복의 날짜별 표시 반례는 기준 검사 실패를 확인해 정확성 수정으로 우선 처리한다.
코드 작성 완료와 검증 완료는 구분하며, 아직 최종 성능 효과·플랫폼 통과를 선언하지 않는다.

## 실행 순서

| 단계 | 작업 | 다음 단계로 넘어가는 조건 |
|---|---|---|
| 1 | 소스·환경·합성 데이터 고정, 입력·탭·주요 화면의 기준 계측 | 원본 표본과 화면 상태를 다시 재현할 수 있다 |
| 2 | 병목과 흐름 후보의 우선순위 확정 | 호출 횟수·처리 시간 또는 조작 단계로 문제를 설명할 수 있다 |
| 3 | 후보 2~3개의 구현·비교·관련 검증을 묶음별로 반복 | 각 변경을 확인한 뒤 남은 후보와 다음 병목을 재평가한다 |
| 4 | 같은 조건 재측정, 관련 회귀·화면 검증 | 효과가 확인되고 초안·최신 데이터·실패 처리가 유지된다 |
| 5 | 전체 조사 결론과 로컬 채택 후보 완료 후 최종 플랫폼 검증·결과 기록 | 채택·유지·보류 이유, 전후 결과, 남은 실기기 확인을 문서에 남긴다 |

우선순위는 **일반 입력·탭 복귀 → 메모 편집·검색 → 자주 쓰는 입력 흐름 → 캘린더·추천 계산 → 시작·위젯 처리**다.
데이터 누락이나 저장 실패를 재현하면 성능 순위보다 먼저 해결한다. 측정에서 비용이 작게 나오면 해당 구조는 유지한다.

Goal에서는 아래 후보 외에도 이월함·활동 기록·회고·루틴·알림·deep link·백업의 관련 경로를 조사한다.
각 영역에 확인 범위와 개선 또는 유지 이유를 남기고 이미 적용된 최적화는 현재 코드와 대조한다.
첫 묶음 완료 후에도 채택한 로컬 후보와 근거 있는 추가 후보가 남아 있으면 다음 묶음을 진행한다.

## 기준 계측과 채택 기준

기존 [공통 성능 fixture](../../../shared/Tests/ResponsivenessPerformanceTests.swift),
[화면 성능 시나리오](../../../mobile/Tests/PlanBaseLaunchUITests.swift),
[Instruments 구간 기록](../../../shared/Core/Services/PlanBasePerformanceTrace.swift)을 활용한다.
필요한 계측만 보완하고 테스트 전체를 새로 만들지 않는다.

| 시나리오 | 기록할 값 | 함께 확인할 동작 |
|---|---|---|
| 일반 제목·한글 조합·연속 입력 | 입력 반영 시간, 메인 실행 영역의 긴 처리, 화면 끊김 | 글자·커서·조합 보존, 추천 비활성 입력의 불필요한 조회 여부 |
| 네 탭 왕복과 첫 진입 | 선택 반응과 데이터 표시 시간을 분리, fetch·집계 횟수, CPU·메모리 | 초안·검색·선택 날짜·스크롤·기록 페이지 깊이 보존 |
| `/` 검색과 방향키 선택 | 라이브러리 조회·필터·정렬 시간과 호출 수 | 후보 순위, 선택, 적용 날짜, 실행 직전 최신 데이터 확인 |
| 메모 편집·검색·필기 | 자동 저장당 페이지 조회 수, 검색 배치 수, 렌더·직렬화 시간, 최대 메모리 | 이탈 저장, 오류 후 초안, 최신 대표 연결, 필기 원본 보존 |
| 달력 날짜·월 선택과 일정 추천 | 배치 계산 횟수, 추천 fetch 수, 처리 시간, 화면 끊김 | 기간·색상·중복·overflow·메모 보호·되돌리기 |
| 앱 시작·복귀와 변경 알림 | 수렴·조회·snapshot 생성·쓰기·reload의 개별 시간과 호출 수 | 최신 테마·날짜·작업·일정 반영, 오래된 쓰기 차단 |

데이터는 빈 상태·일상 사용·대량 상태를 구분한 로컬 또는 메모리 fixture를 사용한다.
기존 전체 작업 3,000개(오늘 240개, 완료·보관 2,760개)와 저장 작업 1,000개 fixture를 재사용하고,
메모 200/2,000/10,000개와 일정 30/200/1,000개는 추가 합성 조건으로 설계한다.
사진·긴 Unicode 본문·체크리스트만 일치하는 검색·물리 중복·결과 없음도 포함한다.

측정 방법과 초기 채택 기준은 다음과 같다. 수치는 이번 계획의 제안 기준이며 달성 결과가 아니다.

- 같은 기기·OS·빌드 옵션·데이터·시나리오에서 전후를 비교한다. 함수·반복 입력은 준비 실행 후
  30회 이상 표본을 모으고 중앙값·95백분위·최댓값·원본 표본을 보존한다.
  시작·긴 시나리오는 5~10회로 측정하고 적은 표본의 95백분위를 안정적인 지표로 주장하지 않는다.
- 입력과 탭 선택의 첫 시각적 반응은 100ms 이내를 초기 목표로 삼는다.
  의도한 추천 debounce, 실제 조회·렌더 완료, XCTest 통신·대기 시간을 각각 구분한다.
  자동화 전체 실행 시간을 한 글자 입력 지연으로 해석하지 않는다.
  입력 시점과 실제 표시 시점을 대응하는 측정 방법을 확보하지 못하면 100ms 목표는 미검증으로 남긴다.
- 성능 변경은 같은 조건의 독립 실행에서도 효과가 재현돼야 한다. 주 지표 중앙값 15% 이상 개선을
  우선 채택 기준으로 삼되, 이미 작은 비용에는 복잡한 캐시를 추가하지 않는다.
  꼬리 지연이나 최대 메모리가 10% 이상 나빠지면 원인과 비용을 검토하고 채택 여부를 다시 결정한다.
- 흐름 변경은 조작 수·스크롤·입력 영역의 가시성·완료 인지로 평가한다.
  CPU 감소와 사용 단계 감소는 별도 결과로 기록한다.
- 성능 계측 중 다른 빌드·벤치마크·UI 검사를 병행하지 않는다.
  계측 hook을 넣은 Release 최적화 빌드와 일반 배포 Release를 구분한다.

## 우선 후보와 완료 조건

### 일반 입력과 탭 복귀

현재 iOS는 비활성 화면의 변경 revision을 기록하고 활성화 시 조회한다.
범위 조회와 통계 분리도 이미 적용돼 있다. 보드에는 상태별 목록·개수·스크롤 대상 계산과
상태별 필터·정렬이 남아 있으나 일반 제목 입력 지연의 단일 원인은 아직 확인되지 않았다.
관련 파일은 [MobileAppRootView](../../../mobile/App/MobileAppRootView.swift),
[VisibleDataRefresh](../../../shared/Core/Components/VisibleDataRefresh.swift),
[MobileBoardView](../../../mobile/App/Features/Board/MobileBoardView.swift),
[ActivityOverviewSession](../../../shared/Core/Services/ActivityOverviewSession.swift)이다.

- 일반 입력, `/` 입력, 변경 없는 탭 복귀, 저장·합성 import 후 복귀를 나눠 측정한다.
- 오늘 작업 20/240개에서 입력당 body·상태별 정렬 횟수를 확인한다.
  비용이 크면 입력 상태를 작은 화면으로 분리하거나 상태별 결과를 한 번 계산해 재사용한다.
  반복 조회·집계도 병목으로 확인된 경로만 줄이고 화면 계층은 유지한다.
- 완료 조건은 입력·초안·날짜·검색·스크롤·페이지 깊이 보존과 유효한 변경의 최신 반영이다.
  변경 없는 탭 복귀의 불필요한 재조회가 줄어드는지 함께 확인한다.

### 메모 자동 저장과 대량 검색

[MemoQuerySession](../../../shared/Core/Services/MemoQuerySession.swift)은 갱신 시 이미 읽은 페이지를 다시 조회한다.
[MemoService](../../../shared/Core/Services/MemoService.swift)의 검색은 100개 단위로 읽어
40개 일치를 찾거나 끝까지 진행한다. 여러 페이지를 연 편집과 희소 검색의 실제 비용은 미측정이다.

- 1/5/10페이지를 연 상태에서 글·체크리스트·필기 저장당 조회 수를 측정한다.
  비용이 크면 목록 갱신 요청 병합이나 변경 범위에 따른 결과 재사용을 검토한다.
- 대량 메모의 마지막 1건·무결과·체크리스트만 일치하는 검색을 측정한다.
  병목이 있으면 취소 가능한 배치 처리 또는 별도 컨텍스트의 값 기반 검색을 검토한다.
- 600ms 자동 저장과 화면 이탈·백그라운드 flush, 최신 대표 선택, 고정·최근 수정 정렬,
  전체 본문 검색을 유지한다. 검색 상한으로 오래된 메모를 누락시키지 않는다.
  저장 실패 때 초안과 기존 목록이 남아야 한다.

### 필기 처리와 메모 생성 진입

메모 필기 미리보기는 행의 상태에 이미지를 보관하고 revision 변경 시 렌더링한다.
모바일 canvas에는 변경 알림과 화면 갱신 양쪽의 직렬화 경로가 있다.
반복 비용은 아직 측정하지 않았다. 회고 사진의 비동기 축소·공유 캐시는 이미 구현돼 있다.
관련 화면은 [MobileMemoView](../../../mobile/App/Features/Memo/MobileMemoView.swift)와
[MemoView](../../../desktop/App/Features/Memo/MemoView.swift)다.

- 작은·중간·큰 합성 필기로 입력·회전·탭 복귀·재스크롤의 렌더와 직렬화 횟수를 측정한다.
  반복 비용이 확인되면 revision 기반 미리보기 재사용·동일 요청 병합·변경 추적을 검토한다.
- 현재 유형 선택 방식과 글 메모 직접 진입 후 다른 유형을 선택하는 방식을 비교한다.
  이 항목은 제품 선택 실험이며 스케치 사용률이 낮다는 가정을 근거로 삼지 않는다.
- 세 유형의 발견성, 기존 복합 메모·필기 원본, 유형 잠금, 지우기와 실패 시 보존을 유지한다.
  메모리 압박에서 미리보기 자원을 해제할 수 있어야 한다. 스케치 삭제나 스키마 변경은 범위에 포함하지 않는다.

### 보드와 일정 입력 및 Mac 회고 작성

보드에는 저장한 작업과 템플릿 진입점이 함께 있으며 하나짜리 템플릿은 같은 재사용 레코드다.
일정 편집기에는 날짜 선택·자주 쓰는 기간 버튼·직접 일수 입력이 함께 있다.
Mac 회고는 작업 요약이 입력보다 먼저 펼쳐지고 저장 후에도 창이 남는 흐름이 있다.
이 항목들은 화면 비교로 판단할 사용 흐름 후보다.

- 저장한 작업·템플릿의 현행 진입과 하나의 불러오기 진입 시안을 비교한다.
  단일 작업과 작업 묶음의 구별·검색·적용을 유지하고 주요 행동의 단계가 늘거나 더 혼동되면 현행을 유지한다.
  긴 카드의 체크리스트 요약도 오늘 작업 탐색과 체크 동작을 함께 비교한다.
- 일정은 날짜·자주 쓰는 기간을 기본으로 두고 직접 일수를 접는 안을 비교한다.
  1일·3일 일정의 조작 수는 늘리지 않고 임의 기간은 기본 날짜 입력으로도 설정할 수 있게 한다.
- 자동 일정 추천의 빈 결과를 한 줄로 줄이는 안을 비교한다.
  실패·재시도·메모 교체·되돌리기는 유지하고, 패널 변화로 커서·스크롤·접근성 초점이 이동하지 않게 한다.
- Mac 회고는 제목·본문 우선, 작업 요약 기본 접힘, 저장 성공 시 완료가 분명한 동작을 검토한다.
  실패하면 창과 초안을 유지하며 미저장 확인·사진·과거 날짜 수정은 보존한다.

대상은 [보드 입력 컨트롤](../../../mobile/App/Features/Board/MobileBoardHeaderControls.swift),
[모바일 일정 편집기](../../../mobile/App/Features/Calendar/MobileEventEditorSheet.swift),
[Mac 일정 편집기](../../../desktop/App/Features/Calendar/DesktopEventEditorSheets.swift),
[추천 공통 화면](../../../shared/Core/Components/CalendarEventRecommendationContent.swift),
[Mac 회고](../../../desktop/App/Features/Archive/DiaryView.swift)다.
작은 iPhone·좁은 iPad 창·Mac, 키보드 표시·최대 글자 크기·VoiceOver 조건에서 비교한다.

### 캘린더 배치와 추천 계산

양 플랫폼의 월 달력 body 경로에는 일정 배치 계산이 있다.
일정 추천은 입력 debounce 이후 최근 일정 범위를 다시 읽고,
저장 작업의 `suggestions`는 호출마다 필터·정렬한다. 반복 비용이 실제 병목인지는 미측정이다.

- 날짜 선택만 바뀔 때와 월·일정·창 크기·글자 크기가 바뀔 때의 달력 계산을 분리한다.
  병목이면 월·데이터 revision·geometry에 연결한 값 projection 재사용을 검토한다.
- 일정 추천은 같은 편집 세션의 입력·삭제별 fetch 수를 측정한다.
  필요할 때만 세션 한정 snapshot을 사용하고 저장·삭제·성공 import·재시도 때 최신화한다.
- 저장 작업 100/1,000개에서 입력 변경과 방향키 선택을 따로 측정한다.
  강조 후보만 바뀔 때 검색이 반복되면 입력과 라이브러리 revision에 연결한 결과 재사용을 검토한다.
- 배치·overflow·5/6주·기간·논리 중복·Unicode·후보 순위·즐겨찾기·접근성 결과가 기존과 같아야 한다.
  최신 선택 확인, 오래된 비동기 결과 차단, 실행 직전 재조회는 유지한다.

대상은 [MobileCalendarView](../../../mobile/App/Features/Calendar/MobileCalendarView.swift),
[CalendarView](../../../desktop/App/Features/Calendar/CalendarView.swift),
[CalendarEventRecommendationSession](../../../shared/Core/Services/CalendarEventRecommendationSession.swift),
[SavedTaskQuickEntryController](../../../shared/Core/Services/SavedTaskQuickEntryController.swift)다.

### 보이지 않는 화면과 Focus 조회

보드의 숨겨진 상태 목록과 각 탭의 Focus 진입 화면에는 주기 갱신 경로가 있다.
SwiftUI가 비가시 갱신을 억제할 수 있으므로 코드만으로 추가 비용을 단정하지 않는다.
Focus 화면은 작업 영역 변경 때 후보와 오늘 집계를 다시 준비하며 단순 체크 변경의 실제 비용은 미측정이다.

- Focus 없음·진행·일시정지에서 칸반과 메모 탭의 실제 tick·snapshot 읽기·진행 계산 수를 관찰한다.
  중복 비용이 확인되면 가시 화면의 표시 갱신과 event revision별 정적 계산을 분리한다.
- 체크리스트 10회 변경·다른 작업 편집·선택 작업 완료·Focus 종료의 fetch와 수렴 횟수를 나눠 측정한다.
  필요하면 선택 작업 갱신·작업 선택 목록·오늘 집계의 무효화 조건을 구분한다.
- 화면 계층과 스크롤, 복귀 직후 시간 표시, 휴식·종료·일시정지·백그라운드 복귀를 보존한다.
  진행 누적 시간과 실제 Focus 시간의 의미를 합치지 않는다.

대상은 [MobileBoardTaskList](../../../mobile/App/Features/Board/MobileBoardTaskList.swift),
[FocusModeView](../../../shared/Core/Components/FocusModeView.swift),
[FocusTaskQueryService](../../../shared/Core/Services/FocusTaskQueryService.swift),
[TaskProgressEventQuerySession](../../../shared/Core/Services/TaskProgressEventQuerySession.swift)이다.

### 시작과 위젯 발행

시작과 성공 import 뒤에는 무결성 수렴이 실행된다. 캘린더 위젯은 150ms 요청 병합과
순차 쓰기 보호를 사용하며 루트에도 강제 갱신 경로가 있다. 동일 변경의 실제 처리 횟수는 미측정이다.

- 시작·복귀·로컬 저장·합성 import·테마·날짜 변경별 수렴과 snapshot 생성·쓰기·reload 횟수를 기록한다.
- 중복 요청 비용이 확인되면 발행 요청의 병합 경계를 정리한다.
  최신 요청 우선, 지연 후 최신 테마 읽기, 실패 때 이전 정상 snapshot 보존을 유지한다.
- 화면 갱신 연기와 위젯 갱신을 구분하고 비활성 앱의 유효한 저장·import 발행을 보존한다.
  전체 수렴을 생략하거나 CloudKit 동기화 간격을 임의로 바꾸지 않는다.

대상은 양 플랫폼 AppRootView와
[CalendarWidgetSnapshotPublisher](../../../shared/WidgetSupport/CalendarWidgetSnapshotPublisher.swift)다.
Watch의 [snapshot 발행](../../../watch/App/WatchWidgetSnapshotPublisher.swift)은 별도로 측정하며,
발행 코드를 바꾸면 Watch 앱과 컴플리케이션도 검증한다.

### 추가 요구: 오늘 캘린더 일정 잠금 화면 위젯

기존 “PlanBase 오늘” inline은 일정 제목을 이미 표시하지만 circular은 빠른 추가,
rectangular은 Task 표시다. 이 기존 동작은 유지하고 “PlanBase 오늘 일정”을 별도 등록한다.
현재 일정 편집 규칙이 날짜를 자정으로 정규화하고 snapshot이 day key만 담으므로 시각은
추가하지 않는다. 같은 날은 종일, 여러 날은 시작·종료 날짜를 표시한다.

- inline: 첫 일정의 제목·종일/기간·나머지 수. rectangular: 최대 두 제목과 기간,
  전체 count와 나머지 수. circular: 캘린더 아이콘과 전체 일정 수.
- 모든 family는 `calendarTodayURL`을 사용해 탭 시점의 오늘로 이동한다.
  숨김 상태에서는 제목·기간을 생성하지 않는 공통 presentation을 사용하고 접근성도 같은 값을 읽는다.
- 새 timeline은 calendar coverage로 최대 8일의 자정 entry를 만든다. task summary/previews가
  없는 calendar-only snapshot도 유효하다. 날짜가 coverage를 벗어나면 갱신 필요로 표시한다.
  누락·손상·미지원 schema·잘못된 날짜/음수 count/중복 preview도 0개로 오인하지 않는다.
- snapshot의 최신 대표 선별, 시작·종료 날짜 포함, preview cap과 독립된 전체 count를 재사용한다.
  공개 snapshot 형식·기존 widget kind·App Group을 바꾸지 않고 새 kind reload만 발행에 추가한다.
- `GoalCalendarLockScreenWidgetTests`로 count·기간·대표·cap·privacy·coverage·자정·호환성을 확인한다.
  기존 Widget 파일에 구현해 target membership 추가가 필요 없으며, PreviewProvider에 세 family와
  privacy/empty 샘플을 제공한다. 실제 Widget extension의 Simulator 렌더링과 기존 위젯 회귀는
  실행 담당 root가 검증한다. 작성 완료를 검사·화면 통과로 간주하지 않는다.

사용자는 잠금 화면 길게 누르기 → 사용자화 → 위젯 추가에서 직접 선택해야 한다.
[Apple의 추가 방법](https://support.apple.com/en-au/118610)을 따른다.
위젯은 앱이 마지막으로 발행한 snapshot을 읽고, 앱의 저장·import·날짜 변경 발행 후 새 kind reload를
요청한다. timeline은 날짜를 바꾸지만 새 데이터의 실시간 수신을 보장하지 않는다.
갱신 정책은 [WidgetKit 공식 안내](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)를 따른다.
구현·미실행 항목·SHA는 실행 증거 `results/calendar-lockscreen-implementation.md`에 기록한다.

- [x] **2026-10-03 02:21 KST 사용자 안내 작성**: [위젯 추가·표시·갱신 안내](../../CALENDAR_LOCK_SCREEN_WIDGET_GUIDE.md)를 제공하고 문서 목록에 연결했다. 기능 포함 버전 설치를 전제로 하며 TestFlight86 배포 완료로 표현하지 않는다. 최신 제품 소스의 세 모양·기간·개인정보 숨김·읽기 실패/확정0개 분기와 Apple의 추가·갱신 설명을 확인했다. 실제 Lock Screen 세 모양과 Watch/Mac 화면의 미완료 상태는 유지한다.

## 기능 보존과 검증

변경한 영역의 관련 테스트부터 실행한다. 후보 비교를 마친 최종 코드에는
`./scripts/verify-platform-builds.sh`를 실행하고, Watch 소스를 바꿨으면 독립 scheme도 확인한다.
계획 문서 작성 자체에는 빌드·테스트를 다시 실행하지 않았다.

| 변경 영역 | 우선 활용할 검증 |
|---|---|
| 탭·조회·기록 | `PersistenceChangeTests`, `ActivityOverviewSessionTests`, `ArchiveQuerySessionTests`, 기존 탭·초안 보존 UI 시나리오 |
| 빠른 입력·일정 | `SavedTaskShortcutTests`, `CalendarEventRecommendationTests`, `CalendarEventGridLayoutTests`, 입력·선택·실패·큰 글자 UI 시나리오 |
| 메모·필기·회고 | `MemoTests`, 기존 생성·자동 저장·필기·탭 복귀·회고 저장 UI 시나리오 |
| 위젯·Focus | `CalendarWidgetSnapshotTests`, `PlanBaseWidgetSnapshotIntegrationTests`, `WatchWidgetSnapshotTests`, `FocusModeTests`, Live Activity 상태·타이머 검사 |

Task 상태와 진행·완료 활동의 같은 저장 명령, 실패 rollback, 논리·물리 ID와 중복 수렴,
`DayKey`, 첨부 원본 검증을 유지한다. SwiftData 모델 객체를 실행 영역 사이에 넘기지 않는다.
동결 스키마 V1~V11·배포 식별자·백업 package V10은 이번 계획의 변경 대상이 아니다.

일반 검사는 실제 사용자 저장소와 CloudKit을 열지 않는 합성 fixture로 수행한다.
전용 앱·preferences·snapshot을 사용하며 실제 사용자 데이터·`.local/backups/`를 측정 재료로 쓰지 않는다.
금지된 iCloud Drive 경로에는 접근하지 않는다. 실제 CloudKit 왕복은
[별도 운영 절차](../../CLOUDKIT_SYNC.md)에 따른 인수 항목이다.

Focus와 Live Activity는 백그라운드 경과 시간·일시정지·재개·종료, 체크리스트 실패와 상태 독립성을 확인한다.
시뮬레이터 확인과 실기기 확인을 구분하며 기존 미확인 이슈는 업로드나 빌드 통과만으로 완료 처리하지 않는다.

## 완료 조건과 결과물

- [x] 최신 기준 소스·환경·fixture와 원본 표본을 보존했다.
- [x] 각 후보에 측정 또는 화면 비교 결과와 채택·보류 이유가 있다.
- [ ] 전체 조사 영역에 결론이 있고 채택한 로컬 후보의 미완료 구현·검증이 없다.
- [x] 남은 후보와 변경 후 비용을 재평가하고 추가 변경의 가치·위험에 따른 유지 이유를 기록했다.
- [ ] 채택한 변경은 같은 조건의 전후 효과와 저장·조회·초안 보존 근거가 있다.
- [ ] 관련 회귀, iPhone·iPad·Mac 화면, 최종 플랫폼 검증이 통과했다.
- [x] CPU·화면 반응·자동화 시간·사용 단계·메모리를 구분해 기록했다.
- [x] 실기기·CloudKit·위젯·타이머의 남은 확인과 확인한 범위를 구분했다.

최종 공통/플랫폼·hosted·독립 Watch 빌드와 iPhone 메모6개·iPad 창4개 기능 통과, 실제10조건 UI 전후 원시 비교를 확보했다. 전체 요청 지표 일부와 실제 Mac/위젯/Watch 수동 확인은 미완료다. 따라서 관련 회귀와 전체 화면 인수를 결합한 완료 조건, 채택본의 미완료 검증이 없다는 조건은 계속 열린 상태다.

실행 증거는 새 `.local/optimization-20261002/<run>/`에 보관하고 기존 측정·배포 자료는 덮어쓰지 않는다.
실행 후 `OPTIMIZATION_2026_10_02_RESULTS.md`에 전후 수치와 최종 소스, 변경별 결론을 기록한다.
이 계획의 완료는 해당 결과와 검증을 확보했을 때 판단한다.

### 메뉴·초기 로딩 추가 확인 (실행 중)

사용자가 메뉴 변경·초기 로딩의 버벅임도 확인하고 문제가 있으면 최적화하라고 요청했다. 새 프로세스의 칸반 내용, 각 메뉴 최초 진입, 예열 후 내용 준비까지 **UI 성능 시나리오5개를 보강**했다. 기존5개를 포함한 실제10조건 전후 pair는 양쪽10검사 통과 및 동일 데이터 내용·원시 비교를 확보했다. 수집된11clock/launch 행과 수집하지 못한 signpost/hitch, 최초3메뉴 CPU/메모리 연결 한계를 구분한다. [UI 측정 설계](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/menu-startup-ui-measurement-design.md)와 [플랫폼별 source audit](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/menu-startup-source-audit.md)를 근거로 입력 첫 반응·선택·content-ready·CPU·XCTest 대기/IPC를 분리한다.

source audit에서 양 root의 `start()`·메뉴 archive·활성 화면 refresh와 snapshot query/make의 동기 MainActor 구간을 확인했다. 위젯 JSON writer는 별도 actor이고 account status·활동 overview도 기존 실행 영역 분리가 있다. 같은 trigger의 중복 요청 가능성과 실제 중복 fetch/화면 점유는 다르므로 코드만으로 원인을 확정하지 않는다. 기존150ms 요청 병합·sequence·동일 쓰기 생략을 재구현하거나 무결성 검사를 제거하는 방식은 사용하지 않는다.

초기 사진 double-inspection 가설은 공개 full reconcile의0/20/100 distinct PNG 전후 비교와3개 강한 회귀를 거쳐 **S4를 채택**했고, 초기 legacy2760 pending-array 비용은 **S2lite→S2batch default 경로**의 두 독립 비교로 개선했다. 이 완료된 서비스 변경을 다시 미계측 후보로 취급하지 않는다. S4의100PNG 약47% 감소·S2batch의누락2760 약0.50~0.52초와 실제 최초 화면의 기여율은 다르다. zero-image 작은 비용·S2lite 작은 조건 퇴행·whole-process RSS·M2slice/session 추가 비용도 [진행 결과](OPTIMIZATION_2026_10_02_RESULTS.md)에 함께 남긴다.

최종 채택본의 동일 내용 fixture·날짜/시간대 기대·큰 글자/회고 접힘·cold/warm 조건을 분리한 실제10조건 전후 pair와 현재 Core의 A1/W1 독립 반복은 완료했다. iPhone 메모6개·iPad 창4개의 후속 성공, 이전 실패/수집 stall, 소스·실행파일 정체성도 별도로 보존했다. 초기 콘텐츠 clock은 약5.51%, 추천 입력 CPU는 약19.01% 감소했지만 warm4탭 clock은 약3.70% 증가했고 첫 메뉴 변화는 작았다. 한 pair의 IPC/대기 포함 clock을 모든 메뉴의 체감 개선으로 확대하지 않는다.

남은 작업은 수동 잠금 해제 뒤 최신 Mac의 Focus 접근성 category/창 크기/보드 복귀, owned Watch 실제 Today·Focus·snapshot/컴플리케이션, owned iPhone Lock Screen3family의 추가/render/privacy/deep link/자정 확인이다. Mac의 일반 회고 연속 저장·메모 검색/재열기·실패 초안 탭 복귀/retry 일부는 실제 CUA로 확인했다. 이후 도구가 Mac 잠금을 명시적으로 보고해 GUI를 중단했다. 실제 spoken VoiceOver·OS IME 조합,100ms/frame과 누락 signpost/hitch는 미검증으로 구분한다. [최신9영역 재평가 v6](/Users/home/ai_project/planbase/.local/optimization-20261002/run-154826-ab8b66/results/final-nine-area-decision-registry-v6.md)는 현재 추가 구현을 권고하지 않으며, 새로운 실제 결함이나 병목이 확인되면 최신 데이터·초안·페이지/선택/스크롤을 보존하는 좁은 수정과 영향 검증을 재개한다. 이미 통과한 전체 gate나 같은 UI pair를 근거 없이 다시 실행하지 않는다.
