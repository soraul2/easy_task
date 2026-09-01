# PlanBase

PlanBase는 iPhone, iPad와 macOS에서 칸반, 캘린더, 기록, 메모를 관리하는 개인 생산성
앱이다. iOS universal 앱과 macOS 앱은 같은 SwiftData 모델과 CloudKit 컨테이너를 공유한다.

현재 배포 기준은 앱 버전 `1.0`(build 60), 영속 스키마 `EasyTaskSchemaV8`,
위젯 스냅샷 v5, 백업 package V7이다. iOS와 macOS TestFlight용 build 60은
서명·공유 권한 검증 후 App Store Connect에 업로드됐다.

## 시작하기

Xcode에서 `PlanBase.xcodeproj`를 열고 목적에 맞는 scheme을 선택한다.

- `PlanBase-iOS`: iPhone·iPad universal 앱과 캘린더·플래너·잠금 화면 위젯, Live Activity
- `PlanBase-macOS`: macOS 데스크톱 앱과 네이티브 캘린더·플래너 위젯
- `PlanBaseCore`: 공통 모델과 서비스의 공개 패키지 제품

## 구조

```text
mobile/      iPhone·iPad 앱, 멀티플랫폼 위젯 소스, 설정, UI 테스트
desktop/     macOS 앱과 설정
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

문서 전체 분류는 [문서 지도](docs/README.md), 자세한 구조와 데이터 규칙은
[아키텍처 문서](docs/ARCHITECTURE.md), CloudKit 운영 절차는
[동기화 문서](docs/CLOUDKIT_SYNC.md)를 참고한다.
