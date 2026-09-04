# PlanBase

PlanBase는 iPhone, iPad, Apple Watch와 macOS에서 계획을 관리하는 개인 생산성 앱이다.
iOS universal 앱, 독립 실행형 watchOS 앱과 macOS 앱은 같은 SwiftData 모델과 private
CloudKit 컨테이너를 공유한다.

현재 소스 기준은 앱 버전 `1.0`, 영속 스키마 `EasyTaskSchemaV11`, 위젯 스냅샷 v5,
백업 package V10이다. V11은 저장한 작업에 선택적인 빠른 입력어를 추가한다.
보드에서 `/`로 후보를 찾거나 `/운동`처럼 지정한 입력어로 작업을 바로 추가할 수 있다.
V10의 종료된 `FocusSession` 기록과 기기별 활성 타이머 snapshot은 유지한다.

CloudKit Production은 V11까지 배포됐다. 입력어의 Development 독립 저장소 왕복 8단계와
Production 필드·인덱스 반영을 확인했다. 마지막 업로드본은 빠른 입력어를 포함한
iOS·iPadOS·watchOS 및 macOS TestFlight build 69(V11)이다. 2026-09-04 두 플랫폼의
App Store Connect 업로드 성공과 패키지 처리 시작을 확인했다. 설치 가능 상태와
빠른 입력어·FocusSession의 실기기 쌍 인수는 별도로 확인한다.

## 시작하기

Xcode에서 `PlanBase.xcodeproj`를 열고 목적에 맞는 scheme을 선택한다.

- `PlanBase-iOS`: iPhone·iPad universal 앱과 캘린더·플래너·잠금 화면 위젯, Live Activity
- `PlanBase-macOS`: macOS 데스크톱 앱과 네이티브 캘린더·플래너 위젯
- `PlanBase-watchOS`: 오늘 작업·일정, 빠른 추가·상태 변경, 독립 Focus와 Watch 컴플리케이션
- `PlanBaseCore`: 공통 모델과 서비스의 공개 패키지 제품

## 구조

```text
mobile/      iPhone·iPad 앱, 멀티플랫폼 위젯 소스, 설정, UI 테스트
desktop/     macOS 앱과 설정
watch/       독립 실행형 watchOS 앱, 컴플리케이션 확장과 설정
shared/      공통 코어, 위젯 발행 지원, 리소스, 단위 테스트
docs/        운영 문서와 진행 중·완료된 설계 기록
scripts/     빌드 및 CloudKit 검증 도구
.local/      Git에 포함되지 않는 로컬 백업
```

## 검증

```bash
swift test
./scripts/verify-platform-builds.sh
```

전체 플랫폼 검증과 iOS archive에는 현재 Xcode SDK와 일치하는 watchOS Simulator
runtime이 필요하다. Xcode의 Settings > Components에서 설치한다.

문서 전체 분류는 [문서 지도](docs/README.md), 자세한 구조와 데이터 규칙은
[아키텍처 문서](docs/ARCHITECTURE.md), CloudKit 운영 절차는
[동기화 문서](docs/CLOUDKIT_SYNC.md), Watch 기능과 출시 절차는
[watchOS 운영 문서](docs/WATCHOS.md)를 참고한다.
