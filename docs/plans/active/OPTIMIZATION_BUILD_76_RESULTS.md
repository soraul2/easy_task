# PlanBase build 76 기준 최적화 결과

상태: **구현·로컬 검증 완료** (2026-09-08). iPhone 31개, iPad 22개 주요 시나리오와
Mac 직접 조작, Watch 40mm 시뮬레이터 조작을 확인했다. 마지막 템플릿 수정 후 두 모바일 기기에서
각 3개 관련 UI 검사를 다시 통과했고 전체 플랫폼 게이트도 종료 코드 0으로 완료했다.
실제 계정·기기 인수와 배포는 별도이며, 해당 체크리스트를 보존하기 위해 이 문서는 active에 둔다.

## 기준과 범위

2026-09-08 작업 시작 시 소스 전체가 TestFlight 1.0(76) 배포 소스 SHA-256 목록과 일치했다.
기존 미커밋 변경을 포함한 소스와 diff를 `.local/optimization-76/baseline/`에 보존했다.
이번 변경만 비교한 자료는 `results/goal-changes.patch`와 `results/goal-changed-files.json`이다.
배포, 커밋, push, 사용자 저장소와 실제 CloudKit 진단은 수행하지 않았다.

## 문제와 변경

| 우선순위 | 확인한 문제 | 변경 후 동작·근거 |
|---|---|---|
| P0 위험 | 메모의 필기/체크리스트 조회 실패를 빈 내용으로 취급해 후속 저장에서 기존 내용을 지울 수 있음 | 두 조회가 모두 성공한 뒤 편집 허용. 실패 주입 시 저장·고정·편집을 막고 재시도 후 원문/자식 항목 보존을 검증. 실제 사용자 데이터 손실을 관찰했다는 의미는 아님 |
| P1 | 저장 실패에도 Mac의 다른 메모 선택·탭 이동/iPhone 뒤로 가기로 초안을 버릴 수 있음 | 메모 선택·뒤로 가기는 저장 결과 확인 후 이동. Mac 탭 이동 시 실패한 세션을 상위 화면이 보관하며 복귀하면 같은 초안과 재시도 버튼 표시. 고정 동작도 저장 오류를 가리지 않고 재시도에 포함됨 |
| P1 | Mac에서 루틴을 만든 뒤 복제를 열면 이전의 빈 편집 상태가 재사용됨 | 편집 요청별 화면 identity를 지정. 복사할 이름·작업이 채워지고, 복사본 수정·적용 후 원본이 유지되는 것을 실제 Mac 화면과 iPhone/iPad 회귀 검사로 확인 |
| P1 위험 | Mac 필기를 화면 갱신마다 전체 영역의 두 배 해상도로 렌더링 | 최초 표시/필기 변경 때 생성한 미리보기 재사용. 긴 변 최대 1,800px, 최대 324만 픽셀. 원본 필기 보존 |
| P2 | 메모 저장에도 작업 알림·Live Activity·위젯·진행/기록 재조회 요청 | 실제 변경 영역으로 알림을 분류하고 관련 소비처만 갱신. 무변경 명령은 알림 생략. import와 기존 영역 정보 없는 알림은 전체 갱신 |
| P2 | 메모 목록 갱신 시 펼친 페이지 소실, 최신 검색어 무시, 실패 시 목록 비움 | 페이지 깊이·기존 행·재시도 위치 유지. 최신 요청 검색어 적용. 선택한 메모는 경로에서 유지 |
| P2 | 값이 같은 체크리스트도 SwiftData 변경으로 기록됨 | `inout` 대입 제거. 실제 다른 속성만 수정. 변경 없음 검사 실패를 재현한 뒤 통과 확인 |
| P2 | 긴 메모 제목·미리보기가 전체 텍스트를 반복 분할 | 필요한 줄만 읽음. 목록 미리보기는 최대 240자와 생략 표시. 전체 본문 검색·편집 유지 |
| P2 | 하루 기록에서 작업마다 조회 구간 30일을 전부 계산 | 실제 시작·닫힌 진행 구간이 있는 날짜만 집계. 자정, 23/25시간 날짜, 한국/미국/호주/UTC에서 기존 계산과 동일함을 확인 |
| P3 | Watch·아키텍처 문서에 이전 스키마/빌드 상태 표기 잔존 | 공통 모델 V11/build 76 최적화 기준과 검증 자료로 정정 |

P1/P2 재현 로그는 `baseline/memo-regressions.log`, `baseline/memo-checklist-writeback.log`에 있다.

## 성능과 사용성 비교

환경: Apple M1 Max, RAM 32GiB, macOS 26.6.2, Xcode 26.6. iPhone 17e/iOS 26.5 시뮬레이터,
Debug 빌드. 작업 3,000개(오늘 240개), 진행 이벤트 6,000개, 저장 작업 1,000개,
일정 180개, 메모 200개의 격리된 테스트 저장소를 사용했다. 측정 중 별도 빌드/테스트를 실행하지 않았다.

| 측정 | build 76 | 수정본 | 해석 |
|---|---:|---:|---|
| 공통 로직: 하루 기록 첫 30일 페이지, 준비 실행 제외 5회 중앙값 | 478.74ms | 377.97ms | 약 21% 감소 |
| 340,018바이트 메모 제목, 30회 중앙값 | 13.9066ms | 0.00146ms | 전체 줄 처리 제거. 같은 프로세스에서 보존한 원래 알고리즘과 짝 비교 |
| 같은 긴 메모 미리보기, 30회 중앙값 | 15.5782ms | 0.0681ms | 출력도 339,999바이트에서 587바이트로 제한. 전체 원문은 유지 |
| 공통 시작 무결성 검사, 3회 중앙값 | 1,913.17ms | 1,923.04ms | 개선 판단 없음 |
| 240개 보드 투영, 50회 중앙값 | 9.878ms | 10.111ms | 개선 판단 없음 |
| 1,000개 저장 작업 조회, 20회 중앙값 | 107.845ms | 109.211ms | 개선 판단 없음 |
| 준비된 저장소의 첫 반응 가능 프레임, 5회 평균 | 3.858초 | 3.776초 | 약 2.1% 차이로 큰 개선을 주장하지 않음 |
| 탭 4개 전환 전체 시간, 10회 평균 | 6.363초 | 6.641초 | 자동화 왕복·대기 포함. 전환 지연 개선을 주장하지 않음 |
| 위 전환의 앱 CPU 시간 | 2.247초 | 2.187초 | 약 2.7% 감소 |
| 위 전환의 앱 최대 물리 메모리 | 94.656MB | 93.658MB | 약 1.1% 감소 |

공통 로직 수치와 프레임 측정은 다르다. 탭 전환 전체 시간의 상대 표준편차는 기준 2.90%,
수정본 6.19%여서 작은 평균 차이를 앱 지연 변화로 단정하지 않는다. 첫 입력 후 픽셀 변화까지의
시간과 SwiftUI body 횟수는 직접 계측하지 않았으며 개선했다고 주장하지 않는다.
정상 작업의 탭 수는 유지하고, 저장 실패는 초안을 다시 작성하는 대신 재시도 한 번으로 복구한다.

조회 조건은 기존 날짜·ID 범위와 페이지 크기를 유지했다. 메모 저장 알림은 메모 영역으로만
전달되므로 작업/기록/일정 위젯 소비처의 재조회 요청은 생략된다. 이는 영역 전달 테스트와
소비처 필터의 근거이며 SwiftData 내부 SQL 총 횟수나 모든 SwiftUI 렌더링의 계측치는 아니다.
Mac 필기 픽셀 상한은 크기 계산 테스트의 근거이며 앱 전체 메모리 상한을 의미하지 않는다.

자료: `baseline/core-performance.log`, `results/performance-debug.log`,
`baseline/ui-performance.xcresult`, `results/ui-performance.xcresult`, 각각의 요약 JSON,
`results/measurement-environment.json`.

## 검증 상태

- 공통 Debug: 등록 444개 중 일반 테스트 440개 통과, 선택 성능 테스트 4개 제외.
  Release: 등록 442개 중 일반 테스트 439개 통과, 선택 성능 테스트 3개 제외.
  `results/full-platform-gate-template-final.log`의 실제 통과/제외 항목을 집계했다. Debug에만 포함되는 시작 계측과
  CloudKit 스키마 초기화 진입 조건 테스트가 등록 개수 차이다. 성능 비교는 앞 절의 별도 실행 로그로 검증한다.
- iPhone 17e/iOS 26.5: 주요 29개와 추가 일정 편집·템플릿 복제 2개, 총 31개 통과.
  `results/ui-iphone.xcresult`, `results/ui-iphone-supplement.xcresult`와 각 요약 JSON·첨부 자료에 보존했다.
- iPad A16/iOS 26.5: 핵심 22개 시나리오 확인. 최초 20개 통과, 새 메모 오류 주입 검사 2개는
  iPhone 하단 탭 막대만 찾는 테스트 탐색 문제로 실패했다. 기존 공통 탐색 helper를 적용한 뒤 두 검사 모두 통과했다.
  `results/ui-ipad.xcresult`의 최초 실패와 `results/ui-ipad-retry.xcresult`의 성공을 함께 보존했다.
  최초 결과 저장 시 정체된 선택 진단 수집 프로세스만 종료했으며 테스트 실행·결과 번들은 유지했다.
- 마지막 템플릿 편집 identity 수정 후 iPhone/iPad 각각 생성·편집·복제·적용·반복 선택 3개 검사를 다시 통과했다.
  `results/ui-iphone-template-final.xcresult`, `results/ui-ipad-template-final.xcresult`와 요약·첨부를 보존했다.
  위 31개/22개와 중복되는 검사이므로 고유 시나리오 수에 더하지 않는다.
- macOS 실제 앱: 테스트 전용 메모리 저장소에서 칸반 입력→중단·재개→완료→실행 취소→기록,
  일정 생성·수정·독립 복제, 템플릿 생성·복제·복사본 편집·적용, 메모 저장 실패/탭 이동/다른 메모 선택/재시도/체크리스트,
  집중 시작·일시정지·창 닫기·복원·재개·작업 완료, 완료 활동 그래프·회고 저장·다시 보기를 직접 검증했다.
  `results/native-ui-validation.md`와 `results/screens/mac-*.png`/`.txt`에 결과와 화면을 보존했다.
- 마지막 Mac 탭 이동 점검에서 실패한 편집 세션의 수명 문제를 추가 수정했다. 성공한 세션은 해제해
  다음 진입에서 최신 데이터를 읽고, 저장에 실패한 세션만 상위 화면이 보관한다. 해당 변경을 포함한 전체 게이트가 통과했다.
- `./scripts/verify-platform-builds.sh`: 종료 코드 0. iOS/macOS Debug·Release 및 각 내장 Watch/위젯의 실행 파일,
  식별자, 개인정보 manifest 검증 통과. Mac AppIcon의 기존 unassigned child 경고는 남아 있다.
- Watch: 독립 scheme의 Debug·Release 모두 종료 코드 0 (`results/watch-standalone-debug.log`,
  `results/watch-standalone-release.log`). 40mm 시뮬레이터 기본·xxxLarge 화면을 확인했다.
  큰 글자에서 빠른 입력→진행→집중 시작/일시정지→홈 이동/앱 복귀→재개/종료(32초 저장)→작업 완료→다시 진행→재완료를 직접 확인했다.
  당일 일정 제목/종료 D-2도 줄바꿈으로 표시됐다. 알림 권한을 거절한 상태의 타이머 흐름이며 알림·햅틱 성공을 뜻하지 않는다.
  `results/screens/watch-*.png`와 `results/native-ui-validation.md`에 증거를 보존했다.
- 게이트의 `git diff --check` 통과. 최종 파일 비교는 `results/diff-check.log`, `compatibility-comparison.json`에 보존한다.

## 데이터·동기화·백업 영향

기준 소스와 비교한 영속 스키마·호환 상수·백업·설정·공개 export 등 48개 파일이 동일하다.
기존 추적 파일 삭제도 없다. `results/compatibility-comparison.json`에 파일별 결과가 있다.
백업 package V10과 V1~V11 스키마를 유지했으며 마이그레이션이 필요하지 않다.

변경한 저장 경계는 기존 선행 저장·명령 저장·실패 rollback 순서를 유지한다.
작업 완료와 진행/완료 기록이 같은 명령에서 저장되고 실패 시 되돌아가는 것을 공통 테스트로 확인했다.
CloudKit 가져오기 완료 이벤트에 추가 무결성 변경이 없더라도 모든 조회 영역을 갱신한다.
이 이벤트 전달 경로는 메모리 저장소로 검증했고, 실제 CloudKit 서버나 사용자 저장소에는 접근하지 않았다.
`id`/`instanceID`, `supersededAt`, 중복 수렴 및 백업 병합 규칙은 변경하지 않았다.

## 접근성·화면 확인

iPhone 감사에서 칸반 9개, 캘린더 39개, 기록 4개, 메모 1개, 총 53개 후보 지적을 보존했다.
`results/ui-iphone-attachments/manifest.json`에서 `accessibility-findings-*`와 대응 화면을 찾을 수 있다.
수집 테스트가 통과했다는 것은 접근성 준수를 인증한다는 뜻이 아니다.

- 칸반의 작은 영역 2개는 `보통`, `예상 30분`의 정적 정보다. 실제 상태 변경·메뉴·집중 버튼과 구분했다.
  정적 텍스트를 불필요하게 큰 버튼으로 바꾸지 않았다.
- 날짜 셀 전체와 정적 텍스트에 대비 경고가 다수 붙었다. 원본 화면은 명암을 구분할 수 있고,
  공통 테마 테스트는 모든 팔레트의 본문/보조/상태·일정 전경 대비를 검증해 통과했다.
  이 근거만으로 OS가 합성한 모든 픽셀의 대비 경고를 오탐으로 확정하지 않으며 실기기 감사 후보로 남긴다.
- 큰 글자 기록·일정·메모·집중 화면에서 줄바꿈, 스크롤, 재시도·완료 조작을 확인했다.
  기록 검색창의 긴 안내 문구, 월 달력의 일정/휴일 축약 표시는 제한된 공간을 사용한다.
  날짜 상세와 접근성 이름에 전체 의미가 제공되는 기존 구조를 유지한다.
- 메모 저장 실패 화면에는 원문·오류·재시도 버튼이 함께 남고, 읽기 실패 화면은 편집기를 열지 않는 것을 확인했다.
  실기기 VoiceOver의 탐색 순서·발음·제스처는 별도 인수 항목이다.

## 유지한 설계와 미수정 이유

- P2 성능 후보: 템플릿 라이브러리는 열려 있는 동안 유효한 전체 루틴/항목을 관찰하는 기존 `@Query`를 유지한다.
  대규모 실제 라이브러리의 화면 병목은 이번에 계측하지 않았다. 전체 검색·개수·독립 복제/적용 의미를 보존하는 페이지 조회 설계가 필요하므로
  단순 fetchLimit을 붙여 일부 루틴을 숨기지 않았다. 새 전체 조회를 추가한 것은 아니다.
- P3: Mac 회고 저장 후 창에 남아 있는 닫기 동작의 문구가 `취소`인 점과 AppIcon의 기존 빌드 경고를 보존했다.
  저장 후 닫기·다시 보기는 성공했다. 저장 동작 변경과 무관한 문구/배포 에셋 정리는 후속 정리 항목이다.
- 시작 무결성 전체 점검은 중복/고아/레거시 데이터 보호를 위해 유지했다. 실행을 생략하거나 단순 캐시로 대체하지 않았다.
- V1~V11 영속 스키마, 모듈 정체성, 백업 V10, 배포 식별자와 target membership을 변경하지 않았다.
- 기록 상단 `완료 활동 · N일 연속`은 같은 요약의 제목이며 펼치면 1년 활동 달력을 보여 준다.
  아래 날짜 목록은 진행·집중·완료·회고를 함께 보는 상세 기록이다. build 76에 이미 있던 단일 요약/날짜 목록 구분을 유지했으며
  이번 변경으로 중복 완료 목록을 새로 분리하거나 접은 것은 아니다.
- 완료 이력은 현재 작업 상태와 구분한다. 완료 후 재개는 완료 사실을 보존하고 명시적인 실행 취소는 해당 전환을 되돌린다.
- Watch의 메모/회고/템플릿/백업 편집은 기존 지원 범위 밖이다. 활성 집중 타이머도 기기별 로컬 상태라는 의미를 유지한다.
- 전면 화면 재설계나 모델 마이그레이션은 이번에 재현한 문제 해결에 필요하지 않아 수행하지 않았다.
- 저장 실패 초안 보존은 실행 중인 창의 메모리에 한정된다. 저장 자체가 실패한 상태에서 앱을 강제 종료하거나
  창을 닫아도 복원되는 영구 초안 기능을 추가한 것은 아니다.

## 실제 기기 인수 항목

실제 CloudKit 계정·사용자 저장소에 접근하지 않았으므로 다음은 별도의 실제 기기 인수로 남긴다.

- iPhone·iPad·Mac·Watch의 오프라인 동시 편집, 연결 복원, 중복 수렴과 가져온 진행 기록의 화면 갱신.
- 기존 TestFlight 데이터의 필기·이미지·백업 왕복 및 배포 버전 간 호환.
- Watch 손목 내림/재실행/저휘도, 종료 알림과 햅틱, 네 종류 컴플리케이션 갤러리.
- 실기기 VoiceOver 제스처, Apple Pencil, Dynamic Island/잠금 화면/Always On, 전력·발열·메모리 압박.
- 사용자 상태를 바꾸는 앱 재설치와 iCloud 로그아웃/재로그인은 이번 범위에서 실행하지 않았다.

## 변경 파일·검증 자료 위치

저장소 루트 기준이다. 이번 Goal의 변경 파일 목록은 `goal-changed-files.json`에서 확인할 수 있으며 기존 미커밋 변경과 구분해 보존했다.

| 자료 | 위치 |
|---|---|
| 이번 변경만의 diff·파일별 해시 | `.local/optimization-76/results/goal-changes.patch`, `goal-changed-files.json` |
| 시작 소스·기존 사용자 diff | `.local/optimization-76/baseline/source.tar.gz`, `changes-at-start.patch` |
| 결과 집계·호환 비교 | `.local/optimization-76/results/validation-status.json`, `compatibility-comparison.json` |
| iPhone/iPad 시나리오·화면 | `.local/optimization-76/results/ui-*.xcresult`, `ui-*-summary.json`, `ui-*-attachments/manifest.json` |
| Mac/Watch 실제 조작 결과 | `.local/optimization-76/results/native-ui-validation.md`, `screens/` |
| 성능 전후 | `.local/optimization-76/baseline/core-performance.log`, `results/performance-debug.log`, 양쪽 `ui-performance.xcresult` |
| 플랫폼 게이트 | `.local/optimization-76/results/full-platform-gate-template-final.log`, `watch-standalone-debug.log`, `watch-standalone-release.log` |

핵심 구현은 `shared/Core/Services/MemoEditorSession.swift`, `MemoQuerySession.swift`,
`MemoRules.swift`, `MemoContentService.swift`, `PersistenceCommandService.swift`,
`DailyActivityRules.swift`, `DailyActivityQueryService.swift`에 있다.
플랫폼 연결은 `desktop/App/Features/Memo/MemoView.swift`, `desktop/App/AppRootView.swift`,
`mobile/App/Features/Memo/MobileMemoView.swift` 및 작업/기록/위젯 알림 소비처다.
템플릿 복제 수정은 `shared/Core/Components/TemplateLibraryView.swift`의 요청별 편집 화면 identity에 있다.
회귀 테스트는 `shared/Tests/MemoTests.swift`, `PersistenceChangeTests.swift`,
`DailyActivityTests.swift`, `OptimizationPerformanceTests.swift`, `mobile/Tests/PlanBaseLaunchUITests.swift`에 있다.

## 후속 TestFlight 배포

2026-09-08에 이 최적화 결과의 배포 build를 77로 올리고 iOS·iPadOS·watchOS와 macOS
아카이브를 생성했다. 여섯 개 앱·확장 번들의 버전 `1.0`·build `77`, 서명 및 공유 권한을
검증한 뒤 두 플랫폼 모두 App Store Connect 업로드를 완료했다. V11 스키마와 백업 V10에는
변경이 없다. 배포 archive와 로그는 `.local/releases/build-77/`에 보관한다.
