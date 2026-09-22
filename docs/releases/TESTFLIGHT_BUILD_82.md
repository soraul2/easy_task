# TestFlight 1.0 (82)

2026-09-23 사용자의 커밋·푸시·TestFlight 업로드 요청에 따라 iOS·iPadOS·watchOS와 macOS 업로드를 완료했다.

| 플랫폼 | 업로드 완료 (KST) | 근거 |
|---|---|---|
| iOS·iPadOS·watchOS | 2026-09-23 01:37:48.039 | `upload-ios.log`, 종료 코드 0, `Upload succeeded` |
| macOS | 2026-09-23 01:37:33.703 | `upload-macos.log`, 종료 코드 0, `Upload succeeded` |

두 플랫폼 모두 Apple 패키지 처리 시작을 확인했다. TestFlight 설치 가능 상태나 외부 테스트 심사 완료를 확인한 것은 아니다. App Store 공개 출시도 수행하지 않았다.

앱 코드와 빌드82 설정은 `2462a3d`로 `codex/kanban-card-design`에 커밋·푸시한 뒤, 해당 커밋에서 추출한 고정 소스로 archive를 생성하고 업로드했다. 원본 자료는 Git에서 제외된 `.local/releases/build-82/`에 보존한다.

## 변경 내용

- 긴 단일 날짜 일정 제목을 여유 공간에 최대 두 줄로 표시한다. 기존 표시 일정 수와 여러 날짜 일정의 한 줄 배치를 보존한다.
- 큰 글자의 두 자리 날짜, 숨겨진 일정 개수와 막대 겹침, 낮은 가로 화면의 마지막 주 접근을 개선한다.
- 기록·회고의 큰 글자 제목과 검색·회전 흐름, 긴 목록의 요약과 전체 읽기를 개선한다.
- 네 탭 이름, 메모 빈 화면과 검색 초기화, 완료·저장 안내, 템플릿 용어와 공유 항목 안내를 보완한다.
- Mac 체크리스트에 키보드·접근성 순서 변경과 포커스 복구를 추가하고 캘린더 하단 탭 겹침을 수정한다.

상세 구현·검증은 [UI·UX 결과](../plans/active/UI_UX_2026_09_22_RESULTS.md)와 [캘린더 두 줄 제목 결과](../plans/active/CALENDAR_SINGLE_DAY_TITLE_2026_09_23_RESULTS.md)에 기록했다.

## 검증과 범위

- 기능 변경의 전체 플랫폼 게이트 통과: 공통 Debug 501개·Release 498개, iOS·macOS·watchOS Debug/Release와 내장 번들 검사. 게이트 중 추가 수정된 UI 파일은 최종 iOS/Mac Debug·Release 및 관련 UI 검사로 보완했다. 게이트 실행 시점과 최종 소스 차이는 원본 결과 문서에 명시한다.
- 최종 iPhone 일반/xxxLarge/AX5 세로·가로, 전체 제목 상세와 AX5 마지막 날짜 스크롤·열기, 실제 585×820 iPad 창의 두 줄 제목과 숨겨진 6번째 일정 열기 통과. 기존 일정 편집·재열기 회귀도 통과했다.
- 배포 준비 전 기능 검증 해시와 모두 일치했다. 이후 프로젝트와 Info.plist 5개의 빌드 번호만 81→82로 변경했다. 앱 기능 코드는 추가 수정하지 않았다.
- 서명된 iOS/Mac archive와 App Store Connect용 export 모두 종료 코드 0. 앱·위젯 6개 모두 1.0(82), 기존 bundle ID·App Group·CloudKit·key-value store 유지, export의 Production 권한과 서명 검증 통과. Mac은 Intel·Apple Silicon을 포함한다.
- 컴파일 소스 iOS 209개·Mac 201개가 고정 커밋과 작업 트리에 일치한다. 배포 실행 파일 6개의 UUID가 archive와 같으며 DEBUG fixture 심볼과 이번 UI 검사 전용 문자열이 없다.
- 스키마 V11·백업 package V10·최소 지원 OS·저장 및 동기화 규칙은 변경하지 않았다. CloudKit schema 추가 배포는 없다.
- **남은 확인:** 최종 캘린더 두 줄 표시의 Mac 실제 화면 검사는 호스트 잠금 때문에 보류 중이다. 해당 후속 검증 중 테스트 인수 누락 실행과 확인되지 않은 일반 로컬 저장소 영향도 캘린더 결과 문서에 기록했다. 실제 TestFlight 설치, VoiceOver 발화, Pencil·Watch 햅틱 및 기기 간 CloudKit 왕복은 이번 업로드 성공으로 통과 처리하지 않는다.

`release-status.json`, `feature-verification-link.json`, `compiled-source-verification.json`, `verification-*-production.json`, `distribution-code-verification.json`, `release-symbol-check.json`, `upload-results.json`과 각 로그를 함께 보존한다.
