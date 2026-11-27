# TestFlight 1.0 (96) — iOS·macOS 업로드 완료

2026-11-27 메모 기능과 UI 변경을 commit·push하고 iOS·iPadOS·내장 watchOS 및 macOS 배포 패키지를 업로드했다. 첫 시도의 필수 계약 오류를 해결한 후 같은 서명 archive로 재시도해 두 플랫폼의 Apple 패키지 수락·처리 시작을 확인했다.

구현·버전 커밋은 `f231ee881c6a61e2ec14bb4c763bdc9c659e6a80`이며 `origin/codex/kanban-card-design`에 푸시했다. 이 커밋을 `.local/releases/build-96/source/`에 고정해 빌드했다.

## 포함한 변경

- 새 메모는 글 메모와 체크리스트만 만든다. 그림 작성·편집·지우기는 제거하고 이전 필기는 읽기 전용으로 보존한다.
- 빈 목록의 직접 생성, 유형·고정·선택 표시, 검색 복구, 체크리스트 진행률·항목 관리·입력 포커스와 큰 글자 배치를 개선한다.
- iPad의 체크 항목 추가·분할 화면 전환에서 편집 본문이 사라지는 현상을 보완한다.
- 기존 그림을 교체하지 않는 저장 경로와 화면 전용 빈 체크 항목의 갱신 후 보존을 적용한다.
- V11 스키마, CloudKit 식별자, 백업 형식과 기존 데이터 호환은 유지한다.

프로젝트 빌드 번호 14곳과 플랫폼 Info.plist 5개를 96으로 통일하고 마케팅 버전은 1.0을 유지한다.

## 검증

- `./scripts/verify-platform-builds.sh`: exit 0. 실행 시각 2026-11-27 15:35:09~15:50:17 KST, 시작·종료 커밋 모두 `f231ee8`.
- 공통 Debug는 777개 통과·42개 skip(총 819개), Release는 772개 통과·10개 skip(총 782개). 매개변수 case와 skipped suite를 별도 테스트로 중복 집계하지 않았다.
- iOS Simulator·macOS 로컬 Debug/Release 빌드와 내장 Watch 앱·위젯·privacy manifest 검사 통과.
- 메모 관련 선택 테스트 Debug 36개·Release 35개 통과. 최종 iPhone 저장·체크 완료·정렬·고정·검색·삭제·재실행과 iPad 입력·열 전환·이전 필기 재열기 확인.
- iOS·macOS Release 서명 archive 및 App Store Connect용 로컬 export 모두 exit 0.
- iOS 앱·위젯·Watch 앱·Watch 위젯 4개와 Mac 앱·위젯 2개의 버전, 식별자, App Group, strict 서명, privacy manifest 확인. 앱과 Watch의 CloudKit·APS는 Production이며 배포 패키지에 Debug 권한이 없다.
- Watch arm64_32·arm64, macOS arm64·x86_64 확인. archive와 Production export의 실행 파일 UUID가 일치한다. Mac 설치 패키지 서명도 확인했다.
- 고정 소스 525개 파일 SHA와 tar 내용이 commit에 일치함을 독립 검토했다. source.tar SHA-256은 `5efb11347adb62add49ef779bc2beddfe361edae376f5052c9cc380eb4cb1079`다.
- macOS는 빌드와 코드 검토까지 확인했으며 실제 창 수동 조작은 수행하지 않았다. 실제 사용자 저장소·운영 CloudKit 데이터에는 접근하지 않았다.

상세 변경과 UI 검증 경계는 [메모 정리 기록](../plans/completed/MEMO_TEXT_CHECKLIST_SIMPLIFICATION.md)을 따른다.

## 업로드 결과

동일한 검증 archive를 `xcodebuild -exportArchive`, `destination=upload`, 자동 서명으로 업로드했다. 첫 시도는 iOS 15:51:14 KST, macOS 15:51:18 KST에 각각 exit 70으로 종료됐다.

두 플랫폼 오류는 `You do not have required contracts to perform an operation.`이다. 인증서·archive·Production package 검증은 통과했으며, 이 오류를 패키지 수락이나 TestFlight 처리 시작으로 간주하지 않는다.

로그인 후 [Apple Developer 계정](https://developer.apple.com/account/)과 App Store Connect에서 업데이트된 Program License Agreement 미동의 안내를 확인했다. 실제 계약 화면의 문서 날짜는 2026-10-29다. 해당 계약의 최종 동의에 대해 사용자에게 명시적 확인을 받은 후 동의했고, 양 서비스의 계약 차단 안내가 사라진 것을 확인했다. 관련 권한은 [Apple 계정 역할 안내](https://developer.apple.com/help/account/access/roles/)를 따른다.

재시도 전 고정 소스 525개·tar·commit provenance, Production 6번들 검증 영수증과 IPA·PKG SHA를 독립 재확인했다. 재빌드나 버전 변경 없이 `run-export.py <ios|macos> upload 02`로 같은 archive를 업로드했다.

2026-11-27 iOS 16:05:33 KST, macOS 16:05:13 KST에 각각 `Upload succeeded.`, `Uploaded package is processing.`, `EXPORT SUCCEEDED`와 exit 0을 확인했다. TestFlight의 두 플랫폼 빌드 업로드 목록에서도 `1.0 (96)`의 **처리 중** 상태를 확인했다. 수락된 패키지는 다시 업로드하지 않는다.

iOS 업로드에는 사용한 iOS 26.5 SDK에 대한 향후 요구사항 경고가 있었다. Apple 로그는 2027년 4월부터 업로드·배포 제출에 iOS 27 SDK/Xcode 27 이상이 필요하다고 안내한다. 이번 업로드는 경고와 함께 성공했다.

소스·archive·배포 패키지·SHA/권한 검증 영수증, 계약 동의 확인 기록, 첫 시도 실패 로그와 재시도 성공 명령·상태·로그는 `.local/releases/build-96/`에 보존한다. 현재 요약은 `release-status.json`, 성공 근거는 `upload-ios-02.log`·`upload-macos-02.log`와 각 `*-status.json`이다.

Apple 처리 완료·테스터 그룹 연결·실기기 설치는 확인하지 않았다. 그룹 설정을 변경하거나 한국어 테스트 안내를 서버에 저장하지 않았으며, 테스트 안내 초안은 `testflight-notes-ko.txt`에 보관한다.
