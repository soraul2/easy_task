# PlanBase 프로젝트 구조

PlanBase는 macOS 앱, iPhone 앱, iPhone 위젯을 하나의 저장소에서 관리하며, 공통 모델과 서비스는 로컬 Swift Package로 공유한다.

## 디렉터리 구성

```text
PlanBase/
├── Package.swift                 # 공통 Swift Package 정의
├── PlanBase.xcodeproj/           # 앱·위젯·UI 테스트 타겟과 shared scheme
├── shared/
│   ├── Core/
│   │   ├── Models/               # 공통 값 타입과 모델 보조 코드
│   │   ├── Persistence/          # SwiftData 스키마·마이그레이션·컨테이너
│   │   ├── Services/             # 도메인 규칙·조회·저장·백업·동기화
│   │   ├── Components/           # 양 플랫폼 공용 SwiftUI 컴포넌트
│   │   └── Theme/                # 앱 테마와 색상
│   ├── PlanBaseCore/             # EasyTaskCore를 공개하는 re-export 계층
│   ├── Resources/                # 앱 에셋과 컨테이너 마이그레이션 설정
│   └── Tests/                    # 공통 단위·통합 테스트
├── desktop/
│   ├── App/                      # macOS 앱, 화면, 플랫폼 서비스
│   └── Configuration/            # macOS plist·entitlements·배포 설정
├── mobile/
│   ├── App/                      # iPhone 앱, 화면, 알림·위젯 연동
│   ├── Widget/                   # 캘린더·잠금 화면 WidgetKit 확장
│   ├── Tests/                    # iOS 기능·통합·실행 테스트
│   └── Configuration/            # iOS·위젯 plist·entitlements·배포 설정
├── docs/                         # 아키텍처·운영·기능 계획 문서
├── scripts/                      # 빌드·아카이브·CloudKit 검증 스크립트
└── .local/backups/               # Git 비추적 로컬 안전 백업
```

## 의존 방향

```text
shared/Core (EasyTaskCore)
        ↓
shared/PlanBaseCore (PlanBaseCore)
        ↓
desktop/App · mobile/App · mobile/Widget
```

`EasyTaskCore`는 배포된 SwiftData 모델의 모듈 호환성을 위해 이름을 유지하고, 앱 타겟은 공개 제품인 `PlanBaseCore`를 사용한다.

## 주요 진입점

| 경로 | 역할 |
|---|---|
| [`Package.swift`](Package.swift) | 공통 패키지 제품과 타겟 정의 |
| [`desktop/App/PlanBaseDesktopApp.swift`](desktop/App/PlanBaseDesktopApp.swift) | macOS 앱 시작점 |
| [`desktop/App/AppRootView.swift`](desktop/App/AppRootView.swift) | macOS 루트 화면 |
| [`mobile/App/PlanBaseMobileApp.swift`](mobile/App/PlanBaseMobileApp.swift) | iPhone 앱 시작점과 루트 구성 |
| [`mobile/Widget/PlanBaseWidgetBundle.swift`](mobile/Widget/PlanBaseWidgetBundle.swift) | 위젯 확장 시작점 |
| [`shared/PlanBaseCore/Exports.swift`](shared/PlanBaseCore/Exports.swift) | 공통 코어의 공개 API |
| [`shared/Core/Persistence/PlanBaseCompatibility.swift`](shared/Core/Persistence/PlanBaseCompatibility.swift) | 배포 호환 식별자 기준 |
| [`scripts/verify-platform-builds.sh`](scripts/verify-platform-builds.sh) | 패키지 테스트와 양 플랫폼 전체 빌드 검증 |

## 파일 추가 시 주의

- `shared/Core`와 `shared/Tests` 아래 Swift 파일은 SwiftPM이 자동으로 찾는다.
- `desktop/App`, `mobile/App`, `mobile/Widget`, `mobile/Tests`에 파일을 추가하면 `PlanBase.xcodeproj`의 대상 타겟 membership도 확인한다.
- 데이터 모델 변경은 기존 스키마를 수정하지 않고 새 `VersionedSchema`와 migration stage로 추가한다.
- `.local/backups/`는 안전 백업 영역이므로 임의로 정리하거나 덮어쓰지 않는다.

## 기본 검증

```bash
swift test
./scripts/verify-platform-builds.sh
```

세부 규칙은 [`AGENTS.md`](AGENTS.md), 실행 안내는 [`README.md`](README.md), 상세 구조는 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), CloudKit 운영은 [`docs/CLOUDKIT_SYNC.md`](docs/CLOUDKIT_SYNC.md)를 참고한다.
