# TestFlight 1.0 (84)

2026-09-29 사용자의 TestFlight 업로드·커밋·푸시 요청에 따라 iOS·iPadOS·watchOS와 macOS를 업로드했다.

| 플랫폼 | 업로드 완료 (KST) | 근거 |
|---|---|---|
| iOS·iPadOS·watchOS | 2026-09-29 13:54:20.688 | `upload-ios.log`, 종료 코드 0, `Upload succeeded` |
| macOS | 2026-09-29 13:53:52.850 | `upload-macos.log`, 종료 코드 0, `Upload succeeded` |

두 플랫폼 모두 Apple 패키지 처리 시작까지 확인했다. TestFlight 설치 가능 상태·외부 테스트
심사 완료는 확인하지 않았으며, App Store 공개 출시는 수행하지 않았다.

## 포함한 변경

- 캘린더 추천을 선택하면 후보의 전체 제목·기간·실제 표시 색상을 입력하고 현재 시작일을 유지한다.
- 기존 메모를 보호하고 명시적인 추천 메모 교체와 적용 전 초안으로 되돌리기를 제공한다.
  수동 편집 이후에는 후속 동작을 종료하여 작성 중인 내용을 덮어쓰지 않는다.
- 최근 일정의 정확·접두어·2글자 이상 포함 검색을 지원한다. 같은 표시 색상의 중복을 정리하고,
  메모만 다른 후보는 미리보기·전문 펼침으로 구분한다.
- 오래된 비동기 결과를 차단하고 조회 실패·재시도를 구분한다. 모바일 조작 영역·큰 글자 표시와
  Mac 스크롤·키보드 선택·접근성 정보를 개선한다.
- 기존 문서 정리를 보존하고 현재 운영 기준, 과거 배포 이력과 기능별 검증 기록을 연결했다.

최종 동작·재현 전후·화면 증거·남은 검증은
[캘린더 추천 사용성 구현 결과](../plans/active/CALENDAR_RECOMMENDATION_USABILITY_REVIEW_2026_09_29.md#9-승인된-개선안-구현-결과-2026-09-29)를 따른다.

## 빌드·검증 범위

- 공통 패키지 Debug 511개·Release 507개, 관련 추천 테스트 14개와
  `./scripts/verify-platform-builds.sh` 통과. DST 지역에서도 관련 14개 테스트 통과.
- 메모리 저장소의 iPhone UI 7개·iPad UI 5개 합격 사례와 Mac 직접 조작을 확인했다.
  여러 실행에서 통과한 서로 다른 사례 수이며 실패·중단 실행을 통과로 합산하지 않았다.
- 기능 검증 이후 앱 코드는 변경하지 않았다. 배포에서는 프로젝트 설정 14개와 Info.plist 5개의
  빌드 번호만 84로 올렸다. 초기 archive에서 plist의 이전 번호를 발견해 수정·재생성했으며,
  잘못된 번호의 초기 archive는 업로드하지 않았다.
- iOS(내장 Watch 포함)·macOS Release archive와 App Store Connect용 export 모두 종료 코드 0.
  앱·위젯 6개 모두 1.0(84), 기존 bundle ID·App Group·CloudKit·key-value store를 유지한다.
  archive 서명 및 배포 패키지의 Production 권한을 확인했고 Mac은 Intel·Apple Silicon을 포함한다.
- iOS 214개·macOS 206개 컴파일 소스가 배포 사본 및 작업 폴더와 일치한다.
  배포 실행 파일 6개의 UUID가 archive와 같으며 DEBUG fixture 심볼과 추천 실패 주입 인자가 없다.
- 영속 스키마 V11·백업 package V10·호환 식별자·CloudKit 수렴 및 무결성 규칙은 변경하지 않았다.
  실제 사용자 저장소·CloudKit을 사용하는 검증과 별도 CloudKit schema 배포는 수행하지 않았다.

한글 조합·한자 선택, VoiceOver 음성/로터, iPhone 최대 글자 크기에서 키보드를 연 상태의 모든
보조 동작과 일부 창 크기 조합은 미확인이다. 기존 탭 반응성·Focus의 실기기 인수 및
TestFlight 설치·기기 간 CloudKit 왕복도 이번 업로드 성공으로 통과 처리하지 않는다.

## 소스와 증거

배포 시작 HEAD는 `c6e3d1d7fbda812358de4ed630d541415f65c9e6`다. 현재 캘린더 개선과 빌드84 설정을
포함한 작업 폴더를 `.local/releases/build-84/source/`에 고정해 archive를 생성했다.
업로드는 커밋 전에 완료했으며, 배포한 앱 소스·설정과 이 기록을 같은 후속 커밋에 포함한다.
업로드 완료 후 갱신한 문서는 앱 바이너리에 영향을 주지 않는다.

Git에서 제외된 `.local/releases/build-84/`에 소스 424개의 해시, 변경 patch, archive,
배포 패키지, 버전·서명·컴파일 소스·실행 파일 검증, 업로드 로그와 결과 JSON을 보존한다.
기능 검증 산출물은 `.local/calendar-recommendation-2026-09-29/`와
`feature-verification-link.json`으로 연결한다. 커밋·푸시 후 정확한 SHA는 로컬
`release-status.json`에 기록한다. 테스트 안내 문구는 `testflight-notes-ko.txt`에 보관했으며
App Store Connect의 안내 필드에는 입력하지 않았다.
