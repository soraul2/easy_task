# TestFlight 1.0 (97) — iOS·macOS 업로드 완료

2026-11-27 일정 추가·편집 화면의 최근 일정 추천 최적화를 commit·push하고 iOS·iPadOS·내장 watchOS와 macOS 배포 패키지를 업로드했다. 첫 시도의 Xcode 인증 오류를 로그인 후 해결하고 같은 archive로 재시도해 Apple의 패키지 수락·처리 시작을 확인했다. 마케팅 버전은 1.0을 유지하고 프로젝트 빌드 번호 14곳과 플랫폼 Info.plist 5개를 97로 맞췄다.

## 포함한 변경

- 편집 세션에서 최근 수정된 활성 일정 최대 200개의 값 snapshot과 정규화한 제목을 재사용한다. 같은 정규화 검색어·제외 ID의 진행 중 요청과 결과를 재사용하고 최대 5개를 표시한다.
- 일정 저장·삭제, 성공한 CloudKit import, 날짜·시간대 변경과 실패 재시도 시 후보를 갱신한다. 닫힘·적용 상태와 되돌리기 기록을 유지하고 늦은 조회가 새 cache를 덮어쓰지 못하게 한다.
- 갱신 중 이전 카드의 배치를 유지하되 클릭·키보드·접근성 적용 대상에서 제외한다.
- 정확·접두어·포함 순위, 논리 대표·설정 중복 제거, 작성한 메모 보호와 되돌리기 동작은 유지한다.
- V11 스키마, CloudKit 식별자, 백업 형식과 기존 데이터 호환은 바꾸지 않는다. build 96의 글 메모·체크리스트 정리와 이전 필기 보존을 포함한다.

## 구현 검증

버전 번호 변경 전 전체 게이트는 2026-11-27 16:49:07~17:03:19 KST에 exit 0이었다. Debug 787통과·42skip(총 829개), Release 782통과·10skip(총 792개), iOS·macOS Debug/Release 빌드와 내장 Watch·위젯·privacy manifest 검사를 통과했다. 배포 준비 전 제품·공통 테스트 SHA가 그 검증 기록과 일치함을 독립 확인했다.

- 추천 관련 선택 테스트 24개 통과.
- iPhone 17e / iOS 26.5에서 메모 보호·되돌리기·포함 검색·저장/재개방, 실패 재시도, 편집·복제 추천 적용 3개 통과.
- iPad A16 / iOS 26.5에서 최대 접근성 글자 크기 재사용과 편집·복제 추천 적용 2개 통과.
- 가짜 일정만 사용하는 Mac 공통 뷰에서 펼친 메모를 포함한 갱신 전후 크기 600×503pt 유지, 로딩 중 후보·전문보기 AX 버튼 0개를 확인했다. 실제 Mac 편집기 전체 흐름이나 iOS 전환 프레임 측정은 아니다.
- 로컬 Mac Release 합성 측정에서 230ms 간격 5회 입력과 같은 정규화 검색 5회 입력의 조회가 각각 5회에서 1회로 줄었다. 비용 측정은 30회 반복이고 조회 횟수 패턴은 각각 1회다. 저장된 일정 수와 무관하게 실제 추천 pool은 최대 200개다.

실기기·운영 CloudKit·실제 IME·입력 지연·프레임·메모리 개선 수치는 확인하지 않았다. UI와 측정 증거는 `.local/calendar-recommendation-analysis-20261127/`에 보존한다.

## 배포 상태

구현·버전 커밋은 `39661cc72c334439df53f5f7d1b6011437e2343f`이며 `origin/codex/kanban-card-design`에 푸시했다. 이 커밋의 526개 파일을 `.local/releases/build-97/source/`에 고정했다. manifest·tar·git archive와 commit 일치를 독립 확인했으며 source.tar SHA-256은 `74e273fdc1187c3c7a328ffdc4c28c5c2a1a22d1b3761bef72419553c918c879`다.

iOS archive는 20:14:08 KST, macOS archive는 20:12:22 KST에 exit 0으로 완료됐다. App Store Connect용 로컬 export도 iOS 20:15:01·macOS 20:13:25 KST에 exit 0이었다.

- iOS 앱·위젯·Watch 앱·Watch 위젯 4개와 Mac 앱·위젯 2개의 버전 1.0(97), 기존 식별자, App Group, strict 서명과 privacy manifest를 확인했다.
- Production 6개 번들은 배포 Team이 일치하고 Debug 권한이 없다. 앱과 Watch의 CloudKit·APS는 Production이며 KVS 식별자도 유지한다.
- Watch arm64_32·arm64와 최소 watchOS 10, Mac arm64·x86_64를 확인했다. archive와 Production export의 실행 파일 UUID가 일치하고 Mac 설치 패키지도 배포 서명이 유효하다.
- 실제 archive 6개·Production 6개 번들과 영수증, 패키지 SHA, 고정 source를 독립 재검토해 불일치가 없었다.

build 97 고정 commit의 전체 게이트도 20:09:03~20:22:53 KST에 exit 0으로 완료됐다. Debug 787통과·42skip(총 829개), Release 782통과·10skip(총 792개), iOS·macOS Debug/Release 빌드와 내장 Watch·위젯·privacy manifest 검사를 통과했으며 종료 시 526개 manifest가 동일했다.

첫 업로드는 iOS·macOS 모두 20:23:39 KST에 exit 70으로 종료됐다. Xcode 로그는 `Failed to Use Accounts`와 `missing Xcode-Username`를 보고했다. 사용자가 Xcode에 로그인한 후 고정 소스·tar·commit, archive·Production 실행 파일 SHA와 IPA·PKG SHA를 재확인했다. 재빌드나 버전 변경 없이 같은 archive로 재시도했다.

재시도는 iOS 20:34:44 KST, macOS 20:34:37 KST에 각각 `Upload succeeded.`, `Uploaded package is processing.`, `EXPORT SUCCEEDED`와 exit 0으로 완료됐다. TestFlight의 두 플랫폼 빌드 업로드 목록에서도 `1.0 (97)`의 **처리 중** 상태를 확인했다. 수락된 패키지는 다시 업로드하지 않는다.

iOS 업로드에는 iOS 26.5 SDK에 대한 향후 요구사항 경고가 있었다. Apple 로그는 2027년 4월부터 업로드·배포 제출에 iOS 27 SDK/Xcode 27 이상이 필요하다고 안내하며, 이번 업로드는 경고와 함께 성공했다.

서명 archive·패키지·검증 영수증·SHA·첫 시도 실패와 재시도 성공 명령·상태·로그는 `.local/releases/build-97/`에 보존한다. 현재 상태는 `release-status.json`, 성공 근거는 `upload-ios-02.log`·`upload-macos-02.log`와 각 `*-status.json`에 기록했다.

Apple 처리 완료·실기기 설치는 아직 확인하지 않았다. 한국어 테스트 안내는 로컬 초안으로 보관하며 기존 테스터 그룹 설정과 공지는 변경하지 않았다.
