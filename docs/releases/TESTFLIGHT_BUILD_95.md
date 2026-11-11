# TestFlight 1.0 (95) — 패키지 검증 완료, 업로드 인증 대기

2026-11-11 일정 추가·편집 화면 변경을 포함한 iOS·iPadOS·내장 watchOS와
macOS 배포 패키지를 준비했다. 구현·버전 커밋은
`5391aa7d81b731983904d8c526b8a6a76c607eca`이며
`origin/codex/kanban-card-design`에 푸시했다. 해당 커밋을
`.local/releases/build-95/source/`에 고정해 서명 아카이브를 만들었다.

## 포함한 변경

- Mac 일정 모달의 제목과 저장 영역을 고정하고 입력 본문을 스크롤하도록 정리했다.
  날짜·기간 카드, 기간 버튼과 직접 입력, 색상과 메모의 간격을 조정했다.
- iPhone·iPad의 날짜와 색상 선택은 창 너비와 접근성 글자 크기에 따라 배치된다.
  기간 버튼의 터치 영역과 선택 상태를 명확히 하고 메모 입력 영역을 넓혔다.
- 최근 일정 추천의 빈 상태와 닫기 표시를 간결하게 정리했다.
- 이전 준비 커밋의 CloudKit 가져오기 후 이미지 검증 결과 재사용을 포함한다.
  스키마·호환 식별자·저장 및 rollback 계약은 유지한다.

프로젝트 빌드 번호 14곳과 플랫폼 Info.plist 5개는 95, 마케팅 버전은 1.0이다.

## 검증

- 캘린더·추천 관련 공통 선택 테스트 21개 통과.
- iPhone Simulator의 회전·초안 보호·큰 글씨 추천·저장 실패 재시도 4개,
  iPad Simulator의 실제 두 앱 분할 창·회전·추천 및 독립 복제 3개 시나리오 통과.
  회전 검사는 폼 내부의 짧은 드래그로 보강한 뒤 두 기기에서 다시 통과했다.
- 실제 Mac의 격리 메모리 저장소에서 빈 제목 보호, 여러 줄 메모, 취소 후 계속 작성,
  직접 입력한 12일 기간, 색상 선택, 저장 후 편집으로 값 보존을 확인했다.
- `./scripts/verify-platform-builds.sh` 재시도 exit 0.
  공통 Debug 771개 통과·42개 skip, Release 766개 통과·10개 skip, 실패 0개다.
  iOS·macOS Debug/Release 빌드와 내장 Watch·위젯·privacy manifest 검사도 통과했다.
  첫 실행은 상속된 Command Line Tools SDKROOT와 Xcode compiler 불일치로 중단됐다.
  소스나 전역 도구 설정을 바꾸지 않고 실행 환경을 Xcode에 맞춰 재시도했다.
- iOS·macOS Release 서명 archive와 App Store Connect용 로컬 export 모두 exit 0.
- iOS 앱·위젯·Watch 앱·Watch 위젯 4개 및 Mac 앱·위젯 2개 번들의 버전,
  기존 식별자, App Group, strict 서명, privacy manifest와 Debug 권한 부재를 확인했다.
  앱의 CloudKit·APS는 Production이다.
- Watch arm64_32·arm64 및 macOS arm64·x86_64를 확인했다.
  배포 실행 파일 UUID는 archive와 일치하며 검사 대상 DEBUG fixture 심볼·마커 부재를 확인했다.
- 고정 소스·source.tar SHA와 커밋의 일치를 독립 검토로 재확인했다.

iPhone·iPad 검증은 iOS 26.5 시뮬레이터 기준이다. Mac의 더 짧거나 좁은 창은
별도로 검증하지 않았다. 실기기 CloudKit 원격 변경의 버벅임 전후 비교,
TestFlight 설치와 실제 VoiceOver·IME 인수는 완료한 것으로 표시하지 않는다.

## 업로드 상태

2026-11-11 iOS 13:25:59 KST, macOS 13:26:05 KST 업로드 시도가 모두
`error: exportArchive Failed to Use Accounts`, `EXPORT FAILED`, exit 70으로 종료됐다.
업로드 수락이나 Apple 처리 시작을 확인한 빌드는 아니다.
Xcode Settings → Accounts에서 배포 계정 상태 확인과 재인증이 필요하다.
인증 복구 후 위 검증된 archive로 업로드를 다시 실행한다.

한국어 테스트 안내는 `.local/releases/build-95/testflight-notes-ko.txt`에 초안으로
보관하며 App Store Connect 공지 저장이나 테스터 그룹 연결 완료로 표시하지 않는다.
소스·서명 archive·배포 패키지·검증 영수증·업로드 실패 로그는
`.local/releases/build-95/`, 화면 자료는 `.local/qa/event-editor-20261111/`에 보존한다.
