# TestFlight 1.0 (93) — macOS 업로드 완료

2026-10-19 macOS 1.0(93)을 업로드했다. 구현·버전 준비 커밋은
`6a329a88aacdf8083f30aeedfe866bf22bd0332b`이며, 해당 커밋의 520개 파일을
`.local/releases/build-93/source/`에 고정했다. 이번 업로드 대상은 macOS 앱과
내장 위젯이며, iOS·iPadOS·내장 watchOS의 최신 업로드는 1.0(92)다.

## 포함한 변경

macOS 칸반 상단의 작업 입력 문자열·입력어 제안·포커스를 별도
`DesktopBoardQuickAdd` 뷰로 옮겼다. 일반 제목 입력이 부모 보드의 작업 정렬과
전체 카드 표시값 계산을 다시 실행시키던 경로를 분리했다.
Enter·추가 버튼·저장한 작업·입력어 선택, 저장 실패 시 초안 유지와
카드 삭제 후 값 스냅샷 보호는 유지한다. 스키마·CloudKit 수렴·백업 계약은 바꾸지 않았다.

기존 관례에 따라 프로젝트의 빌드 번호 14곳과 플랫폼 Info.plist 5개를 93으로
맞췄으며, 마케팅 버전은 1.0이다.

## 검증

- 입력어·보드 관련 선택 테스트 23개 및 macOS Debug·Release 빌드 통과.
- 빌드 번호 변경 후 `./scripts/verify-platform-builds.sh` exit 0.
  공통 Debug·Release 테스트, iOS·내장 Watch·macOS Debug·Release 빌드와
  내장 번들·privacy manifest 검증을 포함한다. 선택 성능·진단 검사는 기본 정책에 따라 제외했다.
- 고정 소스 520개와 커밋의 일치를 독립 검토로 확인했다.
- 서명된 macOS Release archive와 App Store 배포 패키지 export 모두 exit 0.
- 앱·위젯 두 번들의 1.0(93), 기존 식별자, arm64·x86_64, strict 서명,
  Production CloudKit·APS, App Group, privacy manifest와 Debug 권한 부재 확인.
- 배포 실행 파일 UUID가 archive와 일치하고 DEBUG fixture 심볼이 없음을 확인했다.
  패키지 SHA와 Apple Installer 서명도 독립 검토로 재확인했다.

수정 전 로컬 합성 데이터에서 입력 중 보드 계산 반복을 관찰했다. 수정본의 실제
키보드·한글 IME 비교는 테스트 창 포커스 문제로 완료하지 못했으므로,
위 빌드·파일 검증을 체감 개선율이나 모든 멈춤 해결의 근거로 사용하지 않는다.
동기화 후 무결성 검사의 별도 지연 가능성과 실제 TestFlight 설치 확인도 남아 있다.

## 업로드 상태

2026-10-19 11:55:46 KST에 `Upload succeeded.`,
`Uploaded package is processing.`, `EXPORT SUCCEEDED` 및 exit 0을 확인했다.
Apple의 패키지 처리가 시작됐으며 처리 완료·내부 그룹 연결·기기 설치는 별도로
확인하지 않았다. 수락된 패키지는 재업로드하지 않는다.

한국어 테스트 안내 초안은 `.local/releases/build-93/testflight-notes-ko.txt`에
준비했으며 App Store Connect 입력 완료로 표시하지 않는다. 소스·전체 게이트 로그·
배포 파일·검증 결과·업로드 영수증은 `.local/releases/build-93/`에 보존한다.
