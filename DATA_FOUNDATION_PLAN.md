# EasyTask Data Foundation Plan

## 목표

macOS와 iPhone 앱을 CloudKit으로 연결하기 전에 데이터 스키마, 무결성,
이미지, 백업, 빌드 타겟을 안정화한다. UI 기능 추가보다 데이터 손실과
기기별 불일치를 막는 것을 우선한다.

## 현재 기준점

- 기준 브랜치: `main`
- 통합 브랜치: `feature/data-foundation`
- 기준 태그: `v1.0.0-local-mvp`
- 기준 커밋: `7e6c92a`
- 검증 결과: 공통 테스트 31개 통과, iOS Simulator Debug 빌드 통과
- 현재 저장 방식: 기기별 로컬 SwiftData

`v1.0.0-local-mvp`는 데이터 기반 작업 중 문제가 생겼을 때 돌아갈 수 있는
복구 지점이다.

## 핵심 원칙

1. CloudKit은 마지막에 활성화한다. 먼저 로컬 저장소에서 마이그레이션과
   무결성 규칙을 검증한다.
2. `main`에는 빌드와 테스트를 통과한 병합 커밋만 둔다.
3. 모든 데이터 변경은 `EasyTaskCore` 서비스 계층을 통해 실행한다.
4. CloudKit은 고유 제약을 보장하지 않으므로 `@Attribute(.unique)`에
   의존하지 않고 결정론적인 중복 정리 규칙을 사용한다.
5. 이미지 파일명, UUID 외래 키, 날짜 캐시처럼 중복된 저장 값은 하나의
   원본과 명확한 파생 규칙을 갖게 한다.
6. 동기화 저장소에서는 전체 삭제 후 복원을 허용하지 않는다.
7. 각 작업 브랜치는 하나의 책임만 가지며, 서로 같은 파일을 동시에
   수정하지 않는다.

## 완료 조건

- 두 앱이 같은 버전 스키마와 컨테이너 팩토리를 사용한다.
- 기존 로컬 저장소가 새 버전으로 데이터 손실 없이 열린다.
- 같은 날짜 회고, 논리 UUID, 템플릿 시드가 중복되어도 같은 결과로
  수렴한다.
- 작업 삭제 후 템플릿 배치, 이벤트, 회고 첨부에 고아 참조가 남지 않는다.
- 이미지가 백업, 복원, 재설치, 다른 기기에서 정상 표시된다.
- 잘못된 백업은 현재 저장소를 전혀 변경하지 않는다.
- iPhone과 macOS에서 오프라인 편집 후 재연결해도 데이터가 수렴한다.

## 단계별 실행 계획

### Phase 0. 기준점 고정

상태: 완료

- 모바일 보관함 변경을 `feature/mobile-archive-parity`에서 독립 커밋했다.
- 공통 테스트와 iOS 빌드를 확인한 뒤 `main`에 `--no-ff`로 병합했다.
- 원격 `main`과 기능 브랜치를 푸시했다.
- `v1.0.0-local-mvp` 태그를 원격에 생성했다.

### Phase 1. 즉시 데이터 안전 조치

브랜치: `fix/data-foundation-safety`

- 운영 빌드에서 샘플 작업, 회고, 템플릿 자동 생성을 중단한다.
- 샘플 데이터는 Preview, UI 테스트, 명시적인 데모 모드에서만 생성한다.
- 백업에서 읽은 파일명은 UUID 기반 내부 이름으로 변환하고 경로 이동,
  절대 경로, 허용하지 않은 확장자를 거부한다.
- 현재 replace-all 복원은 전체 사전 검증, 명시적 저장, 실패 시 롤백이
  준비될 때까지 실험 기능으로 제한한다.
- 완료 태그: `v1.0.1-data-safety`

검증:

- Release 실행은 빈 저장소에 샘플 데이터를 만들지 않는다.
- `../`, 절대 경로, 과도한 파일 크기, 중복 ID가 포함된 백업을 거부한다.
- 실패한 복원 전후의 저장소 체크섬과 레코드 수가 같다.

### Phase 2. 프로젝트 타겟과 공통 모듈 정리

브랜치: `chore/platform-targets`

- SwiftPM은 `EasyTaskCore`와 공통 테스트를 담당한다.
- Xcode는 iOS와 macOS 앱 번들 타겟을 담당하고 로컬 `EasyTaskCore`
  패키지 제품에 의존한다.
- Xcode 타겟에서 공통 소스 파일을 직접 중복 컴파일하지 않는다.
- iOS/macOS 공유 scheme과 반복 실행 가능한 build smoke 검증을 커밋한다.
- `EasyTaskCore`에는 AppKit, UIKit, PhotosUI 의존성을 허용하지 않는다.

이 단계는 이후 공통 파일 추가가 Package와 Xcode에서 어긋나는 문제를
먼저 제거한다.

### Phase 3. V1 스키마 동결과 컨테이너 통합

브랜치: `feature/schema-v1`

- 현재 7개 모델을 그대로 표현하는 `EasyTaskSchemaV1`을 만든다.
- `EasyTaskMigrationPlan`과 `EasyTaskContainerFactory`를 추가한다.
- 양쪽 앱 진입점은 같은 팩토리로 컨테이너를 생성한다.
- 이 단계에서는 CloudKit을 명시적으로 비활성화한다.
- 파일 기반 기존 저장소를 열고 재실행하는 마이그레이션 테스트를 추가한다.

예정 파일:

- `Sources/EasyTaskCore/Persistence/EasyTaskSchemaV1.swift`
- `Sources/EasyTaskCore/Persistence/EasyTaskMigrationPlan.swift`
- `Sources/EasyTaskCore/Persistence/EasyTaskContainerFactory.swift`
- `Tests/TodoDesktopMVPTests/SchemaMigrationTests.swift`

### Phase 4. V2 무결성 모델과 정리 규칙

브랜치: `feature/schema-v2-integrity`

- 논리 ID와 물리 레코드 ID를 구분하고 생성/수정 시각을 표준화한다.
- `DailyReview.dayKey`와 기본 템플릿 `seedKey`를 자연 키로 사용한다.
- CloudKit 중복은 가장 작은 인스턴스 ID를 대표로 선택하고,
  `(updatedAt, instanceID)`가 큰 값을 최신 값으로 판단한다.
- 중복 레코드는 즉시 삭제하지 않고 연결을 대표 레코드로 옮긴 뒤
  `supersededAt`으로 표시한다.
- UUID 외래 키는 검증 가능한 서비스 또는 CloudKit 호환 optional inverse
  relationship으로 단계적으로 이전한다.
- `TemplatePlacement.taskIds`처럼 양방향으로 중복 저장된 값은 원본을 하나로
  줄인다.
- 잘못된 상태, 우선순위, 색상, 날짜 키를 복구하는 무결성 서비스를 추가한다.

예정 파일:

- `Sources/EasyTaskCore/Persistence/EasyTaskSchemaV2.swift`
- `Sources/EasyTaskCore/Services/DataIntegrityService.swift`
- `Tests/TodoDesktopMVPTests/DataIntegrityTests.swift`

주의: CloudKit 호환성을 위해 새로운 relationship은 optional, 명시적 inverse,
지원되는 delete rule로 구성하며 ordered relationship은 사용하지 않는다.

### Phase 5. 이미지와 백업 V2

브랜치: `feature/media-backup-v2`

- 회고 이미지의 원본을 `DiaryAttachment` 모델로 통합한다.
- 첨부에는 ID, 회고 ID, 순서, MIME type, 크기, 해시, 생성/수정 시각과
  external storage 데이터가 들어간다.
- 저장 전에 실제 PNG, JPEG, HEIC 형식을 판별하고 크기 제한과 리사이즈
  정책을 적용한다.
- 기존 `imageFileNames`와 `DiaryBlock` 이미지는 V2 마이그레이션에서 옮긴다.
- 백업 V2는 `.easytaskbackup` 패키지로 만들고 manifest, records,
  attachments, 크기와 SHA-256 검증값을 포함한다.
- 복원은 전체 검증과 안전 백업 후 stable ID 기준 merge/upsert로 수행한다.
- CloudKit 저장소에서는 replace-all 복원을 거부한다.

검증:

- JSON V1 백업을 읽을 수 있으며 누락된 이미지는 명확히 보고한다.
- 동일 백업을 여러 번 가져와도 레코드가 중복되지 않는다.
- 오류를 주입한 복원 결과는 완전히 이전 상태이거나 완전히 새 상태다.
- 이미지 추가/삭제 중 실패해도 고아 파일과 깨진 참조가 남지 않는다.

### Phase 6. 조회 성능과 공통 저장소 API

브랜치: `perf/bounded-queries`

스키마 작업이 끝난 뒤 아래 작업 패키지를 병렬로 진행한다.

- Board: 날짜/상태 조건 fetch와 데이터베이스 기반 다음 순서 계산
- Calendar: 현재 월과 겹치는 이벤트를 한 번 가져와 날짜별 인덱스 생성
- Archive: 기간 제한, 페이지 단위 fetch, 검색 debounce
- Review: `reviewId` 조건 fetch와 오류를 숨기지 않는 동기화
- Template: 템플릿별 아이템을 한 번 그룹화하고 반복 스캔 제거

10,000개 작업 기준 조회 성능 테스트를 추가하고, 이미지 디코딩은 메인
스레드의 SwiftUI `body`에서 수행하지 않는다.

### Phase 7. CloudKit 개발 환경 연결

브랜치: `feature/cloudkit-sync`

- 하나의 private CloudKit container ID를 iOS와 macOS에 적용한다.
- iCloud entitlement와 remote notification capability를 두 타겟에 추가한다.
- 개발 환경에서만 스키마를 초기화한다.
- 앱 시작, 백업 merge, 원격 변경 후 무결성 정리를 실행한다.
- 오프라인 동시 편집은 정해진 대표 레코드와 최신 값 규칙으로 수렴시킨다.
- 개발 스키마를 운영으로 올리는 작업은 실기기 검증 전에는 하지 않는다.

필수 실기기 시나리오:

- 같은 날짜 회고를 두 기기에서 동시에 생성
- 작업 상태와 회고 본문을 오프라인에서 각각 수정
- 이미지 추가/삭제 후 재설치와 재로그인
- 부모 이벤트/템플릿 삭제와 연결 작업 정리
- 동일 백업을 양쪽 기기에서 반복 가져오기
- 서로 다른 시간대에서 날짜 이동과 완료 처리

### Phase 8. 릴리스 안정화

브랜치: `release/1.2.0`

- Debug/Release 양쪽 플랫폼 빌드와 UI smoke test를 통과한다.
- iOS와 macOS launch UI smoke test 타겟을 추가해 앱 시작을 검증한다.
- CloudKit Dashboard의 개발 데이터를 확인하고 운영 스키마를 한 번만
  승격한다.
- `MARKETING_VERSION`과 Git 태그를 일치시킨다.
- 데이터 기반 완료 태그: `v1.1.0-data-foundation`
- 동기화 베타 태그: `v1.2.0-sync.beta.1`
- 운영 동기화 태그: `v1.2.0`

## 멀티에이전트 작업 분배

에이전트는 독립 worktree와 단일 책임 브랜치를 사용한다.

| 작업 | 소유 범위 | 병렬 실행 조건 |
| --- | --- | --- |
| WP-SAFETY | `SeedService`, 파일명 검증, 복원 보호, 관련 테스트 | WP-TARGET과 즉시 병렬 |
| WP-TARGET | `Package.swift`, Xcode 프로젝트, scheme, smoke target | WP-SAFETY와 즉시 병렬 |
| WP-SCHEMA | `Models`, `Persistence`, migration tests | Phase 2 병합 후 단독 |
| WP-INTEGRITY | 무결성/중복 정리 서비스와 테스트 | V2 타입 확정 후 |
| WP-MEDIA | 첨부 모델, 이미지 저장 서비스와 테스트 | V2 타입 확정 후 |
| WP-BACKUP | backup package, validator, restore와 테스트 | WP-MEDIA 계약 확정 후 |
| WP-QUERY | Board/Calendar/Archive/Review/Template repository | V2 병합 후 영역별 병렬 |
| WP-PLATFORM | entitlement, container 설정, 앱 진입점 | 모든 로컬 migration 통과 후 |
| WP-VERIFY | 빌드, migration, 성능, 두 기기 시나리오 | 각 병합 후보와 병렬 |

통합 담당자는 즉시 다음 단계가 의존하는 작업을 직접 처리하고, 서브에이전트에는
겹치지 않는 파일 범위만 맡긴다. 서브에이전트 결과는 그대로 병합하지 않고 diff,
테스트, 데이터 호환성을 검토한 뒤 통합 브랜치에 `--no-ff`로 병합한다.

## Git 운영 규칙

1. `main` 직접 커밋과 force push를 금지한다.
2. 모든 브랜치는 최신 `feature/data-foundation`에서 시작한다.
3. 공유된 기능 브랜치는 rebase하지 않고 통합 브랜치에 병합한다.
4. 커밋은 되돌릴 수 있는 한 가지 논리 변경만 포함한다.
5. 커밋 형식은 Conventional Commits를 사용한다.

예시:

```text
fix(backup): reject unsafe attachment paths
feat(persistence): add versioned SwiftData schema
feat(integrity): reconcile duplicate daily reviews
feat(media): persist review attachments with external storage
test(migration): verify V1 store reopens as V2
docs(architecture): document CloudKit rollout gates
```

각 브랜치 병합 전 필수 명령:

```bash
git diff --check
swift test
swift build --target EasyTaskCore
xcodebuild -project EasyTask.xcodeproj -scheme EasyTask-iOS -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project EasyTask.xcodeproj -scheme EasyTask-macOS -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

macOS Xcode 타겟 생성 후에는 양쪽 공유 scheme의 Debug/Release 빌드와 테스트를
추가한다. 스키마 변경 브랜치는 파일 기반 저장소 reopen 테스트 없이는 병합하지
않는다.

## 다음 실행 단위

1. `fix/data-foundation-safety`와 `chore/platform-targets`를 서로 다른
   worktree/에이전트에서 병렬 실행한다.
2. 두 브랜치를 각각 검증하고 `feature/data-foundation`에 순서대로 병합한다.
3. 정리된 프로젝트 구조 위에서 `feature/schema-v1`을 단독 실행한다.
4. V1 저장소 reopen 검증이 끝난 뒤에만 V2 모델 작업을 시작한다.
