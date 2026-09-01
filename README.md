# PlanBase

PlanBase는 iPhone, iPad, Apple Watch와 macOS에서 계획을 관리하는 개인 생산성 앱이다.
iOS universal 앱, 독립 실행형 watchOS 앱과 macOS 앱은 같은 SwiftData 모델과 private
CloudKit 컨테이너를 공유한다.

현재 소스 기준은 앱 버전 `1.0`, 영속 스키마 `EasyTaskSchemaV9`, 위젯 스냅샷 v5,
백업 package V8이다. V9는 메모의 텍스트·필기·체크리스트 콘텐츠를 추가하며 CloudKit
Development 초기화와 Production 배포를 완료했다. 마지막 업로드본은 V9/백업 V8을 포함한
iOS·iPadOS·watchOS 및 macOS TestFlight build 62다.

## 시작하기

Xcode에서 `PlanBase.xcodeproj`를 열고 목적에 맞는 scheme을 선택한다.

- `PlanBase-iOS`: iPhone·iPad universal 앱과 캘린더·플래너·잠금 화면 위젯, Live Activity
- `PlanBase-macOS`: macOS 데스크톱 앱과 네이티브 캘린더·플래너 위젯
- `PlanBase-watchOS`: 오늘 작업·일정, 빠른 추가·상태 변경과 Watch 컴플리케이션
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
