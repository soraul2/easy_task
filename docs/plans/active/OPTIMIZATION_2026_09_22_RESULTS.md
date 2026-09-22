# PlanBase 전체 최적화 — 2026-09-22 결과

**상태: 로컬 필수 조사·구현·전후 측정·회귀·화면·전체 플랫폼 검증 완료. 실제 기기·서버 인수는 별도다.**

이 문서는 Goal의 변경 전후 측정과 기능별 검증 결과를 기록한다. 통과·실패 이력·제외·외부 미실행 범위를 아래에서 구분한다.

## 이번 변경

루틴 목록과 회고의 반복 계산, 백업 병합의 반복 부모 조회를 줄였다. 지연된 위젯 갱신이
새 테마를 되돌리는 오류와 큰 글자 화면에서 안내 메시지가 뒤쪽 버튼의 터치를 막는 오류도
재현 후 수정했다. 기존 기능·데이터 형식과 저장 경계를 유지했다.

| 변경 | 원인과 수정 | 의미 보존 근거 |
|---|---|---|
| 루틴 목록 준비 | 한 번의 화면 준비에서 검색 결과·현재 날짜의 작업을 공유하고 자식을 template ID별로 한 번 묶는다. 각 행은 자기 항목만 기존 순서로 초안 변환한다. 빈 검색 결과에서는 그룹화를 생략한다 | 물리 중복·동일 order의 입력 순서·검색·즐겨찾기·편집 직후 결과의 동등성 검사와 12조건 digest 일치. 상세·편집·적용은 기존 최신 데이터 경로 사용 |
| 보드의 불필요한 관찰 | iOS/macOS 보드에서 미사용 전체 템플릿/항목 `@Query` 4개 제거 | 템플릿 시트가 자체 조회, 빠른 입력이 자체 snapshot을 소유함을 확인. 보드의 날짜별 작업·일정 조회 유지. 관찰 4개 제거를 실측 SQL 횟수나 시작 시간으로 환산하지 않음 |
| 빠른 입력 갱신 | setup/export/미완료/실패 CloudKit 이벤트의 전체 라이브러리 재조회를 차단 | 성공 import 완료·로컬 템플릿 변경·실행 직전 재조회 유지. 변경된 입력어·삭제된 선택의 오실행 방지 검사 통과 |
| 회고 목록 준비·갱신 | 회고마다 전체 블록을 검색하던 작업을 호출 내 그룹화로 변경. 보이는 활성 화면만 갱신하고 CloudKit은 성공 import 완료만 처리 | 최신 빈 대표가 과거 내용을 되살리지 않음. 블록 순서·이미지·Unicode 검색 동등성, 2페이지 깊이·복귀 필터·취소 후 늦은 응답 검사 통과 |
| 백업 병합 | 자식 병합 단계마다 필요한 부모를 한 번 읽어 인덱싱하며 단계 간 캐시는 공유하지 않음 | 자연 키·논리/물리 ID·동일 시각 비교·최신 로컬 보존·저장 전 연결·실패 rollback·대기 편집 보존·재시도·재병합 검사 통과 |
| 위젯 지연 테마 | import 대기 전에 잡아 둔 테마가 최신 선택을 덮어쓰던 문제를 수정. 대기 뒤 테마를 읽음 | 실제 임시 snapshot 파일에서 `roseLilac`이 `appleSystem`으로 되돌아가는 기준 실패를 확보한 뒤 동일 검사 통과. 기존 증가 sequence와 동일 내용 쓰기 생략 유지 |
| 큰 글자 안내 메시지 | 동작 없는 `MobileStatusNotice`가 뒤쪽 보관함 버튼의 터치를 가로챔. 목적지/실행 취소 버튼이 있을 때만 터치 영역을 유지 | 원본과 후보의 기존 UI가 같은 위치에서 실패. 수정 후 iPhone 6개 검사 통과: 큰 글자 입력어·일반 입력어, 완료 취소, 지난날 목적지/취소, 회고 저장 안내, 루틴 적용. iPad 후속도 모두 통과(중단·재시도 이력은 아래 구분) |
| iOS 테스트 실행 경로 | 원본·후보 앱 모두 hosted Release test 시작 전에 Frameworks를 찾지 못함. 앱 Debug/Release에 inherited + `@executable_path/Frameworks` 추가 | 실행 파일 LC_RPATH 확인 후 실제 호스트의 위젯·백업·Activity·알림 19개 통과. 배포 ID·entitlement·package linkage 유지 |

회고 이벤트 재현은 2페이지 loader를 사용했다. 원래 67개의 무관하거나 비활성인 트리거가
134회 추가 조회를 발생시켰다. 초기 조회와 유효한 갱신을 합친 전체 호출은 142회였고,
수정 후 검사에서는 같은 계약의 8회만 허용한다. 기준 실패의 68개 assertion에는 마지막
누적 횟수 assertion의 연쇄 실패 1개가 포함되므로 이를 결함 68개로 세지 않는다.

## 기준과 측정 범위

- 기준은 HEAD `e93d7914aa9e06dd230b4efa21b9ab0ebb866ad9` 및 이번 Goal 시작 작업 트리다. 시작 시 앱 코드는 clean, 사용자 변경은 실행 프롬프트 문서 하나였다. 396개 소스/설정 파일 사본·SHA-256·diff를 보존했다.
- 실행 환경은 arm64 Apple Silicon, 메모리 32 GiB, macOS 27.0 `(26A428)`, Xcode 26.6 `(17F113)`, Swift 6.3.3이다. iPhone 성능 검사는 같은 전용 iPhone Simulator/iOS 26.5에서 전후 실행했다. 과거 macOS 26.6.2 수치와 비교하지 않는다.
- 함수 검사는 Release 공통 패키지와 격리된 메모리 저장소를 사용했다. 생성·초기 저장·내보내기·결과 비교는 측정 구간 밖이다. 백업 5회, 회고 7회, 루틴 20회 표본과 준비 실행을 분리했다.
- 전후 성능 실행 중 다른 무거운 빌드·테스트를 병행하지 않았다. 일부 기능 UI의 병렬 대기로 늘어난 실행 시간은 성능값으로 사용하지 않는다.
- 기존 반응성 코어와 iPhone 자동화는 Release 최적화에 DEBUG 계측/격리 hook을 포함한다. 일반 배포 Release의 성능으로 동일시하지 않는다.
- 증거 루트는 `.local/optimization-20260922/run-183419-5b7f4a/`다. 이하 상대 증거 경로는 이 디렉터리를 기준으로 한다.

## 같은 조건 전후 결과

25조건은 백업 4개·회고 9개·루틴 12개다. 아래는 대표 조건의 중앙값이며 전체 원본 표본은
`results/measurements-final.json`, 전체 비교는 `results/comparisons-final.json`에 있다.

| 함수 측정 조건 | 변경 전 | 변경 후 | 표본 수 |
|---|---:|---:|---:|
| 백업 190레코드 삽입 | 66.32ms | 43.90ms | 5 |
| 백업 190레코드 재병합 | 127.05ms | 32.69ms | 5 |
| 백업 1,900레코드 삽입 | 2,334.23ms | 439.52ms | 5 |
| 백업 1,900레코드 재병합 | 9,114.66ms | 301.91ms | 5 |
| 회고 64개·블록 192개·전체 결과 | 21.54ms | 2.95ms | 7 |
| 회고 64개·블록 6,400개·전체 결과 | 699.07ms | 40.63ms | 7 |
| 같은 회고·희소 검색 1개 결과 | 726.73ms | 62.16ms | 7 |
| 같은 회고·결과 없음 | 727.03ms | 62.48ms | 7 |
| 회고 64개 + 경계 날짜 물리 중복 80개·전체 결과 | 30.00ms | 3.79ms | 7 |
| 루틴 30개·항목 90개·첫 10행 준비 | 22.77ms | 7.67ms | 20 |
| 루틴 1,000개·항목 3,000개·첫 10행 준비 | 189.04ms | 47.71ms | 20 |
| 같은 루틴·1,000행 모두 준비하는 상한 실험 | 8,816.11ms | 690.22ms | 20 |
| 루틴 30개·검색 결과 없음·10행 한도 | 0.40ms | 1.11ms | 20 |
| 루틴 1,000개·검색 결과 없음·10행 한도 | 14.49ms | 15.37ms | 20 |

대표 대량 조건에서 백업 재병합은 약 96.7%, 회고 전체 결과는 약 94.2%, 루틴 첫 10행 준비는
약 74.8% 줄었다. 이는 측정한 함수 구간의 경과 시간이며 터치 반응·화면 표시 완료 시간은 아니다.

루틴 검색 결과가 없는 조건에는 약 0.7~0.9ms의 잔여 비용이 있다. 최초 후보의 대량 무결과
조건은 14.49→21.67ms로 느려져 빈 결과의 그룹화를 제거하고 날짜 키를 필터 밖으로 옮겼다.
최종 후보에서도 모든 조건이 빨라진 것은 아니다. 후보 측정에는 기준 모델에서 제외된 메뉴용
sourceTasks 준비도 포함되므로 이 차이는 전체 SwiftUI body의 정확한 비교가 아니다.
장기 캐시를 더하는 복잡성·무효화 위험을 감수할 근거는 부족해 현재 구조를 유지한다.
1,000행 상한 실험도 실제 화면에 1,000행이 동시에 렌더링됐다는 뜻이 아니다.

백업·회고 코드는 최초 후보 계측 후 변경하지 않아 해당 표본을 유지했다. 루틴은 최종 후보2로
다시 측정했다. 원본 로그는 `results/candidate-performance-release.log`, 루틴 최종 로그는
`results/candidate2-template-performance-release.log`다. 출처 경로를 모두 명시한 최종 비교본은
`results/comparisons-final-with-sources.json`이며 원래 비교 JSON도 보존했다.

## iPhone 화면 성능은 별도로 해석

원본·후보 각각 5개 성능 시나리오가 통과했다. 아래 wall time은 XCTest 입력·IPC·idle 대기를
포함한 자동화 구간이다. 보드 스크롤/탭은 10회, 나머지는 5회 표본이다.

| 측정 | 변경 전 중앙값 | 후보 중앙값 | 해석 |
|---|---:|---:|---|
| 보드 스크롤 자동화 wall time | 5.246s | 5.253s | 거의 같음 |
| 대량 빠른 입력 자동화 wall time | 2.935s | 2.907s | 비슷한 범위 |
| 네 탭 이동 자동화 wall time | 6.904s | 6.860s | 비슷한 범위 |
| 상세·Focus 진입 자동화 wall time | 7.221s | 7.101s | 해당 자동화 구간 |
| 준비된 저장소 재실행의 responsive 첫 프레임 지표 | 3.772s | 3.735s | cold boot나 개별 입력 피드백이 아님 |
| 보드 스크롤 앱 CPU 시간 | 1.080s | 1.131s | 약 0.051s 증가 |
| 보드 스크롤 절대 물리 메모리 | 65,194kB | 51,661kB | 이 구간에서 감소; 앱 전체 메모리 보장은 아님 |
| 대량 빠른 입력 앱 CPU 시간 | 1.881s | 1.737s | 이 시나리오에서 감소 |

`results/phone-performance-comparison.json`의 30지표와 원본 metrics를 함께 보존했다.
함수 비용 감소를 전반적인 화면 지연 개선으로 확대하지 않는다. 스크롤 CPU의 소폭 증가도
함께 기록한다. hitch/TabArchive 세부 지표는 반환되지 않았으며 **100ms 첫 시각적 피드백은
미검증**이다. 적은 표본의 p95를 안정적인 꼬리 지연으로 주장하지 않는다.

이 계측은 마지막 안내 메시지 터치 수정 전에 수행했다. 함수 최적화 코드는 같으며,
안내 수정 후에는 관련 기능 UI를 별도 재검증했다. 이 구분과 최종 소스 snapshot을 함께 남긴다.

시작 수렴·보드 projection·저장 작업 load·일일 활동 page의 기존 코어 비교도 새로 수행했다.
각 중앙값은 보드 9.225→9.169ms, 저장 작업 94.75→84.70ms, 전체 수렴
1,603.37→1,473.88ms, 일일 첫 page 309.46→274.92ms다. 이 알고리즘들은 이번에
변경하지 않았으므로 환경 변동을 포함한 회귀 참고값이며 이번 개선율에 합산하지 않는다.
무결성 no-op 후 report와 context에 변경이 없음을 확인했다.

## 기능별 조사 결론

| 영역 | 조사한 주요 경로·검사 | 결론 |
|---|---|---|
| 1. 시작·복귀·탭·무결성·import | 양 AppRootView, DataIntegrityService, PersistenceCommandService, activity import coordinator; 기존 시작 fixture·no-op/rollback/import 무효화 검사 | 전체 수렴을 생략하지 않는다. 동일 값 쓰기 회피·빈 archive 빠른 반환은 기존 구현으로 유지. DEBUG UI 실행의 계정 조회만 차단해 검사 격리 강화 |
| 2. 칸반·상태·완료 취소·체크리스트·이월 | TaskLifecycleService/TaskRules, CarryoverInboxSession; 최신 대표·실패·자정/시간대·실제 표시 후 확인·Undo 검사 | 미사용 템플릿 관찰과 수동 안내 터치 문제만 수정. 상태/진행/완료 기록의 원자성 및 체크리스트 독립성 유지. 이월 대표 재조회는 오래된 완료/이동 작업의 재등장을 막으므로 유지 |
| 3. 저장 작업·빠른 입력·루틴 | TemplateLibraryView/TemplateListRules/SavedTaskQuickEntryController/TemplateEditingService; 중복·Unicode·검색/편집·실행 직전 조회·다중 날짜 적용 검사 | 렌더 준비·import gate 채택. 검색 전용 계산과 다중 날짜 제목 집합은 이전 최적화로 구분. 전체 라이브러리 load를 임의로 잘라 성능 수치를 만들지 않음 |
| 4. 캘린더·기간 일정·재사용·템플릿 적용 | BoundedQueryService+Calendar, CalendarEventGridLayout/ReuseRules/RecommendationSession; 5/6주·동일 ID·기간·DST·독립 복제·최신 검색 검사 | 35/42일 범위와 최대 6주 배치 유지. 최근 200개 추천·취소 보호는 기존 설계. 새 복잡한 인덱스나 스키마 변경을 채택할 근거 없음 |
| 5. 활동 기록·직접 쓴 회고·첨부 | ArchiveQuerySession/DailyActivityQueryService/ReviewDiscoverySession/DiaryAttachmentIndex; 희소 날짜·검색 불일치·64행 경계 중복·페이지 깊이·취소/실패 검사 | 이미 있던 활동 pane 가드는 유지하고 새 회고 pane만 개선. 대표 최신 빈 회고·사진만 회고·메타데이터·첨부 무결성 유지. sparse 검색은 결과를 누락하지 않고 끝까지 탐색 |
| 6. 메모·텍스트·체크리스트·필기 | MemoService/QuerySession/EditorSession/Rules; 읽기 실패·초안/고정 실패·동시 import·긴 Unicode·페이지 복원 검사 | 40개 페이지·240자 미리보기·본문 전체 검색·600ms 자동 저장·이탈 즉시 flush 유지. 자식 읽기 실패를 빈 내용으로 저장하지 않음. 미리보기 최적화는 기존 성과이며 저장을 더 늦추지 않음 |
| 7. Focus·알림·Activity·deep link/Intent | FocusSessionService/TimerRules/ActiveSessionStore, TaskNotificationScheduler/LiveActivityCoordinator/IntentRuntime; pause/resume/revision·rollback·payload·route 검사 | 매초 전체 저장/조회 가설은 현재 코드와 맞지 않아 기각. 종료 기록과 기기 로컬 활성 타이머 경계, 알림 원본, 선택 token·session/revision 검증 유지. 관련 iOS 연동 7개 별도 실행 완료 |
| 8. iPhone/iPad/macOS 위젯·Watch | CalendarWidgetSnapshotPublisher/Store, WatchRoot/Today/Focus/Widget snapshot; 순서·동일 쓰기 생략·범위·Focus 우선·payload 검사 | 재현한 지연 테마만 수정. 공통 scheduler 재설계/Watch 강제 발행 제거는 측정 효과와 오류 경로 근거 부족으로 유지. iPhone 홈 화면 systemMedium 캘린더의 실제 렌더링 확인. 모든 family/플랫폼 표시 완료를 뜻하지 않음 |
| 9. 백업 내보내기·비파괴 병합·호환 | BackupPackageCodec/Merge/RecordMerge/ParentLookup; V2~V10·JSON V1/V2·hash/decode·한도·순서·동일/자연 키·대기 편집/rollback | 단계별 부모 인덱스 채택. 내보내기 원본 검증, 전체 무결성 수렴, 저장/실패 경계를 생략하지 않음. 향후 export/legacy 이미지 반복 스캔은 후보로 남기되 이번 성과로 포함하지 않음 |

상세 파일·재현 조건·유지 근거는 `results/core-audit.md`, `results/template-ui-audit.md`,
`results/widget-focus-audit.md`에 있다. 서로 다른 담당자의 변경을 읽기 전용 교차 검토했으며,
그 검토를 실제 플랫폼 실행의 대체 근거로 사용하지 않는다.

## 최종 검증 결과

| 검증 | 확인 상태 | 증거 |
|---|---|---|
| 시작 공통 Debug | 일반 480 통과, 선택 성능 5 제외, 실패 0 | `baseline/swift-debug.log` |
| 최초 후보 공통 Debug | 일반 489 통과, 선택 성능 8 제외 | `results/shared-debug-first.log`, `shared-debug-first-summary.json` |
| 최종 공통 Debug / Release | Debug 489 통과·8 선택 성능 제외 / Release 487 통과·7 선택 성능 제외, 실패 0. 발견 수 497/494에는 제외 건수가 포함됨 | `results/final-platform-gate.log`, `results/final-package-counts.json` |
| 관련 실패·동등성·취소 회귀 | 8개 통과 | `results/optimization-regression-debug.log` |
| 함수 성능 | 전후 25조건, 루틴 12조건 digest 일치 | `results/comparisons-final.json`, `measurements-final.json` |
| iOS 실제 hosted unit | 위젯 5·백업 7·Activity 4·알림 3, 총 19개 통과 | `results/mobile-unit-runpath-fixed.xcresult`, `results/mobile-notification.xcresult` |
| iPhone 성능 자동화 | 원본/후보 각 5시나리오 통과 | `baseline/phone-performance.xcresult`, `results/phone-performance.xcresult` |
| iPhone 최초 기능 UI | 10개 중 9 통과·1 실패. 큰 글자 보관함 터치 차단을 원본에서도 재현 | `results/phone-ui.xcresult`, `baseline/shortcut-regression.xcresult` |
| 안내 수정 후 iPhone UI | **6개 모두 통과, 실패 0**. 작성 중 로그의 종료 집계까지 직접 확인 | `results/phone-notice-ui.log:965`, `results/phone-notice-ui.xcresult` |
| iPad 최초 기능 UI | 7개 모두 통과. 큰 글자·적응형 회고·템플릿·입력어. 454초 대기 사례는 성능 근거로 사용하지 않음 | `results/pad-ui.log:1034`, `results/pad-ui.xcresult` |
| 안내 수정 후 iPad UI | 3개 모두 최종 통과. 2개 첫 실행 통과, 완료 취소는 runner SIGTERM 및 다음 Busy 실행 실패 후 기기 재시작으로 통과 | `results/pad-notice-ui.xcresult`, `results/pad-undo-retry.xcresult`, `results/pad-undo-reboot.xcresult` |
| macOS 실제 화면 | 독립 진단 앱에서 루틴 생성/항목 검색/무결과/적용, 회고 사진/본문/편집/메타데이터·탭 복귀 검색·테마 유지 확인. 실행 PID 종료 | `results/mac-ui-isolated/ui-verification.json`, 같은 폴더 PNG/AX |
| 위젯 실제 렌더링 | iPhone 홈 화면 systemMedium 캘린더: 배치 및 합성 일정 검사 2개 통과. roseLilac 테마, 5주/6주 현재·이전 달, 월 이동, 하루 5개 일정의 접근성 요약과 화면 +N 표시 확인 | `results/widget-visual-verification.json`, `widget-visual-layout-attachments/`, `widget-visual-gallery.xcresult`, `widget-visual-layout.xcresult` |
| 최종 `./scripts/verify-platform-builds.sh` | 종료 코드 0. 공통 Debug/Release, iOS/macOS Debug/Release와 내장 Watch·위젯 번들/개인정보 명세 모두 통과. Watch 소스 무변경으로 독립 scheme 추가 실행은 하지 않음 | `results/final-platform-gate.log`, `final-platform-gate-status.json`, `final-verification-summary.json` |
| 최종 소스·호환성 확인 | 최종 보호 파일 35개와 6개 설정 항목 모두 기준과 동일. 소스335개 사본·SHA·diff 고정 완료, gate 전후 소스 일치 확인 | `results/compatibility-audit-final.json`, `final-source-manifest.json`, `final-source-changes.patch` |

iPhone은 중복 실행을 제외한 13개, iPad는 8개 시나리오의 최종 결과가 모두 통과했다.
`results/ui-scenario-final-status.json`에 시나리오별 최종 결과와 원본 bundle을 연결했다.

최종 공통 검사 집계와 플랫폼 빌드는 재빌드한 최종 소스를 기준으로 한다. 전체 게이트
실행 전후 고정한 335개 소스·설정 파일의 SHA가 모두 일치했다. 일반 Release 빌드는
성능 계측용 DEBUG hook 포함 빌드와 구분해 통과했다.

macOS는 고유 UUID bundle ID·entitlement 없는 ad-hoc 진단 사본을 사용하고 원래 extension,
URL/UTI 등록·container migration 자원을 진단 사본에서만 제외했다. 제품 식별자를 바꾼 것이
아니다. 한국어 native typeText 입력이 불완전해 접근성 setValue로 입력 후 실제 저장값을
확인했다. 시작 때 NSTableView 경고 한 건이 있었으나 assertion/crash/관찰된 흐름 실패는
없었고 변경 탓으로 단정하지 않았다.

위젯의 최초 사후 ad-hoc 서명 사본은 공유 그룹을 등록하지 못했다. 전용 빌드의 simulator
entitlement를 App Group만 갖도록 제한한 뒤 전용 기기의 공유 공간이 정상 생성됐다.
Xcode의 `*-Simulated.xcent`에는 application identifier와 App Group만 있고 CloudKit 권한은 없다.
제품 설정 변경 없이 합성 JSON을 그 기기 그룹에만 넣었다. 최초 배치 검사와 최종 합성 표시
검사를 구분하며, iPad/macOS 홈 화면 배치나 모든 widget family를 검사했다고 주장하지 않는다.
사용한 전용 iPhone·iPad Simulator는 모두 종료했다.

## 실패 기록과 데이터 보호

기대된 기준 실패와 실제 검사 환경 실패를 모두 보존한다.

- 회고 이벤트의 기준 실패: `baseline/optimization-regression-retry.log`. 실제 수정 후 같은 계약 검사는 통과했다.
- 위젯 오래된 테마의 기준 실패: `baseline/widget-regression.xcresult`. 수정 후 위젯 5개 검사에 포함해 통과했다.
- 큰 글자 보관함 터치의 원본/후보 실패: `baseline/shortcut-regression.xcresult`, `results/phone-ui.xcresult`. 같은 테스트 줄 2379, 안내/버튼 AX 영역 겹침과 녹화 프레임을 확인한 뒤 수정했다.
- 첫 Swift 6 continuation/모델 전송·widget callback actor 진단: 원래 로그 보존 후 모델을 MainActor에 두고 Void 신호만 보내는 harness로 수정. `unchecked Sendable`로 우회하지 않았다.
- 백업 첫 비교 검사는 서로 다른 무정렬 fetch의 첫 물리 레코드를 비교했다. 원본 진단을 남기고 같은 snapshot/역순 snapshot의 동등성 검사로 보정했으며 실제 병합·rollback도 따로 확인했다.
- iOS unit 최초 실행은 assertion 이전 dyld 종료였다. `results/mobile-unit.log`와 dyld 진단, LC_RPATH 수정 후 실제 host 통과를 구분한다.
- iPad 완료취소 최초 실행은 앱 idle 대기 중 test runner가 SIGTERM으로 종료됐다. 다음 실행은 Simulator Busy preflight로 시작하지 못했다. 기기 재시작 후 같은 코드·동일 검사 통과. 최초 종료 신호의 발신자는 확인되지 않았으며 앱 assertion 실패로 단정하지 않는다.
- 최종 플랫폼 게이트 첫 시도는 상속된 `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`와 Xcode Swift 6.3.3의 불일치로 manifest 단계에서 종료됐다. `final-platform-gate-sdk-mismatch.log`를 보존하고 해당 실행 환경에서만 SDKROOT를 제거해 Xcode의 대응 SDK를 사용했다. 시스템 설정·프로젝트를 이 문제 때문에 수정하지 않았다.
- `CFFIXED_USER_HOME` 단독 macOS preferences 격리 probe는 실패했다. 실제 앱 실행에는 사용하지 않았고 고유 진단 bundle 방식으로 전환했다.
- 실패 뒤 자동 `simctl diagnose`가 결과 정리를 지연시켰다. 테스트 소유 수집 프로세스만 종료했으며 이미 나온 테스트 결과·xcresult·화면을 보존했다. 이후 자동 추가 진단 수집을 비활성화했고 테스트 자체의 결과와 구분했다.

실제 사용자 저장소·CloudKit 서버·iCloud Drive·`.local/backups/`에 접근하지 않았다.
검사는 메모리/전용 로컬 fixture, 전용 preferences·임시 snapshot·새 Simulator를 사용한다.
스키마 V1~V11, EasyTaskCore 모듈, bundle/container/App Group 식별자, 백업 형식·레거시 경로를
유지한다. 호환성 감사의 보호 파일 35개와 `PRODUCT_BUNDLE_IDENTIFIER`,
`CURRENT_PROJECT_VERSION`, `MARKETING_VERSION`, `CODE_SIGN_ENTITLEMENTS`,
`REGISTER_APP_GROUPS`, `SWIFT_VERSION`은 기준과 같았다.

저장 명령의 대기 편집 보존·save/rollback, Task 상태와 진행/완료 활동의 원자성,
논리/물리 ID·superseded 수렴, 최신 대표 선택과 첨부 원본 검증을 그대로 둔다.
최적화 Goal 자체에서는 커밋·push·PR·버전 증가·TestFlight 업로드·배포를 수행하지 않았다.
이후 명시적으로 요청된 커밋·푸시와 빌드81 업로드는 별도 배포 기록에 연결한다.

## 외부 인수와 남은 한계

iPhone 최대 접근성 글자 크기에서 기록 화면의 큰 제목 일부가 toolbar 아래로 잘리는 모습을
캡처했다. 검색·pane 전환·reader 동작은 통과했지만 이 별도 표시 결함은 이번에 수정하지 않았다.
모든 화면의 잘림이 해소됐다고 주장하지 않는다. 긴 내용은 스크롤이 필요하다.
근거는 `results/phone-ui-attachments/852641D8-D799-48D1-9A50-46D0B9F2B656.png`다.
탐색·편집 기능은 유지되며 이 제목 문제에는 toolbar의 별도 적응형 배치 검토가 필요해,
현재 계산·갱신 최적화와 터치 차단 수정에 전면 배치 변경을 섞지 않고 후속 항목으로 남겼다.

로컬 검사와 별도로 실제 CloudKit 기기 간 왕복, 배포 버전 간 실제 사용자 백업 왕복,
OS 알림 전달·취소, App Intent의 실제 백그라운드 실행, 잠금 인증/Always-On/Dynamic Island,
사용자 Activity 해제 뒤 장시간 수명, 위젯 reload 예산과 갤러리 정책,
Watch 손목 내림·햅틱·실제 컴플리케이션, Apple Pencil·VoiceOver 음성 탐색,
실기기 전력·발열·메모리 압박은 인수가 남는다. 이 Goal에서 운영 CloudKit에 접속하지 않는다.

로컬 필수 범위는 완료했다. 위 외부 인수와 명시한 잔여 비용·표시 문제는 완료 범위와
혼동하지 않는다. 최적화 Goal 종료 시점에는 커밋하지 않은 작업 트리였다. 이후 사용자가 요청한
커밋·푸시·TestFlight 업로드의 별도 진행 상태는 [빌드81 배포 기록](../../releases/TESTFLIGHT_BUILD_81.md)에 남긴다.

## 증거 색인

| 근거 | 위치 |
|---|---|
| 시작 소스·환경·diff | `baseline/source/`, `baseline/manifest.json`, `baseline/environment.txt` |
| 함수 원본 표본 | `baseline/backup-performance-release.log`, `baseline/projection-performance-release.log` |
| 함수 후보 표본 | `results/candidate-performance-release.log`, `results/candidate2-template-performance-release.log` |
| 25조건 최종 비교 | `results/comparisons-final.json`, `results/measurements-final.json` |
| 기존 코어 회귀 참고 | `results/responsiveness-core-comparison.json` |
| iPhone 성능 30지표 | `results/phone-performance-comparison.json`, 양쪽 `phone-performance-metrics.json` |
| 기능별 조사 | `results/core-audit.md`, `results/template-ui-audit.md`, `results/widget-focus-audit.md` |
| macOS 화면/격리 | `results/mac-ui-isolated/ui-verification.json`, PNG/AX, `results/mac-preferences-probe/` |
| 데이터/식별자 보존 | `results/compatibility-audit-final.json` |
| 최종 검증·소스 고정 | `results/final-verification-summary.json`, `final-platform-gate.log`, `final-source-manifest.json`, `final-source-changes.patch`, `widget-visual-verification.json` |
