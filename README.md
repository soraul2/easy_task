# PlanBase

PlanBase는 iPhone, iPad, Apple Watch와 macOS에서 계획을 관리하는 개인 생산성 앱이다.
iOS universal 앱, watchOS 11 이상 독립 실행형 앱과 macOS 앱은 같은 SwiftData 모델과 private
CloudKit 컨테이너를 공유한다. watchOS 10은 iPhone 연동 모드로 같은 데이터를 사용한다.

현재 소스 기준은 앱 버전 `1.0`, 영속 스키마 `EasyTaskSchemaV11`, 위젯 스냅샷 v5,
백업 package V10이다. V11은 저장한 작업에 선택적인 빠른 입력어를 추가한다.
보드에서 `/`로 후보를 찾거나 `/운동`처럼 지정한 입력어로 작업을 바로 추가할 수 있다.
V10의 종료된 `FocusSession` 기록과 기기별 활성 타이머 snapshot은 유지한다.

CloudKit Production은 V11까지 배포됐다. 최신 업로드는
[iOS TestFlight 1.0 (92)](docs/releases/TESTFLIGHT_BUILD_92.md)이며, 2026-10-14 iOS·iPadOS·내장 watchOS의
업로드·처리 완료와 한국어 공지 저장을 확인했다. 잠금화면 실시간 할 일 카드의 화살표가
잠금 해제를 요구하던 설정을 수정했다. macOS 최신 배포는 [1.0 (91)](docs/releases/TESTFLIGHT_BUILD_91.md)이다.
**watchOS 10·SE 1세대용 iPhone 연동 모드**와
watchOS 11 이상 독립 동기화를 유지한다. 총 12개 테마의 출처와 배색 기준은
[앱 테마](docs/THEMES.md)에 정리했다.
build 92의 관련 공통·iOS 테스트 20개와 서명된 배포 패키지 검사가 통과했다. 전체 플랫폼 회귀는 이번에 재실행하지 않았다.
실제 암호로 잠긴 iPhone의 넘김, SE 1 실기기 설치·iPhone 왕복, TestFlight 설치와 기존 잠금 화면·Watch·Mac 인수의 미확인 항목은 유지한다.
최신 상태, 남은 확인, 기능별 계획과 과거 결과는 [문서 지도](docs/README.md)에 모았다.

## 시작하기

Swift 6 / Swift tools 6.3을 사용하며 현재 소스의 최소 지원은 iOS 18, macOS 26, watchOS 10이다.
watchOS 10은 iPhone 연동 모드이고, watchOS 11 이상은 기존 독립 실행 모드를 사용한다.
watchOS 10 호환 변경은 TestFlight build 90에 포함했다. 실제 SE 1 설치와 기기 간 왕복은 확인 대기다.
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
