# TestFlight 1.0 (81)

2026-09-22 iOS·iPadOS·watchOS와 macOS의 App Store Connect 업로드를 완료했다.

| 플랫폼 | 업로드 완료 (KST) | 근거 |
|---|---|---|
| iOS·iPadOS·watchOS | 2026-09-22 21:04:33.560 | `upload-ios.log`, 종료 코드0, `Upload succeeded` |
| macOS | 2026-09-22 21:04:35.826 | `upload-macos.log`, 종료 코드0, `Upload succeeded` |

두 플랫폼 모두 Apple 패키지 처리 시작을 확인했다. TestFlight 설치 가능 상태나 외부 테스트
심사 완료를 확인한 것은 아니다. 코드와 빌드81 설정은 `509754b`로
`codex/kanban-card-design` 브랜치에 커밋·푸시한 뒤 같은 archive를 업로드했다.
업로드 결과와 검증 자료는 `.local/releases/build-81/`에 보존한다.

## 변경 내용

- 루틴 목록과 회고 탐색의 반복 계산을 줄이고 불필요한 CloudKit 이벤트 재조회를 제거했다.
- 백업 병합의 부모 조회를 단계별로 공유해 대량 병합 비용을 줄였다.
- 지연된 위젯 갱신이 사용자가 새로 고른 테마를 되돌리는 문제를 수정했다.
- 큰 글자에서 동작 없는 안내가 뒤쪽 버튼의 터치를 막는 문제를 수정했다.
- iOS 앱의 Frameworks 실행 경로를 보완했다.

측정 조건·원본 표본·회귀와 남은 한계는
[전체 최적화 결과](../plans/active/OPTIMIZATION_2026_09_22_RESULTS.md)에 기록했다.
함수 실행 시간의 개선을 전체 화면 반응 속도 개선으로 확대하지 않는다.

## 검증

- 최종 기능 코드의 전체 플랫폼 게이트 종료 코드 0: 공통 Debug 489개 통과·선택 성능 8개 제외,
  Release 487개 통과·7개 제외. iOS/macOS Debug/Release, 내장 Watch·위젯·privacy manifest 통과.
- 관련 iOS 연동 19개, iPhone 13개·iPad 8개 고유 기능 시나리오의 최종 실행 통과.
  macOS 해당 흐름과 iPhone 홈 화면 위젯도 격리된 자료로 확인했다.
- 위 검증 소스335개와 비교해329개는 동일하며, 프로젝트와 Info.plist5개의 빌드 번호만
  80에서81로 바꿨다. 앱 기능 코드는 검증 후 변경하지 않았다.
- 앱·위젯6개 모두1.0(81), 기존 bundle ID·App Group·CloudKit·key-value store를 유지한다.
- 내보낸 IPA·macOS 패키지의 Production 권한·서명 검증 통과. macOS는 Intel·Apple Silicon을 포함한다.
- 실행 파일6개의 UUID가 archive와 일치하며, 배포 실행 파일에 DEBUG 전용
  `DiscoveryPreviewFixtures`·`MemoUITestSupport` 심볼이 없다. 컴파일 소스 iOS208개·macOS200개가
  고정 소스와 작업 트리에 일치한다.
- 배포 소스·archive·패키지·서명 검사·업로드 증거는 Git에서 제외된 `.local/releases/build-81/`에 보존한다.
- 첫 archive는 Info.plist의 별도 빌드80이 남아 패키지 검사에서 중단했다. 업로드하지 않았으며
  해당 산출물은 `initial-version-mismatch/`에 보존하고 번호를 맞춰 다시 생성했다.

스키마V11·백업package V10·bundle ID·App Group·CloudKit·최소 지원OS는 유지한다.
추가 CloudKit schema 배포는 없다. 실제 기기 간 CloudKit 왕복, 알림·장시간 Activity 인수와
최대 접근성 글자 크기의 기록 제목 일부 잘림은 별도 확인·개선 항목이다.
이번 요청은 TestFlight 업로드이며 App Store 공개 출시는 포함하지 않는다.
