# TestFlight 1.0 (79)

2026-09-16 iOS·iPadOS·watchOS와 macOS의 App Store Connect 업로드를 완료했다.

| 플랫폼 | 업로드 완료 (KST) | 근거 |
|---|---|---|
| iOS·iPadOS·watchOS | 2026-09-16 22:48:33 | `upload-ios.log`, 종료 코드 0, `Upload succeeded` |
| macOS | 2026-09-16 22:47:47 | Xcode Organizer 완료 화면, `macos-upload.xcdistributionlogs/ContentDelivery.log`의 `UPLOAD SUCCEEDED with no errors` |

두 플랫폼 모두 Apple 패키지 처리 시작을 확인했다. 이 기록은 TestFlight 설치 가능
상태나 외부 테스트 심사 완료를 뜻하지 않는다. 원본 archive·서명 검증·화면·로그는
Git에서 제외된 `.local/releases/build-79/`에 보존한다.

## 변경 내용

- 메모 생성 시 글 메모·체크리스트·필기·그림 유형을 선택하고, 기존 복합 메모는 모든 내용을 유지한다.
- 메모 목록에 유형·체크리스트 진행 상태·필기 미리보기를 표시한다. 다른 기기에서 가져온 내용과 중복 수렴 뒤 편집 내용 보존을 보완했다.
- iPhone 회전과 iPad 창 크기 변경 시 칸반·캘린더·기록·메모·집중 화면의 적응형 배치와 편집 상태 유지를 개선했다.
- macOS의 작은 필기 미리보기와 빈 초안의 저장 상태 표시를 보완했다.

## 검증

- 고정 소스 snapshot으로 전체 회귀 스크립트를 실행해 종료 코드 0을 확인했다.
- Debug 453개·Release 451개 검사 통과. 기본 설정에서 제외되는 선택 성능 검사는 각각 5개·4개이며, 실패는 없다. 로그의 총 458개·455개에는 이 제외 항목이 포함된다.
- iOS·macOS Debug/Release와 내장 Watch·위젯·privacy manifest 검증 통과.
- 앱·위젯 6개 모두 버전 1.0 (79), 기존 bundle ID·App Group·CloudKit·key-value store 유지.
- 실제 iOS IPA와 macOS 업로드 패키지의 Production 권한·배포 서명 검증 통과. macOS는 Intel·Apple Silicon을 모두 포함한다.
- 컴파일 소스 iOS 198개·macOS 190개가 snapshot 및 작업 트리와 일치한다. 배포 패키지 6개의 실행 파일 UUID도 검증한 archive와 일치한다.
- 배포 실행 파일에서 DEBUG 전용 `MemoUITestSupport` 심볼이 제외됨을 확인했다.
- [메모 유형 검증](../plans/completed/MEMO_TYPE_CREATION_PLAN.md)의 macOS 미리보기·지우기·다른 내용 보존·다크 테마·재실행 검증 완료.

영속 스키마 V11·백업 V10·최소 지원 OS를 유지하며 추가 CloudKit schema 배포는 없다.

## 별도 확인 사항

- [적응형 인터페이스 기록](../plans/active/IPHONE_DUO_INTERFACE_PLAN.md)의 Duo 전용 환경 및 실기기 검증은 남아 있다. 이번 업로드가 Duo 전용 검증 완료를 의미하지 않는다.
- 이전 메모 검증 도구가 일반 Debug 앱을 의도치 않게 실행한 사건의 실제 CloudKit 데이터 영향은 미확인이다. 이번 배포로 해당 불확실성이 해소됐다고 주장하지 않는다.
- 이 빌드는 테스트 배포이며 App Store 공개 출시는 수행하지 않았다.
