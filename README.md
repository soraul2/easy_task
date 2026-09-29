# PlanBase

PlanBase는 iPhone, iPad, Apple Watch와 macOS에서 계획을 관리하는 개인 생산성 앱이다.
iOS universal 앱, 독립 실행형 watchOS 앱과 macOS 앱은 같은 SwiftData 모델과 private
CloudKit 컨테이너를 공유한다.

현재 소스 기준은 앱 버전 `1.0`, 영속 스키마 `EasyTaskSchemaV11`, 위젯 스냅샷 v5,
백업 package V10이다. V11은 저장한 작업에 선택적인 빠른 입력어를 추가한다.
보드에서 `/`로 후보를 찾거나 `/운동`처럼 지정한 입력어로 작업을 바로 추가할 수 있다.
V10의 종료된 `FocusSession` 기록과 기기별 활성 타이머 snapshot은 유지한다.

CloudKit Production은 V11까지 배포됐다. 최신 업로드는
[TestFlight 1.0 (84)](docs/releases/TESTFLIGHT_BUILD_84.md)이며, 2026-09-29 iOS·iPadOS·watchOS와
macOS의 업로드 성공·Apple 패키지 처리 시작을 확인했다. 캘린더 최근 일정 추천의 제목 입력,
메모 보호·되돌리기와 검색·조작 개선을 포함한다. 공통 테스트·플랫폼 회귀와 격리 UI 검증을
수행했으며, TestFlight 설치 가능 상태와 실기기 동작은 미확인이다.
최신 상태, 남은 확인, 기능별 계획과 과거 결과는 [문서 지도](docs/README.md)에 모았다.

## 시작하기

Swift 6 / Swift tools 6.3을 사용하며 최소 지원은 iOS 18, macOS 26, watchOS 11이다.
Xcode에서 `PlanBase.xcodeproj`를 열고 목적에 맞는 scheme을 선택한다.

- `PlanBase-iOS`: iPhone·iPad universal 앱과 캘린더·플래너·잠금 화면 위젯, Live Activity
- `PlanBase-macOS`: macOS 데스크톱 앱과 네이티브 캘린더·플래너 위젯
- `PlanBase-watchOS`: 오늘 작업·일정, 빠른 추가·상태 변경, 독립 Focus와 Watch 컴플리케이션

공통 모델과 서비스는 로컬 Swift Package의 `PlanBaseCore` 제품으로 공유한다.

## 구조

```text
mobile/      iPhone·iPad 앱, 멀티플랫폼 위젯 소스, 설정, UI 테스트
desktop/     macOS 앱과 설정
watch/       독립 실행형 watchOS 앱, 컴플리케이션 확장과 설정
shared/      공통 코어, 위젯 발행 지원, 리소스, 단위 테스트
docs/        운영 문서와 진행 중·완료된 설계 기록
scripts/     빌드 및 CloudKit 검증 도구
.local/      Git에 포함되지 않는 백업·진단·배포 증거
```

## 검증

```bash
swift test
./scripts/verify-platform-builds.sh
```

전체 플랫폼 검증과 iOS archive에는 현재 Xcode SDK와 일치하는 watchOS Simulator
runtime이 필요하다. Xcode의 Settings > Components에서 설치한다.

위 명령은 개발용 검증 안내다. 빌드별 실제 실행 여부와 결과는 배포 기록을 따른다.
`.local/backups/`는 안전 백업 영역이므로 명시적인 요청 없이 정리하거나 덮어쓰지 않는다.

문서 전체 분류는 [문서 지도](docs/README.md), 자세한 구조와 데이터 규칙은
[아키텍처 문서](docs/ARCHITECTURE.md), CloudKit 운영 절차는
[동기화 문서](docs/CLOUDKIT_SYNC.md), Watch 기능과 출시 절차는
[watchOS 운영 문서](docs/WATCHOS.md)를 참고한다.
