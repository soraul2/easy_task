# TestFlight 1.0 (91) — 업로드 완료

2026-10-13 iOS·iPadOS·watchOS와 macOS의 1.0(91)을 업로드했다. 현재 작업 폴더의 변경을 포함한 518개 파일을 `.local/releases/build-91/source/`에 고정했다. 커밋·push는 수행하지 않았다.

## 포함한 변경

- 앱 시작과 보드 갱신에서 불필요한 조회를 줄였다.
- 입력어 제안을 재사용하고 제출 직전에 최신 내용을 확인하도록 보완했다.
- 작업 삭제 직후 카드 표시 안정성을 개선했다.
- 앱 준비 중 받은 캘린더 링크를 보관하고 준비 후 처리하도록 개선했다.

## 최소 검증

사용자 요청에 따라 반복 성능 계측과 추가 실기기 UI 검사를 보류했다. 기존 fullgate003 실행 당시 비 Markdown 439개 파일이 현재 shipping 파일과 SHA 및 membership 일치함을 Root와 독립 에이전트가 확인해 PASS를 재사용했다. 이후 변경은 배포 번호90→91의 6파일뿐이다.

iOS·Watch 및 macOS Release archive와 local App Store 배포 패키지 export가 모두 exit0으로 완료했다. 최종6번들의1.0(91), 기존 bundle ID, privacy manifest, strict서명, device 플랫폼, Production CloudKit/APS 및 App Group을 확인했다. Watch 앱·위젯 최소OS10.0과 arm64_32·arm64, Mac의 arm64·x86_64를 확인했다. 배포 실행 파일 UUID6개는 archive와 일치하고 DEBUG fixture 표식은 부재했다.

기존 진단의 iPhone test005는 Save 이전 스크롤·discard alert로 중단돼 저장 실패 복구를 검증하지 못했다. 실제 입력→표시100ms, 남은 Mac 성능 개선, 실제 OS cold URL 및 추가 실기기 복구 검증의 미확인 상태를 유지한다. 이 배포의 해결 주장이나 공지에 해당 수치·진단 전용 변경을 포함하지 않는다.

## 업로드 상태

| 플랫폼 | 업로드 완료(KST) | 결과 |
|---|---|---|
| iOS·iPadOS·watchOS | 2026-10-13 20:04:51 | Upload succeeded / EXPORT SUCCEEDED / exit0 |
| macOS | 2026-10-13 20:04:53 | Upload succeeded / EXPORT SUCCEEDED / exit0 |

두 플랫폼 빌드91의 처리가 완료됐으며 기존 내부 ‘지인’ 그룹(2명)에 연결된 것을 확인했다. 한국어 테스트 내용을 각각 입력하고 ‘저장 완료’ 및 입력 문구 일치를 확인했다. 실제 기기의 TestFlight 설치는 별도 확인이다. 이미 수락된 패키지를 재업로드하지 않는다. 배포 원시 로그·서명 검증·고정 소스는 `.local/releases/build-91/`에 보존한다.

## 한국어 테스트 내용

앱 시작과 보드 갱신에서 불필요한 조회를 줄였습니다. 입력어 제안을 재사용하고, 제출 직전 최신 내용을 확인하도록 보완했습니다. 작업 삭제 직후 카드 표시 안정성과 앱 준비 중 받은 캘린더 링크 처리도 개선했습니다.


테스트할 내용
• 앱을 종료한 뒤 다시 열어 로딩 화면과 보드가 정상적으로 이어지는지 확인해 주세요.
• 작업 생성·상태 변경·삭제 후 보드, 이월함, 진행 시간이 정확히 갱신되는지 확인해 주세요.
• /입력어 제안과 작업 생성, 저장한 작업 변경 후 제안 반영을 확인해 주세요.
• 위젯의 캘린더 링크로 종료 상태의 앱을 열어 요청한 날짜가 표시되는지 확인해 주세요.
• 편집 중 앱을 잠시 백그라운드로 보냈다가 돌아왔을 때 초안이 유지되는지 확인해 주세요.

공지 저장 화면: `.local/releases/build-91/testflight-ios-notice-saved.jpg`, `testflight-macos-notice-saved.jpg`. ASC 확인 영수증은 `app-store-connect-ui-completion.json`이다.
