# PlanBase UI·UX 점검 — 2026-09-22

기준: `f7a0673` / TestFlight 1.0(81). 이번 작업의 산출물은 점검 결과와 후속 Goal 프롬프트다. 제품 코드를 수정하거나 개선 Goal을 시작한 작업은 아니다.

## 점검 방법과 범위

- 현재 iOS/iPadOS 루트, 칸반·기록·회고·메모·캘린더, 공통 템플릿·집중 모드, macOS 탭과 작업 상세, Watch 화면의 관련 소스를 조사했다.
- 9월 22일 최적화 검사에서 보존한 iPhone·iPad·격리 macOS 화면을 직접 다시 읽었다. 과거 화면은 과거 증거로 표시하며 최신 실행 증거와 구별한다.
- 현재 소스로 별도 Debug 검사 앱을 빌드하고, 전용 iPhone 17e / iOS 26.5 Simulator에서 메모리 fixture를 사용하는 4개 UI 검사를 실행했다. 4개 모두 통과했으며 아래에 화면 품질과 자동 감사 결과를 별도로 기록한다.
- 이전 디자인 점검은 build 70/71 기준이며 이후 기능이 추가됐다. 그 문서의 통과/미검증 목록을 현재 상태로 그대로 옮기지 않는다.
- 실제 사용자 저장소·운영 CloudKit·iCloud Drive·`.local/backups/`는 이번 점검 대상이 아니다.

원본 실행 증거: `.local/uiux-audit-20260922/`.
기존 화면 증거: `.local/optimization-20260922/run-183419-5b7f4a/results/`.

## 우선순위와 판단

P1은 읽기·연속 조작에 직접 영향을 주는 문제, P2는 기능 발견성과 조작 편의 개선이다. 화면에서 확인한 현상과 사용자에게 미치는 영향에 대한 판단을 구별한다.

| ID | 우선순위 | 확인 수준 | 현상 / 개선 방향 |
|---|---|---|---|
| U01 | P1 | 현재 화면에서 재현 + 코드 | iPhone 최대 접근성 글자에서 기록 → 회고 제목 일부가 잘린다. 활동 기록·회고가 모두 큰 navigation title을 사용한다. 활동 기록도 같은 조건에서 추가 확인한 뒤 적응형 제목·toolbar 배치로 수정한다. 정확한 원인은 레이아웃 조사 후 확정한다. |
| U02 | P1 | 현재 화면·조작 확인 + 코드 | 최대 글자에서 완료 안내와 두 행동이 화면 높이의 약 40%를 차지한다(이번 fixture의 육안 추정). 완료 취소 자체는 새 검사에서도 통과했다. 연속 작업을 가리는 면적을 줄이고, 실행 취소·목적지 이동을 유지하는 배치가 필요하다. |
| U03 | P2 | 화면·코드 확인 / 영향은 UX 판단 | 주요 네 탭이 아이콘만 표시된다. 접근성 이름과 Mac 도움말은 있지만 시각적 이름은 없다. 특히 기록·메모의 의미 구분을 돕는 짧은 탭 이름을 검토한다. |
| U04 | P2 | 현재 빈 화면·조작 + 코드 | 메모가 없을 때 중앙에는 안내만 있고 생성은 상단 아이콘 메뉴에 있다. 검색 결과가 없을 때도 직접 초기화 행동이 없다. 빈 화면에서 새 메모 종류 선택, 검색 결과 없음에서 검색어 지우기를 제공할 수 있다. |
| U05 | P2 | 화면·코드 확인 / 영향은 UX 판단 | 진입과 검색은 ‘템플릿’, 목록·작성은 ‘루틴’이다. 1개 항목의 루틴과 저장한 작업이 같은 데이터라는 설명은 목록 뒤에 있다. 화면 용어와 편집·삭제 영향 설명을 행동 가까이에서 일관되게 제공한다. |
| U06 | P2 | 화면·코드 확인 / 추가 계측 필요 | 큰 글자에서 회고 목록 본문이 무제한 줄로 표시되고, 루틴 설명도 한 화면 이상 길어질 수 있다. 목록 요약과 전체 읽기를 구분해 다음 항목 탐색 부담을 줄일 여지가 있다. 전체 내용은 명시적인 상세/펼치기로 접근 가능해야 한다. |
| U07 | P2 | 코드 확인 / 실제 키보드·VoiceOver 미검증 | macOS 작업 상세 체크리스트 정렬은 드래그 핸들과 drop handler로 구현돼 있으며 해당 행에 명시적인 위/아래 이동 대안이 없다. 키보드·접근성 정렬 경로를 재현하고 필요한 대안을 추가한다. |
| U08 | 조사 후 결정 | 코드상 후보 | 회고 저장 안내와 캘린더 안내도 overlay를 사용하지만, 칸반 안내와 같은 터치 통과 처리가 보이지 않는다. 저장 직후 뒤쪽 행동을 가리는지 먼저 실제 재현한다. 코드만으로 터치 결함을 확정하지 않는다. |
| U09 | P1 조사 | 현재 자동 감사 원본 54건 | 칸반 10·캘린더 40·기록 3·메모 1건이 수집됐다. 대비 44·터치 영역 2·확대 시 잘림 가능성 8건이며, 중복·시스템 요소·측정 범위 문제를 포함할 수 있다. 실제 결함으로 분류한 뒤 색상 토큰·접근성 구조·배치를 필요한 만큼 수정한다. 54개 제품 결함이라는 뜻은 아니다. |

### 근거 위치

- U01: `mobile/App/Features/Archive/MobileReviewDiscoveryView.swift:70`, `MobileArchiveView.swift:164`. 기존 `phone-ui-attachments/852641D8-D799-48D1-9A50-46D0B9F2B656.png`의 ‘기록’ 제목 일부가 잘린다. 검색·회고 선택·읽기 동작의 통과와 제목 품질은 별개다.
- U02: `mobile/App/Features/Board/MobileBoardComponents.swift:7`, `MobileBoardView.swift:303`. 기존 `phone-notice-ui-attachments/AAE193C3-B278-4E8D-A68B-27775E3FB905.png`. 칸반의 수동 행동 없는 안내에 `.allowsHitTesting(false)`가 적용된 것은 이미 완료된 수정이다. `TaskCompletionUndoService.availabilityDuration`의 15초 의미도 보존한다.
- U03: `mobile/App/MobileAppRootView.swift:91`, `desktop/App/FloatingTabBar.swift:13`. 기존 `mac-ui-isolated/routine-applied-board.png`와 iPhone 화면. ‘이름이 없다’는 시각적 표시를 뜻하며 접근성 레이블이 없다는 뜻이 아니다.
- U04: `mobile/App/Features/Memo/MobileMemoView.swift:156`. 회고의 `ReviewDiscoveryEmptyState`, 템플릿의 빈 상태에는 이미 직접 행동이 있으므로 인접 패턴을 활용할 수 있다.
- U05: `shared/Core/Components/TemplateLibraryView.swift:60`, `:112`, `:119`. 기존 `phone-ui-attachments/4351840E-244B-4D41-AF73-CF091D8F49F6.png`에서 혼용을 확인한다. 실제 사용자가 혼동했다고 주장하는 사용자 연구 결과는 없다.
- U06: `shared/Core/Components/ReviewDiscoveryViews.swift:81`의 접근성 글자에서 `lineLimit(nil)`. 기존 `phone-ui-attachments/C5A69EF7-7807-44F6-BF26-6CFBC1D4A9DA.png`는 큰 글자 루틴의 긴 설명과 행동을 보여 준다. 스크롤 자체는 결함이 아니며 목표는 내용 보존과 탐색 효율이다.
- U07: `desktop/App/Features/Board/DesktopTaskDetailSheet.swift:292`, `:589`. 위/아래 이동 없이 `.draggable`과 `.dropDestination`이 연결된다. 시스템 보조 기술이 제공하는 실제 경로는 별도 검증해야 한다.
- U08: `mobile/App/Infrastructure/MobileUIComponents.swift:141`, `mobile/App/Features/Calendar/MobileCalendarView.swift:127`, `MobileCalendarGrid.swift:184`.

## 이미 있는 기능과 보존할 부분

초안 폐기 확인, 저장 실패 시 초안 보존·재시도, 삭제 영향 설명, 큰 글자에서 세로 배치와 상태 메뉴, iPad 분할 화면·선택 복원, 테마 공통 토큰, 칸반 완료 취소는 이미 구현돼 있다. 후속 작업은 이 기능을 새로 만든 것으로 보고하지 않는다.

최근 최적화에서 iPhone 13개·iPad 8개 시나리오의 최종 결과가 통과했다. 이 수치는 당시 실행 결과이며 이번 점검의 새 실행 수와 합산하지 않는다. 위젯·Watch·Focus의 모든 상태가 현재 버전에서 실기기 검증됐다는 뜻도 아니다.

## 자동 감사 결과 해석

`testCollectPrimaryScreenAccessibilityAuditFindings`는 대비·터치 영역·설명·글자 잘림의 지적을 저장한 뒤 handler에서 `true`를 반환한다(`mobile/Tests/PlanBaseLaunchUITests.swift:6211`). 의도된 수집용 검사다. 따라서 검사 성공을 ‘접근성 문제 0건’으로 해석하면 안 된다.

후속 Goal에서는 지적별로 실제 결함 / 시스템 요소 / 의도된 요약 / 중복 여부를 육안 및 조작으로 분류한다. 확인된 제품 결함은 문제별 회귀 검사로 막고, 자동 검사만으로 실제 VoiceOver 발화·읽기 순서 통과를 주장하지 않는다.

## 새 실행 결과

2026-09-22 21:12~21:16 KST, 현재 소스 `f7a0673`에서 별도 Debug 빌드를 실행했다. 빌드 종료 코드 0, UI 검사 4개·실패 0, 검사 시간 약 136초다. 검사 전후 추적한 소스·설정 SHA가 일치했다. 사용한 전용 Simulator는 종료했다. 제품 코드·설정은 변경하지 않았다.

| 새 검사 | 결과 | 의미 |
|---|---|---|
| 주요 네 화면 접근성 감사 수집 | 통과 | 화면 진입·지적·스크린샷 수집 성공. 접근성 적합 판정이 아님 |
| 큰 글자 이월함·회고 조작 | 통과 | 해당 조작 가능. 첨부된 회고 목록에서 제목 잘림은 재현 |
| 최대 글자 완료 실행 취소 | 통과 | 취소 동작 정상. 안내가 큰 면적을 차지하는 UX 현상 확인 |
| 메모 종류 선택·빈 초안 닫기 | 통과 | 세 종류 진입과 빈 초안 정리 동작 정상. 빈 화면의 직접 생성 행동은 없음 |

첨부 파일은 `.local/uiux-audit-20260922/attachments/manifest.json`에 테스트별로 연결돼 있다.

| 화면 근거 | 새 파일 |
|---|---|
| U01 기록 제목 잘림 | `attachments/A546FAA5-600E-404B-830A-942410FE6C75.png` |
| U02 완료 안내 면적 | `attachments/30F68402-1B39-4C0D-92C0-96E6BF8AEB64.png` |
| U03/U04 메모 빈 화면·탭 | `attachments/FF52ED14-6CC8-4E1C-8D46-809BD944DE3C.png` |
| 메모 종류 선택 | `attachments/357ADEE2-9764-449B-B0B3-65A5328E6668.png` |
| 일반 글자 칸반·캘린더·활동 기록 | `attachments/92E87CF4-937B-4296-8E0F-C4A6C85C1762.png`, `B7E1A97E-807C-4242-96F1-8AA3A99E3C27.png`, `92A9835E-D173-49EB-BACE-E987B0D2FB89.png` |

자동 감사는 `appleSystem` 일반 글자 네 화면에서 54건을 보고했다. U01의 최대 글자 잘림과는 검사 조건이 다르며 서로 중복 집계하지 않는다. `may be clipped`는 확대 시 문제 가능성을 뜻한다. 캘린더의 의도된 짧은 공휴일명·일정 요약과 실제 정보 소실을 구별하고 날짜 상세·접근성 이름으로 전체 내용을 읽을 수 있는지도 확인해야 한다. 칸반의 ‘보통’·‘예상 30분’은 표시용 텍스트인지 독립 행동인지부터 분류해야 한다. 대비는 실제 글자·배경 색과 상태를 대조하기 전 확정하지 않는다.

이번 새 실행은 iPhone에 한정된다. iPad/macOS는 현재 코드와 기존 화면 증거를 검토했으며 새 실행 완료로 집계하지 않는다. Watch·위젯·실기기 VoiceOver의 새 실행도 수행하지 않았다.

## 다음 Goal의 검증 범위

- iPhone: 일반/중간 확대/최대 접근성 글자, 좁은 세로·가로, 키보드 표시, 대표 밝은·어두운 테마.
- iPad: 세로·가로·좁은 창에서 목록↔상세, 검색/스크롤/선택/초안 유지. 테스트용 폭 변경과 실제 창 변경은 구별한다.
- macOS: 최소 지원 창과 넓은 창, 키보드만으로 탭·검색·편집·취소·체크리스트 순서 변경. 격리 fixture로 검사한다.
- 변경된 공통 UI: 11개 테마를 대표 화면으로 확인하고 문제가 있는 조합에 상세 검사를 집중한다. 모든 기능×테마 조합을 검사했다고 주장하지 않는다.
- Focus·위젯·Watch: 공통 구성요소 변경의 영향을 점검하고 영향이 있으면 해당 화면을 검사한다. 실기기 햅틱·잠금·Always-On·Pencil·실제 VoiceOver 발화는 별도 인수 상태로 기록한다.

## 판단에 사용한 Apple 공식 자료

탭 이름은 의미를 더 명확히 전달하는 데 도움이 된다는 Apple 디자인팀의 설명을 U03의 판단에 참고했다. 같은 자료의 단계적 정보 노출 설명은 U06의 설계 후보를 뒷받침한다. 제품에서의 실제 효과는 별도 검증해야 한다. [Apple Design Q&A](https://developer.apple.com/news/?id=s8sl4tpa)

큰 글자에서 적응형 배치를 사용하고 필수 내용을 보존하는 기준은 [Get started with Dynamic Type](https://developer.apple.com/videos/play/wwdc2024/10074/)을 참고한다. 터치 영역·글자 겹침·대비는 [UI Design Dos and Don’ts](https://developer.apple.com/design/tips/)를 참고한다.
