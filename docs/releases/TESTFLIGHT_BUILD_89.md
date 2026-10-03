# TestFlight 1.0 (89) — 업로드 완료

2026-10-03 새 테마 네 개를 포함하는 빌드를 업로드했다. 마케팅 버전은 1.0,
앱·위젯·Watch 빌드 번호는 89다. 시작 HEAD는 `6042620`이며,
492개 저장소 파일을 `.local/releases/build-89/source/`에 고정해 검증·컴파일했다.
소스는 `350ffbb9307bcbb84afb92e83d8a9a843fb99977`로
`origin/codex/kanban-card-design`에 commit·push했다.

## 업로드 상태

| 플랫폼 | 업로드 완료 시각(KST) | Delivery ID |
|---|---|---|
| iOS·iPadOS·watchOS | 2026-10-03 22:05:05 | `6f0b5920-4c14-4e6e-bc08-60b2a17714ed` |
| macOS | 2026-10-03 22:04:48 | `2c098ac9-4da6-44b2-b615-fd619f74f000` |

두 플랫폼 모두 `Upload succeeded.`·`Uploaded package is processing.`·`EXPORT SUCCEEDED`
및 exit0를 확인했다. 기존 Automatic signing 설정으로 archive·export·upload가 모두
첫 시도에 성공했다. 설치 가능 상태·테스터 그룹 공개·외부 테스트 심사는 확인하지 않았다.
영수증은 `upload-results.json`, `release-status.json`에 보존하며 이미 수락된 빌드를 재업로드하지 않는다.

## 포함한 변경

- 라이트 테마: Olive Linen(올리브·린넨 베이지), Burgundy Ivory(버건디·아이보리).
- 다크 테마: Forest Gold(짙은 숲색·골드), Cocoa Copper(코코아 브라운·코퍼).
- 전체 라이트 8개·다크 4개. 기존 테마와 선택값, 일정 분류색을 유지한다.
- 앱·테마 미리보기·위젯은 공통 팔레트를 사용한다.

출처·인기 순위·색상 조정과 검증은 [앱 테마](../THEMES.md)를 따른다.
SwiftData V11, CloudKit V11 Production, App Group, 백업 V10, 위젯 snapshot v5는 변경하지 않는다.

## 검증·배포 상태

- 기능 구현 시 공통 테스트 26개, iPhone 전체 12개 테마 UI 검사 1개, iOS·macOS Debug 빌드 통과.
- build 89 전체 플랫폼 회귀가 840.456초·exit0로 완료됐다. 공통 Debug 693통과·36skip,
  Release 688통과·10skip, 실패 0. iOS/macOS Debug·Release와 내장 Watch·위젯·privacy manifest를 확인했다.
- iOS와 macOS Release archive·App Store 배포 패키지 생성 완료. 총 6개 번들의
  1.0(89), strict 서명, device 플랫폼, privacy manifest, Production CloudKit/APS,
  App Group, 실행 파일 UUID와 DEBUG 진단 코드 부재를 확인했다. 전체 entitlements는
  정상 업로드된 build 88과 일치하며 Mac 패키지의 Apple 설치 서명도 확인했다.
- 실제 컴파일된 iOS 219개·macOS 211개 Swift 파일과 빌드 입력 415개가 고정 소스 및
  작업 폴더와 일치한다. Mac 앱·위젯은 Apple Silicon과 Intel을 포함한다.
- iOS·iPadOS·watchOS와 macOS 업로드 성공·Apple 패키지 처리 시작을 확인했다.

## 테마 업데이트 공지 검토

Apple은 [TestFlight 테스트 정보](https://developer.apple.com/testflight/)에 변경 내용과
테스트할 내용을 적는 방식을 제공한다. 외부 테스터는 빌드 승인 후
[자동 또는 수동 알림](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)
대상이 될 수 있다. 실제 전달은 배포 그룹·승인·테스터 설정에 영향을 받는다.

이번 요청은 공지 가능 여부 확인이므로 아래 문구를 초안으로 준비했다. App Store Connect
입력이나 `Notify Testers` 실행, 별도 이메일·푸시 발송을 완료했다는 뜻은 아니다.
현재 앱 소스에는 업데이트 공지 전용 화면·버전별 노출 기록이 없으며, 앱 안에서
한 번 보여 주는 새 테마 안내는 별도 구현할 수 있다.
Xcode 업로드 인증은 정상 동작했지만 App Store Connect 웹에서는 별도 로그인 화면을 확인했다.

### 한국어 ‘테스트할 내용’ 초안

새 테마 4종이 추가되었습니다!

- 라이트: Olive Linen(올리브·린넨 베이지), Burgundy Ivory(버건디·아이보리)
- 다크: Forest Gold(짙은 숲색·골드), Cocoa Copper(코코아 브라운·코퍼)

앱의 팔레트 아이콘에서 새 테마를 선택해 보세요. 총 12개 테마를 사용할 수 있습니다.
테마 변경 후 칸반·캘린더·기록·메모의 글자 가독성과 위젯 색상 반영을 확인해 주세요.

로컬 배포 근거와 초안은 `.local/releases/build-89/`에 보존한다.
