# TestFlight 1.0 (83)

2026-09-28 사용자의 TestFlight 업로드 요청에 따라 iOS·iPadOS·watchOS와 macOS를 업로드했다.

| 플랫폼 | 업로드 완료 (KST) | 근거 |
|---|---|---|
| iOS·iPadOS·watchOS | 2026-09-28 13:16:25.266 | `upload-ios.log`, 종료 코드 0, `Upload succeeded` |
| macOS | 2026-09-28 13:16:01.762 | `upload-macos.log`, 종료 코드 0, `Upload succeeded` |

두 플랫폼 모두 Apple 패키지 처리 시작까지 확인했다. TestFlight 설치 가능 상태나 외부 테스트 심사 완료를 확인한 것은 아니며, App Store 공개 출시는 수행하지 않았다.

## 포함한 변경

- 보드·캘린더의 반복 조회와 정렬을 줄이고, 숨겨진 탭·캘린더 상세의 갱신을 다음 활성화까지 미룬다. 메모 초안, 날짜·검색·스크롤·기록 페이지를 보관하는 화면 상태를 유지한다.
- 위젯의 화면 재계산별 비교 문자열 생성을 제거하고 저장·CloudKit 수신·테마·날짜 변경으로 갱신한다.
- 기록 통계의 무거운 조회·집계를 별도 ModelContext로 옮기고, 데이터가 그대로인 재진입에서 결과를 재사용한다.
- Focus 타이머를 화면 크기에 맞춰 조절하고 작은 영역·접근성 글꼴에서는 텍스트로 표시한다. 작업 체크리스트 표시와 체크 저장을 추가하고 매초 갱신을 타이머 부분으로 제한한다.

## 빌드·패키지 확인 범위

구현별 코드 위치와 남은 확인은 [탭 반응성·Focus 결과](../plans/active/TAB_RESPONSIVENESS_AND_FOCUS_2026_09_28_RESULTS.md)를 따른다.

- 구현 단계 iOS·macOS·watchOS Debug 빌드 통과. 이번 배포의 iOS(내장 Watch 포함)·macOS Release archive와 App Store Connect용 export도 종료 코드 0.
- 앱·위젯 6개 모두 1.0(83), 기존 bundle ID·App Group·CloudKit·key-value store 유지. 서명과 export의 Production 권한 확인. macOS는 Intel·Apple Silicon을 모두 포함한다.
- 컴파일 소스 iOS 213개·macOS 205개가 고정 사본과 작업 폴더에 일치한다. 배포 실행 파일 6개의 UUID가 archive와 일치하며 DEBUG fixture 심볼·검사 전용 문자열이 없다.
- 영속 스키마 V11·백업 package V10·호환 식별자·CloudKit 수렴 및 무결성 처리 규칙은 변경하지 않았다. CloudKit schema 추가 배포는 없다.
- **사용자 요청으로 테스트 작성·실행, UI 자동화, 벤치마크, 실기기 계측, 전체 회귀 스크립트를 생략했다.** 빌드·패키지 확인은 기능 또는 성능 실행 검증을 대신하지 않는다. 실제 탭 체감 속도, Focus 화면 배치·체크 동작, 기기 간 동기화와 TestFlight 설치는 미확인이다.

## 소스와 증거

배포 당시 기준 HEAD는 `392af1494f2d3da1dc8b94ab43e22eb19a2a8d6f`다. 여기에 이번 개선 파일과 빌드83 설정을 포함한 작업 폴더 사본을 `.local/releases/build-83/source/`에 고정해 archive를 생성했다. 업로드는 커밋 전에 완료했으며, 실제 배포한 앱 소스·빌드83 설정과 최초 배포 기록은 후속 커밋 `c6e3d1d7fbda812358de4ed630d541415f65c9e6`에 기록하고 `origin/codex/kanban-card-design`으로 push했다. 커밋 전 변경된 앱 소스·설정 24개의 해시가 배포 사본과 일치함을 확인했다.

Git에서 제외된 `.local/releases/build-83/`에 소스 418개의 해시, 변경 patch, archive, 배포 패키지, 서명·컴파일 소스·실행 파일 확인 결과, 업로드 로그와 `upload-results.json`, `release-status.json`을 보존했다. 테스트 안내 문구는 `testflight-notes-ko.txt`에 보관했으며 App Store Connect의 안내 필드에는 입력하지 않았다.
