# PlanBase 전체 최적화 — 실행 계획

상태: 로컬 필수 범위 완료. 기준 HEAD `e93d7914aa9e06dd230b4efa21b9ab0ebb866ad9`.
시작 시 사용자 변경은 실행 프롬프트 문서 하나(미추적)이며 앱 코드는 clean 상태다.
실행 명세: [Goal 프롬프트](OPTIMIZATION_2026_09_22_GOAL_PROMPT.md).

증거 루트: `.local/optimization-20260922/run-183419-5b7f4a/`.
`baseline/source/`의 396개 파일과 `manifest.json`, 시작 diff/HEAD/환경을 보존했다.
환경: Apple Silicon, macOS 27.0 (26A428), Xcode 26.6 (17F113), Swift 6.3.3.
과거 macOS 26.6.2 측정과 직접 비교하지 않고 이번 실행에서 새 기준을 측정한다.

## 조사와 소유권

| 영역 | 담당 | 현재 상태 | 확인할 근거 |
|---|---|---|---|
| 시작·복귀·탭·무결성·import | 주 에이전트 | 유지 결정·관련 검증 완료 | 시작 no-op 수렴/rollback/import 검사, 전체 수렴 의미 유지 |
| 보드·상태·완료 취소·체크리스트 | 주 에이전트 + template_ui | 구현·관련 검증 완료 | 미사용 관찰4개 제거, passive 안내 터치 수정, phone/pad Undo 통과 |
| 루틴·저장 작업·빠른 입력 | template_ui | 구현·관련 검증 완료 | 12조건 전후 비교, import gate, 편집/검색/적용 UI |
| 이월함·활동 기록·회고 | core_audit | 구현·관련 검증 완료 | 회고9조건, 페이지/취소/import 검사; 이월 대표 재조회 유지 |
| 캘린더·적용·재사용 | core_audit | 유지 결정·관련 검증 완료 | 35/42일 범위, 배치 계산, DST·독립 복제 검사 |
| 메모·첨부 | core_audit | 유지 결정·관련 검증 완료 | 읽기/저장 실패 초안 보존, 최신 대표·긴 내용·첨부 무결성 |
| Focus·알림·Live Activity·Intent | widget_focus | 유지 결정·로컬 검증 완료 | Focus 원자성·로컬 상태 유지, iOS 알림3/Activity4 통과; 실기기 외부 인수 |
| 위젯·Watch | widget_focus | 구현·관련 검증 완료 | 지연 테마 재현/수정5개 통합검사, iPhone 실제화면2개; Watch 구조 유지 |
| 백업·호환성 | core_audit + 주 에이전트 | 구현·관련 검증 완료 | 단계 부모 인덱스,4조건비교,rollback/replay,보호35파일·6설정 동일 |

모든 영역의 조사와 채택 변경의 관련 검증, 최종 전체 플랫폼 게이트를 마쳤다.
실제 CloudKit·실기기 인수와 잔여 표시·성능 한계는 결과 문서에 별도로 남겼다.
각 조사 보고서는 증거 루트 `results/*-audit.md`, 최신 종합 결과는
[결과 문서](OPTIMIZATION_2026_09_22_RESULTS.md)에 연결한다.

우선 채택한 것은 잘못된 테마와 터치 차단의 재현 결함, 대량 백업 부모 조회,
회고 블록·루틴 행 반복 계산, 불필요한 import 외 갱신이다. 데이터 원자성·대표 선택을
바꾸는 전역 캐시나 전체 수렴 생략은 채택하지 않았다. 루틴 무결과 약1ms 추가 비용은
수정 후 남은 한계로 기록했다. 별도 기능 확장·스키마 변경·UI 전면 재설계는 하지 않았다.

## 실행 순서

1. 시작 소스와 환경 보존, 현행 Debug 공통 테스트 확인.
2. 모든 영역의 조사 결론과 후보 우선순위 작성, 의미 보존 기준 확정.
3. 변경 전 회귀/성능 fixture와 필요 시 UI 기준 실행. baseline을 고정 보존.
4. 근거가 확보된 후보를 작은 단위로 구현하고 동등성·실패·취소 회귀 검증.
5. 같은 조건 성능 재측정, 효과 없는 변경 재검토.
6. 관련 iOS 전용 검사와 iPhone/iPad/macOS 화면 검증.
7. 최종 전체 플랫폼 게이트, 필요 시 Watch 독립 빌드.
8. 소스 diff/호환성 감사, 기능별 유지 이유, 전후 결과 및 외부 인수 정리.

## 완료 기준

- 위 9개 영역 각각에 파일/함수·관련 테스트·개선 또는 유지 이유가 있다.
- 채택한 변경은 재현/측정과 기능 보존 증거를 갖추고 필수 검증이 통과한다.
- `./scripts/verify-platform-builds.sh` 최종 코드 통과. UI/iOS 전용 검사를 별도 집계한다.
- baseline과 결과를 같은 조건으로 비교하고 CPU/자동화 시간/첫 화면 반응을 구분한다.
- schema V1~V11, 호환 식별자, 백업 형식, 저장/수렴 의미를 보존한다.
- 결과 문서와 원본 증거가 연결된다. 실제 CloudKit·실기기 장시간 수명 등 외부 인수는 별도다.

## 작업 이력 — 아래 체크포인트는 기록 당시 상태

- 원본 공통 Debug: 480 통과, 5 opt-in 건너뜀, 실패 0.
- 세 조사 보고서: `results/{core,template-ui,widget-focus}-audit.md`.
- 원본 Release 백업: 190개 삽입/재병합 중앙값 66.32/127.05ms,
  1,900개 2,334.23/9,114.66ms. warm-up 1 + 표본 5, 생성/내보내기 제외.
- 원본 루틴/회고 Release projection 측정 진행 중. baseline/source에 계측 테스트만
  추가했으며 manifest에 기록한 시작 production 소스는 수정하지 않았다.
- 구현 중: 루틴 화면 계산 공유·미사용 조회 제거·quick-entry import gate,
  회고 블록 그룹화, 단계별 백업 부모 인덱스. 아직 수정 후 통과/개선 주장 없음.
- 위젯 지연 테마: 기존 동작의 재현 helper/테스트 준비. 초기 빌드 actor annotation
  오류는 수정했고, baseline 실패를 수집하기 전 실제 테마 읽기 순서는 유지했다.
- 전용 iPhone simulator: `8E608822-8353-492D-99C5-54F2ACE0D8F8` (iOS26.5).
  앱을 시작하기 전 xctestrun host에 UI-testing 격리 인수를 넣고 entitlement를 확인한다.
- 다음: projection 기준 실행 완료 → widget baseline 재현 → 코드 수정/관련 회귀 및
  전후 Release 측정 → 플랫폼·UI 검사 → 최종 게이트/보고서.

### 19:08 체크포인트

- 첫 후보 공통 Debug 완료: 489 pass, 8 opt-in skip (497 발견). `results/shared-debug-first.log`.
- 원본/첫 후보 Release 25조건 완료. `baseline/measurements.json`,
  `results/measurements-candidate1.json`, `results/comparisons-candidate1.json`.
  백업 1,900 replay 9,114.66→301.91ms, 회고64×100 all 699.07→40.63ms,
  루틴1000×3/10행 189.04→48.76ms. 루틴 결과 digest 12조건 일치.
- 첫 후보 no-match는 14.49→21.67ms로 느려져, 후보2는 빈 결과 grouping을 생략하고
  sourceTasks의 날짜 키를 한 번만 계산한다. 아직 후보2 재측정 전.
- 위젯 iOS 기준: 5검사 중 기대한 stale-theme 1실패, 나머지4 pass.
  현재 theme provider 호출 위치를 delay 뒤로 수정. 새 build/재검증 필요.
- 회고 event guard 수정 및 2페이지/취소/복귀 테스트 통과.
- 백업 resolver의 별개 unordered fetch 비교 문제를 같은 snapshot/역순 동등성으로
  고쳤으며 실제 병합/save 전 연결/rollback/retry/end-to-end도 통과.
- mac CFFIXED home probe 실패; 실제 PlanBase preferences에는 접근하지 않았다.
  mac 화면 검사는 향후 독립 diagnostic copy의 고유 CFBundleIdentifier,
  PlugIns/URL/UTI/container-migration 자원 제거, ad-hoc signing 및 명시적 UI 인수로
  격리한다. 원본 빌드/소스 호환 식별자는 변경하지 않는다.
- 현재 실행: 원본의 별도 UI clone에서 Release+DEBUG hooks build-for-testing,
  원본 공통 Release+DEBUG 계측 build(실행 아님). UI clone에는 CloudKit 차단을 위한
  양 root DEBUG guard만 별도 적용하고 `baseline/ui-isolation-changes.json`에 기록.
- 다음: build 완료 확인 → 기존 responsiveness 코어/폰 기준 계측 순차 실행 →
  후보2 Release template 재측정/기존 responsiveness 비교 → 최종 iOS 전용/화면/mac
  검사와 전체 verify-platform-builds 게이트. 변경하지 않은 코어 측정은 회귀 확인이며
  오래된 최적화의 성과로 합산하지 않는다.

### iPhone 기준 계측 완료 후 재개 지점

- `baseline/responsiveness-core.log`: 원본 기존 코어 계측 1개 pass. Release + `-DDEBUG`.
- `baseline/phone-performance.xcresult`: iPhone 성능 시나리오5개 모두 pass.
  raw metrics `baseline/phone-performance-metrics.json` (30지표), 텍스트 요약도 보존.
  준비된 DB의 FirstFramePresentationResponsive 중앙값3.772s(5회),
  스크롤/입력어/탭/상세·Focus는 자동화 IPC 포함 wall time과 CPU/memory를 구분했다.
  hitch/TabArchive 지표는 이 결과에 반환되지 않아 달성/개선 수치로 쓰지 않는다.
- 원본 UI Release 계측 빌드는 기존 trace helper의 Swift6 actor 진단으로 처음 실패.
  `phase` 함수와 closure를 MainActor로 명시한 동일 harness 수정으로 원본 clone과
  현재 테스트를 고쳤고 재빌드 성공. 실패 로그 `baseline/ui-build.log` 보존.
- 후보2 UI 준비 코드는 고정. 현재 실행 중인 build-only 작업:
  `results/candidate2-core-build.log` (일반 Release 공통 tests list),
  `results/ui-build.log` (수정본 iOS Release + DEBUG hooks build-for-testing).
  실행 중인 성능 측정은 없으며 전용 iPhone은 shutdown 상태다.
- 다음: 두 빌드 완료 → 후보2 template Release benchmark(skip-build) →
  수정본 코어 Release+DEBUG 별도 build 및 mac Debug build → 기존 코어 비교 →
  iPhone 같은5개 성능 비교 → iPhone/iPad 선택 UI·iOS unit·mac 화면 → 최종 게이트.
  widget 수정 이후 통합5개는 아직 재실행하지 않았다.
- 두 서브에이전트의 교차 검토에서 새 생산 코드의 조치 필요 결함 없음.
  실제 렌더링, 최종 검증 및 외부 인수 구분을 완료하기 전 Goal 완료 금지.

### 최종 후보2·iOS 연동 검증 체크포인트

- 후보2 루틴 Release 12조건 digest 일치 및 동등성 검사 통과. 첫10행
  189.04→47.71ms, 전체1,000행 8,816.11→690.22ms. 결과 없음은
  14.49→15.37ms로 후보1의 21.67ms보다 개선됐지만 기준 대비 약0.89ms 잔여 비용.
  후보만 포함하는 공용 메뉴 sourceTasks 준비 비용을 명시하고 추가 cache는 채택하지 않음.
- 기존 코어 Release+DEBUG 비교 완료: 보드240 9.225→9.169ms,
  저장작업1,000 load 94.75→84.70ms, 전체 수렴3,000 1,603.37→1,473.88ms,
  일일 첫page 309.46→274.92ms. 이번에 해당 알고리즘을 바꾸지 않았으므로
  이 수치는 환경 변동을 포함한 회귀 참고이며 이번 최적화 성과로 합산하지 않음.
- iOS Release hosted units 최초 실행은 테스트 시작 전 dyld 종료.
  원본/후보 모두 앱의 Frameworks 실행 경로가 빠져 있었고, Debug/Release 앱 설정에
  inherited + @executable_path/Frameworks만 추가. 새 LC_RPATH 확인 및 실제 host
  16개(위젯5 포함)·알림3개 통과. 실패 로그와 수정 후 xcresult 모두 보존.
  bundle/entitlement/package linkage 변경 없음. 서브에이전트 read-only 교차검토 완료.
- mac isolated artifact 준비: 독립 UUID bundle ID, PlugIns·URL/UTI·container migration
  자원 제거 및 entitlement 없는 ad-hoc 서명. 아직 실행 전이며 실제 앱/선호설정 불사용.
- 현재 후보 iPhone 성능5개를 원본과 같은 기기·빌드 조건으로 실행 중. 무거운 작업 병행 없음.
- 다음: iPhone 성능 결과 추출 → iPhone/iPad UI와 mac 진단앱 화면 → 최종 전체 게이트.

### 화면 검증과 안내 overlay 결함 체크포인트

- 후보 iPhone 성능5개 전부 통과. 전후30지표 비교 `results/phone-performance-comparison.json`.
  자동화 wall 중앙값 스크롤5.246→5.253s, 빠른입력2.935→2.907s,
  탭6.904→6.860s, 상세·Focus7.221→7.101s; responsive launch3.772→3.735s.
  스크롤 CPU1.080→1.131s로 소폭 증가, 절대 memory65,194→51,661kB.
  함수 개선을 전반적 화면지연 개선으로 확대하지 않음. hitch 지표 반환 없음.
- mac diagnostic GUI 완료: 루틴 빈목록/생성/저장/작업명검색/무결과/보드적용,
  회고 text/photo/본문/편집/메타데이터/탭복귀검색/Blush Pink테마.
  evidence `results/mac-ui-isolated/*.png`, `ui-verification.json`, 최종AX.
  해당 PID16946 종료. 실제 사용자 설정 불사용. 시작 NSTableView 경고1건은
  crash/assertion/흐름 실패 없이 관찰되어 원인 미확정 참고로 보존.
- iPhone UI 첫10개:9 pass/1 fail. 큰 글자 입력어 추가 직후 보관함 tap 실패.
  AX에서 saved-task-library y562~640, 비상호작용 board-status-notice y558~733 겹침.
  녹화55초 frame도 실제 가림을 확인. 원본 동일UI도 같은 줄2379 실패로 재현.
  `baseline/shortcut-regression.xcresult`, `results/phone-ui.xcresult` 및 attachments.
- root가 MobileBoardComponents.swift MobileStatusNotice에
  `.allowsHitTesting(destinationTitle != nil || onUndo != nil)` 추가.
  행동 없는 안내만 터치 통과. template_ui read-only 검토에서 버튼 조건과 일치 확인.
  접근성 announcement 그대로; 런타임 label/undo/destination 재검증 필요.
- iPad UUID `BC7881D8-2FC4-4EA0-8B36-DF5702E5B840` 생성. 기존후보7개 전부 pass,
  `results/pad-ui.xcresult` 완료 대기/추출 필요. 원본 추가재현과 일부 UI가 병렬 실행돼
  AX 대기450초 사례가 있으므로 이 실행시간은 성능값에 사용하지 않음. 이후 UI는 직렬.
- Xcode 실패후 자동 simctl diagnose가 결과완료를 지연시켜 소유 collector PID17412만
  SIGINT로 중단. 테스트10개 결과·화면·xcresult 정상보존. 이후 `-collect-test-diagnostics never`.
- 현재 새 overlay 수정본 iOS Release+DEBUG build-for-testing가 별도
  `results/ui-notice-build`에서 진행 중(기존 ui-build와 분리). 완료 후 iPhone 관련UI
  (큰글자입력어, 완료취소큰글자, 지난날목적지+취소, 일반안내AX, 루틴적용) 재실행.
- 남은 일: iPad screenshots 추출·시각검토, 수정후UI 직렬통과, 위젯 실제 렌더링
  (합성 fixture와 opt-in xctestrun 준비됨), final verify-platform-builds, 최종문서 정리.


### 안내 수정 후 UI 검증 완료 체크포인트

- 새 iOS Release+DEBUG build-for-testing 완료(`results/ui-notice-build`).
- iPhone 관련6개 모두 통과(`phone-notice-ui.xcresult`): 입력어 AX5/일반, 완료취소 AX5,
  지난날 목적지/취소, 회고 저장 일반안내 AX label, 루틴 생성·편집·적용.
- iPad 후속3개 중2개 통과, 최초 완료취소는 assertion 이전 runner SIGTERM.
  재시도도 Simulator Busy preflight로 시작 실패. 종료 상태의 전용 기기를 다시 boot한 뒤
  같은 코드·검사 완료취소1개 통과(`pad-undo-reboot.xcresult`). 최초 실패2개 보존.
  원인 신호는 확인했으나 최초 SIGTERM 발신자는 미확정으로 남긴다.
- iPad AX5 실제 캡처에서 안내의 완료보기·완료실행취소가 잘리지 않고 보이며 동작 통과.
- 최종 소스335개(코드/설정/스크립트) 사본·SHA를 `results/final-source*`에 고정.
  사진 에셋 등은 시작 manifest에 있으며 final-source는 명시 확장자만 포함한다.
- 비교25조건 출처 null을 보완한 새 `results/comparisons-final-with-sources.json` 생성.
  원래 수치·원본 비교 JSON은 보존.
- 위젯 visual용 사본은 앱그룹 entitlement만 ad-hoc 서명하며 CloudKit entitlement 없음.
  전용 iPhone Simulator에서만 설치·합성 snapshot 주입. 실제 사용자 그룹 사용 안 함.
- 남은 작업: 위젯 실제 렌더링, 최종 전체 게이트, 최종 문서 및 소스일치/호환성 재확인.


### 위젯 화면 완료·최종 게이트 체크포인트

- iPhone systemMedium 캘린더 실제 홈 화면 배치와 합성자료 표시2개 통과.
  `results/widget-visual-gallery.xcresult`, `widget-visual-layout.xcresult`.
  현재9월(5주)/이전8월(6주), roseLilac, 하루5개일정 AX 요약/overflow/월이동 확인.
  실제 PNG2장 시각검토 완료, `widget-visual-verification.json` 및
  `rendered-ui-inspection-final.json`에 범위/미실행 family 명시.
- 코드서명 사본은 Simulator 그룹을 등록하지 못해 전용 빌드에서 App Group만 지정한
  Simulated.xcent를 생성했다. CloudKit 권한 없음. 제품 프로젝트 설정 불변.
- 전용 iPhone/iPad 모두 shutdown. 실제 mac 진단앱 PID도 이전에 종료.
- 최종 게이트 첫 시도는 inherited SDKROOT가 CLT Swift6.4용 SDK를 가리켜 manifest 전 실패.
  로그 `final-platform-gate-sdk-mismatch.log` 보존. 실행 환경에서만 SDKROOT 제거,
  DEVELOPER_DIR를 사용 중인 Xcode로 고정해 전체 script 재실행 중.
- 결과문서 사실검토에서 수치25조건/출처/phone13/pad8 최종 pass 일치 확인.
  남은 필수는 최종 게이트 종료 및 같은 source manifest 확인, 문서 최종 상태 갱신뿐이다.


### 최종 완료 기록

- 최종 `./scripts/verify-platform-builds.sh` 종료0. Debug 공통489통과/8선택성능제외,
  Release487통과/7선택성능제외. iOS/macOS Debug/Release 및 내장 Watch·위젯/개인정보명세 통과.
- gate는 inherited SDKROOT만 제거하고 사용 중인 Xcode로 실행. 최초 SDK 불일치 실패 로그 유지.
- 관련 iOS hosted unit19개, iPhone13/iPad8개 고유기능 시나리오, 위젯 실제화면2개,
  mac 진단 앱 해당 흐름 완료. 최종 코드 이후 영향받는 UI 재검증 완료.
- 함수25조건, iPhone 성능5시나리오 전후측정 보존. 함수개선을 화면 전체개선으로 환산 안 함.
- final source335개 gate전후 SHA 동일, 보호35파일/주요6설정 동일, git diff 검사 통과.
- 커밋·push·PR·버전 증가·배포 없음. 운영 CloudKit/실사용자 저장소/iCloud Drive 접근 없음.
- 근거: `results/final-verification-summary.json`, `final-platform-gate-status.json`,
  `final-package-counts.json`, `compatibility-audit-final.json`, `final-source-manifest.json`.
- 남은 인수: 실제 CloudKit 왕복·실기기 알림/장시간 Activity/Intent/Watch/Pencil/전력.
  별도 한계: 최대글자 기록 제목 잘림, 무결과루틴 +약1ms, 100ms 초기피드백 미검증.
