# PlanBase 문서 지도

현재 구현과 운영 절차는 아래 운영 문서를 기준으로 한다. `plans/`의 계획·측정값·검증 결과는
각 문서에 적힌 날짜와 소스 기준의 기록이며, 최신 빌드의 검증 결과로 간주하지 않는다.

## 현재 상태

기준일: 2026-10-03

| 항목 | 기준과 확인 범위 |
|---|---|
| 최신 업로드 | [TestFlight 1.0 (86)](releases/TESTFLIGHT_BUILD_86.md), iOS·iPadOS·watchOS 및 macOS |
| 배포 준비 | [TestFlight 1.0 (87)](releases/TESTFLIGHT_BUILD_87.md), 두 archive·iOS Production 패키지·전체 게이트 확인 완료. iOS 계정 오류·Mac 설치 서명 인증서 부재 이후 사용자 요청으로 업로드 후속 보류 및 Git 반영. 계정·설정은 사용자가 직접 준비하며 업로드 성공은 미확인 |
| build 86 배포 확인 | 두 플랫폼 업로드 성공·Apple 패키지 처리 시작. 설치 가능 상태·외부 테스트 심사·공개 출시는 확인 범위 밖 |
| 데이터 계약 | `EasyTaskSchemaV11`, CloudKit V11 Production, 캘린더 위젯 snapshot v5, 백업 package V10 |
| 최근 변경 | [보드의 저장한 작업 `/` 안내와 접근성 힌트](releases/TESTFLIGHT_BUILD_86.md#포함한-변경) |
| build 86 확인 | Debug 511·Release 507 공통 테스트, 전체 플랫폼 게이트, Release archive·Production 서명·배포 패키지 확인 |
| 남은 확인 | 새 안내의 실기기·VoiceOver, iOS 27 타이머·Focus 실기기, 저전력·Always-On·최소 글꼴 가독성, TestFlight 설치와 기존 IME·작은 화면·탭 반응성 인수 |

업로드 성공, 기능 검증 완료, 성능 개선 확인은 서로 다른 상태다. 이전 빌드의 테스트 통과나
측정값으로 build 86의 체감 성능·실기기 동작을 보증하지 않는다.

## 운영 문서

| 문서 | 찾을 내용 |
|---|---|
| [빠른 시작](../README.md) | 앱 소개, 개발 환경, scheme, 기본 검증 명령 |
| [에이전트 작업 지도](../AGENTS.md) | 접근 제한, 변경 경계, 기능별 수정 위치 |
| [프로젝트 구조](../PROJECT_STRUCTURE.md) | 디렉터리·주요 진입점·파일 추가 규칙 |
| [아키텍처](ARCHITECTURE.md) | 모듈 경계, 데이터 흐름, 화면 갱신, 무결성·백업 |
| [CloudKit 동기화](CLOUDKIT_SYNC.md) | entitlement, schema 배포, 수렴 진단과 운영 인수 절차 |
| [Apple Watch](WATCHOS.md) | 독립 실행형 앱·컴플리케이션 데이터 흐름과 출시 확인 |

## 구현·검증 후속 작업

`plans/active/`에는 구현 중인 작업뿐 아니라 구현 후 실기기 확인이 남은 작업과 그 근거 문서를
함께 둔다. 아래 설명은 기록된 확인 범위이며, 이번 문서 정리에서 기능을 다시 검증한 것은 아니다.

### 반응성과 화면 품질

| 주제 | 상태와 연결 문서 |
|---|---|
| [2026-10-02 성능·사용 흐름 최적화](plans/active/OPTIMIZATION_2026_10_02_PLAN.md) | 9영역 조사·채택, 메뉴/초기 로딩10조건 비교, 최신 main UI2개·전체 플랫폼 게이트·안내 검토 완료. 2026-10-03 최신 사용자 지시로 실제 잠금 화면·Watch·일부 Mac 인수와 TestFlight87 업로드를 후속 보류하고 현재 변경의 commit·push를 진행한다. Goal 도구의 이전 blocked 상태와 화면 미완료 기록은 유지한다. [결과와 측정 한계](plans/active/OPTIMIZATION_2026_10_02_RESULTS.md), [Goal 실행 프롬프트](plans/active/OPTIMIZATION_2026_10_02_GOAL_PROMPT.md) |
| [2026-09-29 캘린더 추천 사용성](plans/active/CALENDAR_RECOMMENDATION_USABILITY_REVIEW_2026_09_29.md) | build 84 구현·공통/플랫폼 회귀·격리 화면·업로드 완료, 수동 IME·VoiceOver 등 미확인 범위 유지 |
| [2026-09-28 탭 반응성·Focus](plans/active/TAB_RESPONSIVENESS_AND_FOCUS_2026_09_28_RESULTS.md) | build 83 구현·빌드·업로드 완료, 기능·성능 실측 미실행 |
| [2026-09-22 UI·UX](plans/active/UI_UX_2026_09_22_PLAN.md) | 필수 로컬 구현·검증 완료. [결과·실기기 미확인 범위](plans/active/UI_UX_2026_09_22_RESULTS.md), [최초 점검](plans/active/UI_UX_2026_09_22_AUDIT.md), [접근성 54건 분류](plans/active/UI_UX_2026_09_22_ACCESSIBILITY.md), [실행 프롬프트](plans/active/UI_UX_2026_09_22_GOAL_PROMPT.md) |
| [2026-09-23 캘린더 두 줄 제목](plans/active/CALENDAR_SINGLE_DAY_TITLE_2026_09_23_RESULTS.md) | build 82 포함. iPhone·iPad 확인, 최종 Mac 화면과 일반 실행 영향 미확인 기록 유지 |
| [2026-09-22 전체 최적화](plans/active/OPTIMIZATION_2026_09_22_PLAN.md) | 9영역 조사·구현·전후 측정·로컬 검증 완료. [결과·외부 인수](plans/active/OPTIMIZATION_2026_09_22_RESULTS.md), [실행 프롬프트](plans/active/OPTIMIZATION_2026_09_22_GOAL_PROMPT.md) |
| [2026-09-14 추가 최적화](plans/active/OPTIMIZATION_2026_09_14_RESULTS.md) | 루틴·빠른 입력 반복 계산 개선과 당시 측정·회귀 결과 |
| [build 76 기준 전체 최적화](plans/active/OPTIMIZATION_BUILD_76.md) | 구현·로컬 검증 완료. [결과·실기기 인수](plans/active/OPTIMIZATION_BUILD_76_RESULTS.md) |
| [2026-09-04 반응성 최적화](plans/active/RESPONSIVENESS_OPTIMIZATION.md) | 당시 실기기 측정 기록과 남은 100ms 초기 피드백 확인 |
| [UI 디자인 일관성](plans/active/UI_DESIGN_CONSISTENCY.md) | build 71 기준 진행 기록·미확인 항목. [당시 UI 소스·화면 목록](plans/active/UI_DESIGN_SURFACE_INVENTORY.md) |
| [iPhone Duo 적응형 인터페이스](plans/active/IPHONE_DUO_INTERFACE_PLAN.md) | 일반 iPhone·iPad 적응형 구현·검증 완료, Duo 전용 환경 대기 |

### 작업·집중·기록과 데이터

- [이월함·회고 탐색](plans/active/CARRYOVER_AND_REVIEW_DISCOVERY_PLAN.md): 구현·격리 화면·플랫폼 확인 완료. [결과·실기기 확인 범위](plans/active/CARRYOVER_AND_REVIEW_DISCOVERY_RESULTS.md), [잠금 화면 동작 계약](plans/active/LOCK_SCREEN_TASK_SELECTION_FOLLOWUP.md), [실행 프롬프트](plans/active/CARRYOVER_AND_REVIEW_DISCOVERY_GOAL_PROMPT.md)
- [칸반 입력·진행·완료와 실행 취소](plans/active/KANBAN_FLOW_IMPROVEMENT.md)
- [저장한 작업 빠른 입력어](plans/active/SAVED_TASK_SHORTCUT_PLAN.md): V11 도입·Development 왕복 기록과 실기기 인수
- [Focus 모드·집중 타이머](plans/active/FOCUS_MODE_PLAN.md): 최초 설계·플랫폼별 동작과 실기기 인수. build 83 후속 변경은 위 결과 문서 참조
- [회고 없이도 보이는 하루 기록](plans/active/ARCHIVE_DAILY_ACTIVITY_PLAN.md), [구현 검증](plans/active/ARCHIVE_DAILY_ACTIVITY_VALIDATION.md)
- [활동 스트릭·히트맵·통계](plans/active/ACTIVITY_STREAK_HEATMAP_PLAN.md)
- [일정 재사용과 계획일·완료일 기록](plans/active/EVENT_REUSE_AND_TASK_DATE_HISTORY_PLAN.md)
- [Task 완료 전환 알림 보존](plans/active/TASK_REMINDER_COMPLETION_RETENTION_PLAN.md)
- [macOS·iPhone 기능 정합성](plans/active/CROSS_PLATFORM_PARITY_PLAN.md): 수동 백업·CloudKit 왕복 인수 포함

### 위젯과 Live Activity

- [2026-09-29 Dynamic Island 작업 시간 멈춤 분석](plans/active/DYNAMIC_ISLAND_TASK_TIMER_ANALYSIS_2026_09_29.md): build 85 업로드 완료, iOS 27/26.5 연속 갱신 및 최소·가로 표시 검증, 실기기 확인 대기
- [캘린더 위젯 밀도](plans/active/CALENDAR_WIDGET_DENSITY_PLAN.md)
- [macOS 바탕화면 네이티브 위젯](plans/active/MACOS_DESKTOP_WIDGET_PLAN.md)
- [월간 일정·오늘 작업 플래너 위젯](plans/active/PLANNER_WIDGET_PLAN.md)
- [잠금 화면 위젯](plans/active/LOCK_SCREEN_WIDGET_PLAN.md)
- [오늘 캘린더 일정 잠금 화면 위젯 사용 안내](CALENDAR_LOCK_SCREEN_WIDGET_GUIDE.md): 기능 포함 버전의 추가 방법·표시 내용·마지막 발행 데이터와 갱신 한계. 실제 OS 화면 확인은 최적화 결과의 미완료 항목을 따른다.
- [Task 중심 잠금 화면·Live Activity](plans/active/LOCK_SCREEN_TASK_LIVE_ACTIVITY_PLAN.md)

실제 위젯 갤러리·잠금 인증·저휘도·알림 전달과 Watch 햅틱은 각 문서의 미완료 항목을 따른다.
CloudKit의 오프라인 충돌·재설치·재로그인·기기 간 왕복은 [운영 절차](CLOUDKIT_SYNC.md)에 따라 별도로 확인한다.

## 완료된 설계·구현 기록

- [테마 정리와 대표색](plans/completed/THEME_REFINEMENT_PLAN.md)
- [칸반 작업 카드 디자인](plans/completed/KANBAN_CARD_DESIGN.md)
- [메모 생성 유형 분리](plans/completed/MEMO_TYPE_CREATION_PLAN.md): 로컬 기능 검증 완료. 과거 일반 CloudKit 실행 영향의 미확인 기록 유지
- [저장한 루틴 중심 템플릿 UI/UX](plans/completed/TEMPLATE_UX_IMPROVEMENT.md)
- [집중모드 화면과 예상 시간](plans/completed/FOCUS_EXPERIENCE_POLISH_PLAN.md)
- [칸반 화면·버튼·테마 완성도](plans/completed/KANBAN_SERVICE_POLISH_PLAN.md)
- [저장한 작업](plans/completed/SAVED_TASK_LIBRARY_PLAN.md)
- [접근성·문구·파일 구조](plans/completed/ACCESSIBILITY_AND_MAINTAINABILITY_PLAN.md)
- [기록·회고 UI/UX](plans/completed/ARCHIVE_REVIEW_UI_UX_PLAN.md)
- [캘린더 경험 디자인](plans/completed/CALENDAR_EXPERIENCE_DESIGN_PLAN.md)
- [iPad 네이티브 지원](plans/completed/IPAD_SUPPORT_PLAN.md)
- [칸반 상태 UI/UX](plans/completed/KANBAN_STATUS_UI_UX_PLAN.md)
- [UI 리팩터링](plans/completed/REFACTORING_PLAN.md)
- [Task 알림 최초 구현](plans/completed/TASK_REMINDER_PLAN.md)

완료는 각 작업에서 정한 범위의 완료를 뜻한다. 문서 안의 당시 파일 크기·테마 수·스키마·측정값과
미확인 기록은 보존하고, 현재 구현은 운영 문서를 기준으로 판단한다.

## 배포·기반 전환 이력

| 기록 | 내용 |
|---|---|
| [TestFlight 1.0 (87) 준비](releases/TESTFLIGHT_BUILD_87.md) | 2026-10-03 최적화·오늘 일정 잠금 화면 위젯, 실제 화면 인수 후속 보류 |
| [TestFlight 1.0 (86)](releases/TESTFLIGHT_BUILD_86.md) | 2026-10-02 저장한 작업 `/` 빠른 입력 안내 |
| [TestFlight 1.0 (85)](releases/TESTFLIGHT_BUILD_85.md) | 2026-09-29 Dynamic Island 타이머·Focus 상태·장시간 표시 개선 |
| [TestFlight 1.0 (84)](releases/TESTFLIGHT_BUILD_84.md) | 2026-09-29 캘린더 최근 일정 추천 사용성·검색 개선 |
| [TestFlight 1.0 (83)](releases/TESTFLIGHT_BUILD_83.md) | 2026-09-28 탭 반응성·Focus, 테스트·계측 생략 |
| [TestFlight 1.0 (82)](releases/TESTFLIGHT_BUILD_82.md) | 2026-09-23 캘린더 두 줄 제목·UI 접근성 |
| [TestFlight 1.0 (81)](releases/TESTFLIGHT_BUILD_81.md) | 2026-09-22 최적화·안정성 |
| [TestFlight 1.0 (80)](releases/TESTFLIGHT_BUILD_80.md) | 2026-09-17 이월함·회고·잠금 화면 |
| [TestFlight 1.0 (79)](releases/TESTFLIGHT_BUILD_79.md) | 2026-09-16 업로드·검증 근거 |
| [build 78까지의 CloudKit·배포 이력](releases/CLOUDKIT_AND_RELEASE_HISTORY_THROUGH_78.md) | 2026-07~09 서버 스키마·실기기 수렴·TestFlight 기록 |
| [데이터 기반 전환 계획](DATA_FOUNDATION_PLAN.md) | 최초 데이터 안전 전환 순서·Git 운영 규칙·남은 기반 인수 |
| [구조 정리 체크리스트](STRUCTURE_CLEANUP_CHECKLIST.md) | 2026-07 완료 당시 구조 정리 스냅샷 |

## 문서 갱신 규칙

- 최신 업로드는 이 문서의 현재 상태와 해당 `releases/` 문서에 기록한다. 구조·운영 문서에는 배포 이력을 반복해서 쌓지 않고 연결한다.
- 구현 결과에는 기준 소스, 변경 범위, 실제 수행한 확인과 미실행 항목을 구분한다. 과거 결과를 최신 빌드의 검증으로 바꾸지 않는다.
- 새 문서는 이 목록에 연결하고, 이동 시 기존 상대 링크도 함께 수정한다. 계획·결과·실행 프롬프트는 같은 주제로 묶는다.
- 미완료 확인이 남은 작업은 업로드만으로 `completed/`로 옮기지 않는다. 후속 문서로 넘기는 경우 원문과 새 문서를 서로 연결한다.
- `.local/`의 진단·배포 자료는 Git 비추적 증거다. 공유해야 할 결론은 문서에 남기며 `.local/backups/`는 임의로 정리하거나 덮어쓰지 않는다.
