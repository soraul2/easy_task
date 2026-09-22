# PlanBase UI·UX Goal 검증 기록

**필수 로컬 구현·검증 완료.** iPhone·iPad에 이어 권한 복구 후 Mac의 실제 창·키보드·체크리스트 저장/실패/취소와 공통 템플릿·회고를 검증했다. Mac 최소 창에서 캘린더 마지막 주와 하단 탭이 겹치는 결함도 재현·수정하고 같은 조건으로 재확인했다. 실기기 인수 항목은 아래에 별도로 남긴다.

기준 HEAD: `f7a0673c296cd4360da91bce0a812859a50b08b8`. 변경은 작업 트리에 있으며 이 Goal에서 커밋·푸시·TestFlight 업로드를 수행하지 않았다. 이전 배포 결과를 이번 변경의 배포 결과로 표시하지 않는다.

## 채택한 개선과 완료 근거

| 항목 | 변경 | 검증 결과 |
|---|---|---|
| U01 | 활동 기록/회고 제목을 inline으로 표시. 회고의 테마 버튼을 왼쪽으로 이동. 검색 힌트를 간결하게 표현. 낮은 가로 화면에서는 기록 종류 선택기도 스크롤. 두 pane의 검색 drawer는 회전 중에도 automatic 유지 | 같은 iPhone 일반/xxxLarge/AX5 × 세로/가로에서 두 pane 전후 12장씩 확보. 제목 잘림 해결. 추가로 최대 글자·대비 증가에서 회고 검색 응답 정지를 재현했고, 검색 drawer 표시 모드 고정 후 같은 상세/뒤로/필터/검색/회전 흐름 통과. 같은 멈춤 조건의 재검사까지 통과 |
| U02 | 완료 결과·작업 제목을 분리하고 행동을 적응형으로 배치. 목록 아래 안내 공간 확보 | AX5 안내 높이 약 329pt→262pt, 약 20% 감소. 15초 취소 규칙 유지. 연속 두 작업 완료의 최신 대상·실행 취소, 키보드 입력과 탭 복귀 검사 통과 |
| U03 | 칸반·캘린더·기록·메모 탭에 가시적 이름. Mac 캘린더에도 하단 콘텐츠 여백 적용 | iPhone·iPad 화면과 탭 이동 통과. Mac 900×712/1920×985 창, ⌘1~4, 집중 실행 버튼 공존·타이머 보존 확인. 캘린더 마지막 주의 탭 겹침을 없앰 |
| U04 | 빈 메모 중앙에 종류 선택 메뉴, 검색 결과 없음에 검색어 지우기 | 글/체크리스트/필기 빈 편집기를 닫아도 레코드가 남지 않음. 검색 초기화, 저장 실패 초안 보존·재시도, 탭·백그라운드 복귀 통과. OS 최대 글자 오류/빈 화면 보완 검사도 통과 |
| U05 | UI 대표 용어를 ‘템플릿’으로 통일. 공유 항목의 편집·삭제 영향을 상세와 편집 화면에 설명 | 생성/편집/취소/복제/중복 적용/날짜 조정/삭제 확인/저장 실패/입력어/즐겨찾기 관련 회귀 통과. Mac 목록·상세·만들기/취소·8개 적용도 확인. 내부 모델·식별자·사용자 콘텐츠 이름 유지 |
| U06 | 회고 제목 2줄·본문 4줄 미리보기와 전체 읽기. 템플릿 제목·작업 미리보기 2줄과 작업 전체 보기. 큰 글자에서 템플릿 선택기의 고정 폭 해제 | 같은 긴 fixture에서 다음 회고까지 12→2회, 다음 템플릿까지 3→1회 느린 스와이프. 전체 회고 본문 높이 5,477.67pt 전후 동일. Mac에서도 마지막 문장·사진 3장·편집 진입/취소·목록 복귀 위치와 템플릿 8번째 작업·전체 적용 확인 |
| U07 | Mac 체크리스트에 위/아래 이동 메뉴·접근성 행동, 이동 후 포커스 복구 추가. 드래그 유지 | 실제 키보드 추가/수정/완료/첫·중간·끝 이동/저장/재열기, 이동한 행 포커스, 취소 초안/원본 보호 통과. 실제 저장 명령 내부 오류 주입으로 rollback·초안 보존·재시도 확인. AX 이동 행동과 기존 드래그도 확인 |
| U08 | 행동이 없는 공통 저장 안내에 터치 통과 | 기준 앱에서 캘린더 저장 안내 중심 (195,728)pt를 누를 때 날짜 상세가 열리지 않는 결함 재현. 수정 후 같은 검사 통과. 회고 저장 직후 날짜 상세 진입·재저장도 통과 |
| U09 | 원본 접근성 지적 54건에 분류·근거·유지/조치 연결 | [54건 분류표](UI_UX_2026_09_22_ACCESSIBILITY.md). 최종 수집 54건은 결함 수가 아니다. 짧은 시스템 검색 힌트의 잠재적 잘림 지적은 실제 AX5 전체 표시 근거와 함께 유지했다. 이름·좌표 없는 원본 12건은 식별 한계를 명시하고 보존 |

## 유지한 부분과 이유

- **데이터 의미:** 스키마 V1~V11, 호환 식별자, 저장 서비스·CloudKit·백업·완료 활동·알림·15초 완료 취소를 변경하지 않았다. 화면과 DEBUG fixture/검사만 변경했다.
- **전체 내용:** 목록의 정보량만 줄였다. 상세 본문·사진·편집·적용 경로와 전체 접근성 이름을 보존했다.
- **색상:** 내부 글자/배경 실제 픽셀과 기존 테마 검사로 확인한 색 토큰은 유지했다. 검색 바의 `Text.foregroundStyle` 시험은 전후 픽셀이 같아 제외했다. 네이티브 검색 바 전체를 교체하지 않았다.
- **성능:** 기존 bounded query/session, 이미지 미리보기, 저장/rollback 및 알림 경계를 유지했다. 전체 테이블 관찰이나 원본 이미지의 목록 즉시 decode를 추가하지 않았다.
- **테마:** 현재는 8개 색상 구성과 3개 레거시 식별자 연결이다. apple2020/navyBlush→appleSystem, solarBerry→maroonEmber. 서로 다른 11개 색상 구성으로 보고하지 않는다. 8개 대표 화면과 레거시 선택, 어두운 테마의 할 일/진행/완료/저장한 작업 화면 및 기존 테마 규칙 검사 15개를 확인했다.

## 용어 기준

| 개념 | 이전 혼용 | 현재 UI |
|---|---|---|
| 재사용 작업 묶음 | 템플릿 / 저장한 루틴 | 템플릿 / 저장한 템플릿 |
| 생성·편집·상세·삭제 | 루틴 만들기·편집·상세·삭제 | 템플릿 만들기·편집·상세·삭제 |
| 개별 작업 재사용 | 저장한 작업 | 유지 |
| 사용자 제목 | 아침 루틴 등 | 사용자 콘텐츠이므로 유지 |
| 한 항목 템플릿/저장한 작업 | 공유 관계 설명 부족 | 편집·삭제의 양쪽 반영과 이미 추가된 보드 작업 보존을 해당 행동 가까이에 설명 |

## 시나리오별 검사

환경: Xcode 26.6 / Swift 6.3.3 / iOS Simulator 26.5. 전용 iPhone 17e 두 대와 iPad A16 한 대. `SDKROOT`는 검사 프로세스에서만 제거했다.

| 증거 폴더 (`.local/uiux-20260922/`) | 범위 | 결과 |
|---|---|---|
| `phone-final-probes/` | 원본 그대로 접근성 감사, 기록 3개 글자 크기×회전, 긴 목록, 연속 완료·키보드, 안내 뒤 날짜 터치 | 5개 통과 |
| `phone-regression/` | 검색·목록 복귀·사진, 기록/캘린더 AX5, 테마·날짜·초안, 완료 취소, 메모 실패/복귀, 템플릿/저장한 작업, 실제 동작 줄이기 설정 | 23개 통과 |
| `ipad/` | 실제 창 축소·다른 앱과 나란히 배치, 세로/가로, 메모 초안·선택·키보드, 기록/캘린더·보드·집중 상태, 템플릿/저장한 작업 | 8개 통과 |
| `acceptance-layout/` | 최종 템플릿 선택기, 템플릿 생성/편집/적용과 AX 행동, 긴 목록, AX5 가로 회고 상세·검색 | 4개 통과 |
| `search-style-check/` | 검색 힌트 색상 시험과 같은 12개 기록 화면, 빈 메모/검색 초기화 | 2개 통과. 색상 시험은 표시 차이가 없어 제외 |
| `final-AX5-recovery/` | OS 글자 크기 자체를 최대로 설정한 메모 최초 오류→재시도→작성/재열기, 세 종류 빈 편집기, 검색 초기화 | 2개 통과 |
| `final-contrast/` | OS 대비 증가, AX5 가로 회고 전체 읽기/뒤로/필터/검색과 완료 취소 | 완료 취소 통과. 전체 읽기/뒤로/필터 후 검색 입력에서 응답 정지. OS 최대 글자 자체로도 재현. 검색 drawer 표시 모드 고정 후 `contrast-search-reveal/`에서 전체 흐름 통과 |
| `ipad-final/` | 최종 소스의 실제 좁은 창 기록/캘린더, 회고 적응형 편집, 저장한 작업 접근, 빈 메모/검색 | 4개 통과 |
| `theme-tests.log` | 기존 AppTheme 규칙 | 15개 통과 |
| `final-platform-gate.log` | Debug/Release 공통 검사, iOS/macOS/watchOS Debug/Release 및 내장 Widget/Watch 번들 | 종료 코드 0. 공통 Swift Testing Debug 497개, Release 494개 통과 |
| `final-ios-release.log` | 첫 iOS Release 보완 빌드 | 종료 코드 0 |
| `stable-search-release.log` | 검색 응답 정지 수정 후 최종 iOS Release | 종료 코드 0 |
| `normal-search-reveal/` | 검색 수정 후 일반 설정의 AX5 가로 상세/검색, 독립 검색/활동 이동, 목록 위치 복귀 | 3개 통과 |
| `contrast-search-reveal/` | OS 최대 글자 + 대비 증가의 가로 상세/검색/회전 | 1개 통과 |
| `ipad-search-final/` | 검색 수정 후 iPad 독립 검색/활동 이동, 적응형 편집 | 2개 통과 |
| `final-records-contrast/` | 최종 소스로 최초 멈춤 조건 및 활동 기록/캘린더 큰 글자·대비 증가 | 2개 통과 |
| `final-records-default/` | 최종 접근성 raw 수집, 12개 기록 전후 조건, 긴 목록 수치 | 3개 통과. raw 54건은 별도 분류 |
| `rotation-input-final/` | OS 최대 글자 + 대비 증가에서 회전 후 검색어 유지·추가 입력·가로 화면 조작 | 1개 통과 |
| `mac-final-build.log`, `mac-final/isolation.json` | 권한 복구 전 Mac Debug 재빌드와 격리 | 당시 소스 해시 일치. 후속 Mac 두 파일 변경 전 기록으로 보존 |
| `mac-verification/` | 최소/넓은 창, 실제 키보드·포커스·저장/재열기/취소/실패, 캘린더 전후 | 화면·AX 원본 보존. 아래 Mac 시나리오별 결과 참조 |
| `mac-failure-build.log`, `mac-final-release.log`, `mac-verified/isolation.json` | DEBUG 저장 실패 주입 추가 후 Mac Debug/Release와 격리 앱 | 두 빌드 종료 코드 0. 실제 저장 실패·재시도·rollback 검사에 사용 |
| `mac-calendar-build.log`, `mac-calendar-release.log`, `mac-final-ux/isolation.json` | 캘린더 하단 여백까지 포함한 최종 Mac Debug/Release와 격리 앱 | 두 빌드 종료 코드 0. 최종 소스 해시 일치. 최소/넓은 캘린더·집중 상태와 템플릿 전체 보기/적용 확인 |

iPad 창은 실제 프레임이 (0,0,1180,820)pt에서 (403,0,375,743)pt로 바뀐 증거가 있다. 테스트용 폭 강제값만으로 좁은 창 검증을 대신하지 않았다.

## 전후 화면과 수치

경로 기준은 `.local/uiux-20260922/`이며 각 폴더의 `attachments/manifest.json`에 검사 이름과 모든 화면을 보존한다.

| 확인점 | 변경 전 | 변경 후 |
|---|---|---|
| 기록 제목 AX5 세로 | [잘린 기록 제목](../../../.local/uiux-20260922/before/attachments/13E597CC-AF6B-477D-A5C0-926D41C9F4B9.png) | [읽을 수 있는 기록 제목](../../../.local/uiux-20260922/final-records-default/attachments/3F415178-5BE9-4CB9-ACDA-A54DEF9411E7.png) |
| 완료 안내 AX5 | [변경 전 안내](../../../.local/uiux-audit-20260922/attachments/30F68402-1B39-4C0D-92C0-96E6BF8AEB64.png) | [공간 확보한 안내](../../../.local/uiux-20260922/after/attachments/7831C1D7-68FD-45A7-9173-6A8243F9AF62.png) |
| 캘린더 안내 뒤 터치 | [차단 재현](../../../.local/uiux-20260922/before-probes/attachments/7D210527-909B-43D4-9D28-6BFC7000D029.png) | [같은 위치 검사 통과](../../../.local/uiux-20260922/phone-final-probes/attachments/7F42DD26-08DD-4DE5-98DB-0DDCA9ABD594.png) |
| 긴 목록 탐색 | [회고 12회·템플릿 3회](../../../.local/uiux-20260922/before-long-final/attachments/79494C2B-C6D4-4873-9BC9-A220736AF3F6.txt) | [회고 2회·템플릿 1회](../../../.local/uiux-20260922/final-records-default/attachments/978CD99B-49C7-40D9-909A-C282E11CB626.txt) |
| Mac 체크리스트 정렬 | [기존 드래그 핸들](../../../.local/uiux-20260922/mac-verification/before-wide-checklist.png) | [명시적 순서 변경 메뉴](../../../.local/uiux-20260922/mac-verification/verified-add-2-settled.png) |
| Mac 최소 창 캘린더 | [마지막 주와 탭 겹침](../../../.local/uiux-20260922/mac-verification/calendar-before-clearance.png) | [콘텐츠 여백 적용](../../../.local/uiux-20260922/mac-verification/calendar-after-clearance.png) |

추가 화면: [키보드와 완료 취소](../../../.local/uiux-20260922/phone-final-probes/attachments/6E49A1B6-657A-448D-82F6-38EE6BA3C813.png), [OS 최대 글자 메모 생성](../../../.local/uiux-20260922/acceptance-system-AX5/attachments/6166CDE0-C93D-414D-A902-A48A81E3193D.png), [템플릿 큰 글자 요약/전체 보기](../../../.local/uiux-20260922/acceptance-layout/attachments/920D4B48-E9D1-4B9E-9AC3-EAFEAAC327C7.png), [실제 좁은 iPad 메모](../../../.local/uiux-20260922/ipad/attachments/11CE356F-008D-4F60-AA74-3C960AC67755.png).

안내 높이는 같은 1170×2532px, 3배율 AX5 이미지의 테두리 사이를 측정했다(약 1px 오차). 329.33→262pt, 화면 높이의 39.02%→31.04%. 자세한 값은 `completion-notice-measurement.json`에 있다. 목록 수치는 XCTest의 동일 느린 스와이프 수이며 사용자 수행 시간으로 해석하지 않는다.

## 검사 실패를 처리한 방식

- `before-long/`, `before-probes/`: 스크롤이 상단 고정 영역에서 시작하거나 첫 템플릿 행이 화면 밖에 있어 검사 조작이 실패했다. 실제 본문에서 드래그하고 대상 행을 화면 안으로 가져오도록 보정했다. `before-long-final/`에서 기준 측정을 통과했다.
- `before-probes/`의 안내 뒤 날짜 터치 실패는 실제 제품 결함이다. `MobileNoticeBanner.allowsHitTesting(false)` 수정 후 동일 검사 `phone-final-probes/`가 통과했다.
- `acceptance-contrast/`: 회고 열기 버튼이 상단 바 뒤에 있는데 AX가 hittable로 보고했다. 실패 화면/트리에서 y=-57.7…70.3pt를 확인했다. ‘전체 읽기’를 상·하단 바 사이에 완전히 표시한 뒤 누르도록 검사를 보정했다.
- `acceptance-system-AX5/`, `memo-AX5-retry/`: 최초 앱 실행에서 fixture 인수가 누락되는 해당 Simulator 런타임 현상이 재발했다. 오류 주입과 midnightBlue 테마가 모두 적용되지 않은 빈 화면을 기록했다. 기존 `launchKanbanFlowApp`와 같은 launch→terminate→launch 초기화로 보정한 `final-AX5-recovery/`에서 실제 오류 화면, 재시도, 메모 저장·재열기를 통과했다. 제품 저장/조회 서비스를 변경하여 검사를 맞추지 않았다.
- `final-contrast/`, `contrast-system-AX5/`: 회고 전체 읽기→뒤로→가로/세로 전환→필터→검색 입력에서 앱 CPU 약 100%, 이벤트 루프 응답 정지를 확인했다. `final-contrast/planbase-sample.txt`에는 메인 스레드의 SwiftUI/UIKit trait 갱신 반복이 있고, `live-timeout.png`를 보존했다. OS 최대 글자 자체로도 재현되므로 자동 검사 문제로 제외하지 않았다. 회전에 따라 검색 drawer를 always/automatic으로 전환하던 구성을 automatic으로 고정한 뒤 `contrast-search-reveal/`에서 41.7초 내 전체 흐름 통과. 검색 바가 접힌 경우 본문을 내려 다시 표시한 뒤 실제 입력하며, 검색어 보존까지 확인했다. 최초 멈춤 조건(OS 일반 글자 + 앱 AX5 fixture + 대비 증가)의 `final-records-contrast/`와 최종 두 기록 pane의 큰 글자/대비 검사까지 통과했다. 검색어 확인 직후의 화면은 회전 애니메이션 중에 캡처되어, 회전 후 실제 추가 입력과 최종 화면 검사를 보강했다. `rotation-input-final/`에서 검색어 ‘작은 진전’ 보존, ‘을’ 추가 입력, 가로 창과 입력 가능 상태까지 통과했다. [최종 가로 검색 화면](../../../.local/uiux-20260922/rotation-input-final/attachments/47AF8D2B-9D9C-4B74-BBC4-F323A63588A2.png).
- 첫 수정에서 inline 회고 제목이 오른쪽 버튼 3개에 밀리는 것을 화면에서 발견해 테마 버튼을 왼쪽으로 옮겼다. 템플릿 선택기의 220pt 고정 폭도 AX5 화면 근거로 해제했다. 자동 검사 통과만으로 화면을 승인하지 않았다.

## 소스 일치와 격리

전체 게이트는 22:00:15~22:13:48 실행, 종료 코드 0이다. 실행 중 검색 힌트 색상 시험과 검사 조작 보정이 있었으므로 `final-gate-status.json`의 `sourceUnchanged=false`를 숨기지 않는다. 모바일 최종화 당시 시작 해시와의 차이는 `MobileArchiveView.swift`, `MobileReviewDiscoveryView.swift`, UI 검사 파일이었다. 검색 수정까지 포함한 최종 iOS Debug 빌드는 `rotation-input-build/status.json`, 최종 iOS Release는 `stable-search-release.log`로 보완했다.

Mac 검증 재개 후 추가 변경은 `DesktopTaskDetailSheet.swift`의 DEBUG 오류 주입과 `AppRootView.swift`의 캘린더 하단 여백 두 파일이다. 이 최종 소스의 Mac Debug/Release 빌드가 각각 종료 코드 0을 반환했다. `mac-calendar-build.log`/`mac-calendar-release.log`는 quiet 빌드 출력이며, 성공 판정은 실행 도구가 반환한 종료 코드에 근거한다. 이전 전체 게이트가 이 두 후속 변경까지 검사했다고 주장하지 않는다. 공통·iOS·Widget·Watch 소스는 모바일 최종 검증 당시와 같다. `verification-source-complete.json`에 현재 소스 해시, 이전 검증별 차이, 보완 빌드와 앱 격리 기록을 연결했다. 이전 manifest는 덮어쓰지 않고 보존한다.

기준 프로젝트는 HEAD의 추적 파일에서 추출하고 동일 비교용 DEBUG fixture/검사만 추가했다. 테스트는 메모리 또는 전용 fixture 저장소와 전용 Simulator를 사용했다. Mac 비교 앱은 고유 bundle ID로 복사해 entitlement·PlugIns·문서/URL 연결·마이그레이션 리소스를 제거했으며 실제 배포 앱/사용자 저장소를 열지 않았다. 캡처의 ‘iCloud 권한 확인 필요’는 무서명 격리 앱의 예상 상태이며 운영 계정의 장애 판정이 아니다. iCloud Drive·`.local/backups/`·운영 CloudKit에 접근하지 않았다. 전용 Simulator 3대와 이 검증에서 실행한 격리 Mac 앱 4개는 종료했다. 키보드 검사에 사용한 macOS ‘키보드 탐색’은 원래 꺼짐으로 복원했다. 설치 이미지·fixture·스크린샷·실패 로그는 보존한다.

## Mac 실제 검증 완료

이전 22:43까지 세 번 연속 창 읽기가 `permission_denied`로 실패해 Goal을 `blocked`로 기록했다. `mac-final/blocked-audit.json`과 당시 실패 기록은 보존한다. 사용자의 재개 요청 후에는 접근성 창 읽기가 성공했다. 이후 실제 UI를 검증했으며, 권한 오류를 빌드 성공으로 대체하거나 필수 범위에서 제외하지 않았다.

| 시나리오 | 실제 관찰 결과 | 근거 |
|---|---|---|
| 탭 이름·단축키 | 900×712 최소 창과 1920×985 넓은 창에서 네 탭 이름 표시. ⌘1~4로 보드/캘린더/기록/메모 이동 | `final-minimum.png`, `verified-minimum.png`, `final-before-edge.png`와 키보드/AX 기록 |
| 캘린더 겹침 | 같은 900×712·9월·appleSystem·빈 일정 fixture에서 마지막 주 y=583~675와 탭 y=629~693이 겹쳤다. 캘린더에 기존 다른 탭과 같은 92pt 하단 여백 적용 후 마지막 주 y=507~583, 탭 시작 y=629로 46pt 간격 확보 | `calendar-before-clearance.png`, `calendar-after-clearance.png` |
| 집중 버튼 공존 | 최종 앱에서 25분 집중 시작→집중 창 닫기→⌘2→최소/넓은 창 전환. 네 탭·집중 실행 버튼·테마 버튼과 월 전체가 겹치지 않음. 재열기 시 24:37 진행 중, 종료 후 30초 기록 안내와 실행 버튼 해제 확인 | 재개 대화의 CUA 화면·AX 결과 및 `cua-observations.json` |
| 키보드 정렬 | 실제 키 입력으로 3항목 추가, 마지막 제목 수정, 완료 1/3. 마지막→중간→첫→중간→마지막 이동, 이동한 행의 메뉴로 포커스 유지. 첫 행 위/마지막 행 아래 행동 비활성화. 저장 후 키보드로 재열어 순서·제목·1/3 보존 | `keyboard-last-moved-settled`, `keyboard-middle-to-first-settled`, `keyboard-first-to-middle-settled`, `keyboard-middle-to-last-settled`, `keyboard-save`, `keyboard-reopen-settled`의 JSON/PNG |
| 취소와 초안 | 실제 타이핑으로 제목 변경→Escape→계속 작성은 초안 유지. 다시 Escape→변경 버리기→재열기는 원래 순서·제목·1/3 유지 | `cancel-real-settled`, `cancel-guard-continue-settled`, `cancel-guard-discard-settled`, `cancel-original-settled` |
| 실제 저장 실패·재시도 | DEBUG+`--ui-testing`+전용 인수에서 저장 명령의 체크리스트 교체 직후 최초 1회 오류. 오류 안내 후 3개 초안 유지, 순서 변경 후 재시도 저장 성공·A,C,B 재열기 | `failure-alert`, `failure-moved-*`, `failure-retry-saved-0`, `failure-reopen-verified-0` |
| 실패 후 원본 보존 | 저장된 A,C,B를 C,A,B로 변경→저장 실패→초안 유지→취소/버리기→A,C,B 원본 재열기 | `rollback-error-0`, `rollback-draft-0`, `rollback-original-0` |
| 접근성 행동·드래그 | A,C,B에서 B의 ‘위로 이동’ AX 행동으로 A,B,C. 기존 핸들 드래그로 C,A,B. 취소 후 저장된 A,C,B 유지 | CUA 실제 행동/AX 결과, `cua-observations.json` |
| 긴 회고 | 최소 창 목록 요약→전체 읽기→마지막 문장·사진 3장 확인→사진 3에서 편집 진입/취소→같은 사진/본문 위치→닫기 후 같은 목록 행의 픽셀 위치 | CUA 실제 화면/AX 결과, `cua-observations.json`. 스크롤 비율은 콘텐츠 범위 변화로 달라져 동일 비율이라고 주장하지 않음 |
| 긴 템플릿 | 최소 창의 520×640 시트에서 8개/2개 템플릿 요약. 전체 보기에서 8번째 작업과 체크리스트·하단 적용 행동 접근. 8개 적용 후 보드 할 일 2→10. 만들기/취소 후 템플릿 2개 유지 | 최종 앱 CUA 실제 화면/AX 결과, `cua-observations.json` |

체크리스트 전후 화면은 같은 1920×985 부모 창·540×720 시트와 동일한 3개 제목을 비교한다. 배경 보드는 저장 여부 차이가 있으므로 비교 범위는 편집 시트다. CUA 증거 요약 파일은 도구 결과를 정리한 관찰 기록이며 원시 자동 테스트 로그로 표시하지 않는다.

Mac 도구 사용 중 AX 값 설정만으로 TextField 바인딩이 반영되지 않는 경우가 있어 실제 타이핑으로 재검증했다. TextEditor는 Tab을 입력하므로 Control+Tab으로 이동했다. 즉시 캡처의 이전 화면, 부모/시트 좌표 혼동에 의한 드래그 실패는 도구 조작 문제로 구별했다. 시트 좌표의 실제 드래그 성공과 안정된 후속 AX 상태를 기준으로 판정했다. 파일 이름만으로 화면 내용을 추정하지 않는다.

## 추가 제안: 단일 날짜 일정의 두 줄 제목

사용자가 제시한 작은 월 캘린더 화면에 대한 디자인 제안이다. 이번 Goal의 구현 범위에는 추가하지 않았다.

2026-09-23의 후속 진행 요청으로 구현을 이어갔다. 해당 변경과 검증 상태는 [단일 날짜 제목 후속 결과](CALENDAR_SINGLE_DAY_TITLE_2026_09_23_RESULTS.md)에 별도로 기록한다.

- 실제 시작일과 종료일이 같은 일정에서 제목이 길 때 최대 두 줄을 허용하고, 짧은 제목은 한 줄을 유지하는 방안을 권장한다. 현재 앱은 날짜 범위 기반이므로 이 표시 개선을 위해 별도 종일 여부 필드나 스키마를 추가할 필요는 없다.
- 여러 날짜 일정은 연속성을 읽기 쉽도록 한 줄 막대를 유지한다. 주/월 경계에서 우연히 한 칸만 보이는 다일 일정을 단일 날짜 일정으로 판정하지 않는다.
- 날짜 칸의 높이는 유지한다. 일정 밀도와 남은 공간을 고려해 두 줄을 허용하고 넘치는 항목은 개수와 날짜 상세로 연결한다. 제목만 두 줄로 바꾸면 현재 고정 높이 막대·행 배치와 겹칠 수 있으므로 레이아웃도 함께 설계해야 한다.
- 후속 구현 시 좁은 iPhone·실제 좁은 iPad·Mac 최소 창, 긴 한글/영문·공백 없는 제목, 1/여러 일정, 주·월 경계, 큰 글자, 여러 날 일정과의 혼합을 같은 fixture로 비교한다. 읽을 수 있는 제목 증가와 숨겨지는 일정 수를 함께 평가한다.

## 별도 실기기 인수

VoiceOver 실제 발화, Pencil 입력, Watch 햅틱, 잠금/Always-On 및 실제 CloudKit 왕복은 로컬 UI/빌드 결과로 통과 처리하지 않는다. 현재는 미검증이다.

## 후속 배포

2026-09-23 별도 배포 요청으로 변경사항을 `2462a3d`에 커밋·푸시하고 iOS·macOS TestFlight 1.0(82) 업로드를 완료했다. 위의 미커밋·미배포 표현은 구현·검증 당시 범위를 설명한다. Apple 처리 및 남은 확인 범위는 [빌드82 배포 기록](../../releases/TESTFLIGHT_BUILD_82.md)을 따른다.
