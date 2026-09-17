# 이월함·회고 탐색·남은 작업 실시간 카드 구현 결과

작성일: 2026-09-17
상태: Goal 구현·격리 화면 검증·최종 플랫폼 게이트 완료. 실기기 미확인 범위는 아래에 별도 기록.
기준 브랜치/HEAD: `codex/kanban-card-design` / `dd2e1d2`의 작업 트리.

## 적용한 동작

- 이월함: 실제 오늘 기준 전체 개수, 기기별 새 작업 강조, 하루 한 번 안내, 새 항목 우선 표시.
  최초 성공 조회를 기준 목록으로 삼고 화면에 표시한 항목만 확인 처리한다. 전체 수는 열어도 유지된다.
  작업 ID와 계획일을 함께 사용하므로 제목 변경·물리 중복 교체는 새 작업이 되지 않고, 다시 이월된
  날짜는 새 항목이 된다. 조회와 처리 시 대표 레코드를 다시 확인한다.
- 기록: 내부 `활동 기록 / 회고` 선택기. 회고는 제목·본문·사진·날씨·기분·레거시 블록을 기준으로
  모으며 Task 기록을 조회하지 않는다. 전체 기간, 독립 검색/기간, 페이지, 전체 읽기, 수정, 이날 활동
  연결을 제공한다. 사진만 있는 회고도 포함하고 최신 대표가 비어 있으면 이전 중복을 되살리지 않는다.
- 잠금 화면: 오늘 todo 또는 doing이 있으면 하나의 Live Activity를 생성·유지한다. todo는 시작,
  doing은 완료, 변경은 표시만 순환한다. 시작은 선택한 작업만 바꾸고 기존 다른 doing을 멈추지 않는다.
  모두 완료하거나 오늘 후보가 없어지면 즉시 종료한다. 상태/선택 토큰으로 오래된 버튼과 중복 입력을
  거절하고 같은 Activity를 갱신한다. Focus/휴식 우선순위와 미래 알림 완료 확인을 유지한다.

SwiftData 스키마, 호환 식별자, 백업 형식은 변경하지 않았다. 기존 칸반 빈 상태·체크리스트 변경을
보존했다. Goal 구현 단계에는 배포를 포함하지 않았으며, 이후 사용자의 별도 요청으로
[TestFlight 1.0 (80) 업로드](../../releases/TESTFLIGHT_BUILD_80.md)를 진행했다.

## 구현 중 발견하고 수정한 문제

1. 회고 카드 컨테이너의 접근성 식별자가 자식 버튼 식별자와 겹침: 컨테이너 식별자를 제거하고
   날짜/제목을 버튼의 명시적 접근성 이름으로 제공했다.
2. 회고에서 처음 `이날 활동 보기`를 열 때 세션이 비어 있는 시트: 날짜와 조회 세션을 하나의
   presentation 값에 묶었다. 수정 후 iPhone/iPad 전환 테스트를 통과했다.
3. 회고 편집기가 다루지 않는 기존 날씨·기분이 저장 시 지워짐: 생략한 필드는 보존하고 명시적 빈
   값만 지우도록 저장 API를 보완했다. iPhone/iPad/Mac 화면과 공통 저장 테스트로 확인했다.
4. 수정한 회고 제목을 UI fixture의 시작 표식으로 사용해 테스트 재실행 때 fixture가 중복 생성됨:
   테스트 전용 로컬 seed 표식으로 교체했다. 운영 실행 경로에는 적용되지 않는다.
5. 내부 탭을 돌아올 때 스크롤 위치가 초기화됨: 재생성 중의 초기 위치 보고가 저장한 날짜를 덮어쓰지
   않도록 복원 구간을 보호했다. Mac은 접근성 스크롤 때 ID 바인딩 갱신이 빠지는 경우가 있어 실제
   보이는 날짜도 기록한다. iPhone 자동화와 Mac 1·2페이지 왕복에서 읽던 날짜 복원을 확인했다.
6. 큰 글자에서 마지막 이월 작업을 옮긴 뒤 목록 높이가 줄어 처리 안내가 위로 밀려남: 결과 안내를
   목록 상단의 고정 영역으로 옮겼다. 성공 문구를 짧게 표시해 긴 제목이 화면을 차지하지 않게 하고
   접근성 이름에는 작업 제목을 유지했다. 기존 마지막 항목 회귀 테스트가 iPhone 14/15, iPad 04에서 통과했다.
   짧은 최종 안내의 iPhone 화면은 15 실행 증거다.

## 격리와 증거 위치

- 공통 테스트는 메모리/임시 로컬 저장소를 사용했다.
- iPhone: `PlanBase Discovery iPhone`, iPhone 17 Pro / iOS Simulator 26.5,
  `D3E926DB-624D-4394-B863-9BE6D0CD53C0`.
- iPad: `PlanBase Discovery iPad`, iPad Pro 13-inch (M5) / iPadOS Simulator 26.5,
  `B80F337B-161A-4A5E-AEC0-63518CB3219E`.
- Mac: 테스트 인수가 고정된 별도 서명 앱 `com.soraul2.planbase.discovery-ui-tests`와 UUID 저장소.
  운영 앱을 실행하지 않았다. 900pt 최소 창과 1920pt 넓은 창을 점검했다.
- 실제 CloudKit 기기 간 동기화 대신 로컬 fixture/변경 이벤트를 사용했다. iCloud Drive 금지 경로와
  `.local/backups/`에 접근하지 않았다.
- 전체 증거: [`.local/carryover-review-discovery`](../../../.local/carryover-review-discovery/).
  Mac 검증 앱과 이번 작업의 두 Simulator는 확인 후 종료했다. 테스트 저장소와 증거는 보존했다. 시작 diff는 `baseline/starting.patch`, 화면 증거는 `screenshots/`, 결과 번들은 `*.xcresult`다.
  최종 변경 소스·설정 SHA-256은 `final-source-sha256.json`에 기록했다. 새 파일도 포함하고
  삭제 경로는 `final-deleted-paths.txt`에 별도 기록했다. 변경 전체는 새 파일을 포함한
  `final-working-tree.patch`, 최종 Git 상태는 `final-git-status.txt`에 보존했다.
  [증거 색인](../../../.local/carryover-review-discovery/EVIDENCE_INDEX.md)에서 실행별 결과와 대표 화면을 찾을 수 있다.

## 검증 결과

| 검증 | 결과와 근거 |
|---|---|
| 공통 Debug | 총 485개 중 480개 통과, 선택 성능 검사 5개 제외. `platform-gate-verified.log`의 공통 테스트 단계 |
| 공통 Release | 총 482개 중 478개 통과, 선택 성능 검사 4개 제외. Debug 전용 테스트 제외. `platform-gate-verified.log` |
| 추가 경계·실패 검증 | 0/1/99/100/140개(조회 batch 경계 포함), Seoul/LA 날짜 왕복, 실패한 이동·진행 명령 rollback, 기존 정적 위젯 시작 제한. `boundary-tests-final.log` 4개 테스트(개수 테스트는 5개 입력) 통과 |
| 이월함 iPhone | 개수 4/새 항목 2 → 확인 후 새 항목 0 → 오늘 이동 후 3 → 재실행 유지. `discovery-iphone-03.xcresult` 1개 통과 |
| 회고·잠금 화면 iPhone | 최초 todo 카드, 변경/시작/완료/종료, 동일 Activity ID 유지; 회고 수정·읽기·활동 연결·독립 검색. `discovery-iphone-07.xcresult` 3개 통과 |
| 기존 기능 및 큰 글자 iPhone | 빈 칸반, 상태별 체크리스트 기본 펼침·독립 접기, 회고 없는 활동 기록, 회고 조회 실패/재시도, 사진만 회고, 큰 글자, 실제 집중/휴식 Live Activity 일시정지·재개·종료. `discovery-iphone-08.xcresult` 7개 통과 |
| iPhone 스크롤 복원 | `discovery-iphone-09.xcresult` 1개 통과. 25일 전 회고까지 이동 후 탭 왕복 |
| 마지막 이월 항목·큰 글자 | 고정 안내·빈 이월함·보드 반영: `discovery-iphone-14/15.xcresult`, `discovery-ipad-04.xcresult` 각각 1개 통과. 15는 성공 문구를 짧게 다듬은 최종 화면 |
| 추가 기존 흐름 iPhone | `discovery-iphone-10.xcresult`: 회고 저장/취소, 사진 선택 취소, 사진 carousel의 현재·레거시·누락 표시, 이월 미래 알림 경고, 과거 doing 이월함 포함의 5개 통과. 큰 글자 마지막 항목 실패는 fixture 실행 인수 누락·탐색 절차 및 앱의 안내 위치를 수정한 뒤 별도 실행으로 검증 |
| 이월함 iPad | 이동/확인/재실행 유지 통과. `discovery-ipad-01.xcresult`의 carryover 테스트 1개. 나머지 3개는 테스트 탐색 방식 실패로 제외하고 02에서 재검증 |
| 회고·잠금 화면 iPad | 큰 글자, 가로/세로, 390pt 영역으로 분할 축소, 초안 유지·수정, 사진만 회고, 독립 검색, 실제 Activity todo/doing 액션·종료. `discovery-ipad-02.xcresult` 5개 통과 |
| iPad 스크롤 복원 | `discovery-ipad-03.xcresult` 1개 통과. 읽던 회고 날짜로 복귀 |
| Mac | 새 작업 2/전체 4 → 열어 확인 → 이동 후 전체 3/새 작업 0; 회고 수정·기존 메타데이터 보존·활동 연결·Escape 복귀·독립 검색·2페이지 조회·읽던 날짜 복원. `mac-*.json/png`, `screenshots/mac-page2-before-switch.png` / `mac-page2-restored.png` |
| payload 호환 | 실제 `PlanBaseTaskActivityAttributes.swift`를 iOS Simulator 실행 파일로 컴파일하여 기존 payload/wire key, todo round-trip, Focus 우선순위, 이전 attributes 4항목 통과. `payload-audit.log` |
| 테마·접근성 | 밝은 기본/charcoalRose 실제 화면, 가장 큰 Dynamic Type, 접근성 수치/액션/선택기 식별. 전체 팔레트 대비 규칙은 공통 테스트 포함 |
| 최종 플랫폼 게이트 | `./scripts/verify-platform-builds.sh` 종료 코드 **0**. `platform-gate-verified.log` / `platform-gate-verified.exit`. `git diff --check`, 공통 Debug/Release, iOS·macOS 및 iOS에 포함되는 Watch 앱/위젯의 Debug/Release 빌드, 번들 식별자·실행 파일·privacy manifest 검증 통과 |

사진·일반 회고·긴 이월 제목의 줄바꿈과 버튼 겹침을 직접 확인했다. 모바일의 좁은 화면 내부 탭은
상단에 고정했고 큰 글자에서는 메뉴로 전환한다. Mac은 기존 최대 콘텐츠 폭과 테마 토큰을 사용한다.

대표 화면:

- [iPhone 할 일 실시간 카드](../../../.local/carryover-review-discovery/screenshots/iphone-discovery-live-todo-initial.png)
- [iPhone 시작 후 카드](../../../.local/carryover-review-discovery/screenshots/iphone-discovery-live-started.png)
- [iPad 좁은 회고 화면](../../../.local/carryover-review-discovery/screenshots/ipad-discovery-review-narrow-dark.png)
- [iPhone 마지막 이월 처리 안내·가장 큰 글자](../../../.local/carryover-review-discovery/screenshots/iphone-carryover-last-item-feedback.png)
- [Mac 새 이월 작업](../../../.local/carryover-review-discovery/screenshots/mac-verified-inbox-dark.png)
- [Mac 넓은 회고 목록](../../../.local/carryover-review-discovery/screenshots/mac-review-wide.png)
- [Mac 2페이지에서 탭 왕복 후 위치](../../../.local/carryover-review-discovery/screenshots/mac-page2-restored.png)
- [Mac 수정 후 기존 날씨·기분 유지](../../../.local/carryover-review-discovery/screenshots/mac-final-saved-reader.png)

## 실제 장치 검증과 구분한 사항

- 실시간 카드 증거는 시뮬레이터의 실제 ActivityKit/알림 센터/Intent 실행이다. 실기기의 잠금 인증
  성공·취소, Always-On 저휘도, 개인정보 가림의 실제 렌더링, 8시간 실제 대기는 실행하지 않았다.
- 시간 경과·자정·수동 해제·원인 불명 사라짐·재실행 정책은 주입된 날짜와 로컬 수명 저장소 테스트로
  확인했다. 이를 실제 8시간 시스템 만료 관찰이나 수동 스와이프 해제 실기기 검증으로 기록하지 않는다.
- 실제 OS 설정에서 Live Activity 권한을 끈 UI 흐름은 실행하지 않았다. 권한 검사 분기는 코드로 확인했다.
- VoiceOver 실제 음성 탐색은 이번 환경에서 실행하지 않았다. 접근성 속성/조작 영역 검사와 구분한다.
- Hosted `PlanBaseMobileTests`는 테스트 시작 전에 멈춰 완료 결과를 얻지 못했다. 통과로 세지 않았다.
  위 payload 4항목은 동일 소스를 사용하는 별도 Simulator 실행으로 확인했다.
- `discovery-iphone-01/02/04/05/06`은 빌드 오류, 자동화 정체 또는 수정 전 실패/중단 기록이다.
  최종 통과 근거로 사용하지 않는다. iPad 01의 탭 탐색 실패는 앱의 iPad 상단 탭 구조에 맞춰 테스트를
  수정한 뒤 02에서 통과했다. 전체 게이트 첫 실행은 스크롤 수정을 진행하며 이전 공통 모듈과 새 호출부가
  섞여 실패했다. 두 번째 실행(`platform-gate-final.log`)은 Debug 485/Release 482 공통 테스트와
  Debug 플랫폼 빌드를 통과한 뒤 이월 처리 안내 수정 때문에 중단했다. 최종 실행 `platform-gate-verified.log`의 종료 코드 0으로 대체했다. 별도 경계 테스트의 첫 실행도 컴파일 중 테스트 파일 변경으로
  중단되었고 `boundary-tests-final.log`에서 다시 실행하여 통과했다.
- iPhone 10/11의 마지막 항목 테스트는 Xcode가 fixture 인수를 누락해 기본 예제 데이터가 열린 문제가
  있었다. 이중 실행으로 격리 fixture를 확실히 적용했다. 12/13에서 별도로 확인한 실제 앱 결함은
  마지막 항목 처리 후 안내가 목록 위로 밀리는 현상이었고, 14/15에서 수정 검증을 통과했다.
  11/12/13은 실패 후 결과 번들 마무리가 정체되어 프로세스를 종료했으며 로그만 실패 근거로 남긴다.
- `mac-page-restored.png`, `mac-scroll-fixed-*`, `mac-scroll-offset-*`는 수정 전 또는 중간 실패 증거다.
  최종 스크롤 검증 근거는 `mac-scroll-visible-before/after.png`, `mac-page2-before-switch/restored.png`다.
  수정한 제목을 fixture 표식으로 쓰던 시기의 `mac-final-board-dark.png`도 최종 집계 근거에서 제외한다.

## 시스템 동작의 한계

Live Activity는 앱의 실행·시스템 권한·수명 정책을 따른다. 하나의 활성 수명은 최대 8시간이며,
새 Activity 요청은 foreground나 지원 Intent 등 허용된 경로에서만 수행한다.
[Apple ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

`dismissed`는 사용자 또는 시스템 해제일 수 있어 정확한 원인을 알 수 없다. 관찰한 수명 만료는
허용된 시점에 복구하되, 원인 불명 사라짐은 당일 자동 재생성을 억제한다. 사용자의 명시적 시작/재개와
다음 날짜의 실행은 다시 평가한다. 무기한 백그라운드 유지나 앱을 실행하지 않은 상태의 즉시 원격 갱신을
약속하지 않는다. [Apple ActivityState.dismissed](https://developer.apple.com/documentation/activitykit/activitystate/dismissed).
