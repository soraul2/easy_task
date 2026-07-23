# PlanBase

PlanBase는 iPhone과 macOS에서 칸반, 캘린더, 기록, 메모를 관리하는 개인 생산성 앱이다. 두 앱은 같은 SwiftData 모델과 CloudKit 컨테이너를 공유한다.

## 시작하기

Xcode에서 `PlanBase.xcodeproj`를 열고 목적에 맞는 scheme을 선택한다.

- `PlanBase-iOS`: iPhone 앱과 캘린더 위젯
- `PlanBase-macOS`: macOS 데스크톱 앱
- `PlanBaseCore`: 공통 모델과 서비스의 공개 패키지 제품

## 구조

```text
mobile/      iPhone 앱, 위젯, 설정, UI 테스트
desktop/     macOS 앱과 설정
shared/      공통 코어, 리소스, 단위 테스트
docs/        운영 문서, 구조 정리 체크리스트, 완료된 설계 기록
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
