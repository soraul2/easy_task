# PlanBase Data Foundation Plan

## 목표

macOS와 iPhone 앱을 CloudKit으로 연결하기 전에 데이터 스키마, 무결성,
이미지, 백업, 빌드 타겟을 안정화한다. UI 기능 추가보다 데이터 손실과
기기별 불일치를 막는 것을 우선한다.

## 문서 상태와 현재 기준점

이 문서는 2026-07의 데이터 기반 전환 순서와 당시 브랜치·태그를 보존하는 운영 기록이다.
현재 구현 판단은 아래 최신 상태와 [`ARCHITECTURE.md`](ARCHITECTURE.md)를 우선한다.

### 최초 계획 기준점

- 기준 브랜치: `main`
- 통합 브랜치: `feature/data-foundation`
- 기준 태그: `v1.0.0-local-mvp`
- 기준 커밋: `7e6c92a`
- 검증 결과: 공통 테스트 31개 통과, iOS Simulator Debug 빌드 통과
- 현재 저장 방식: 기기별 로컬 SwiftData

`v1.0.0-local-mvp`는 데이터 기반 작업 중 문제가 생겼을 때 돌아갈 수 있는
복구 지점이다.

## 현재 진행 상태 (2026-09-08)

- 현재 소스의 영속 스키마는 `EasyTaskSchemaV11`이고 V1~V10은 동결되어 있다. V10은
  종료된 Focus 구간 기록 모델, V11은 `TaskTemplate.quickEntryAlias`를 포함한다.
- private CloudKit Production에는 V11까지 배포됐다. 빠른 입력어는 Development의 독립 저장소
  왕복 8단계를 통과했다. 입력어·FocusSession의 실기기 쌍 인수는 별도로 남는다.
- 백업 package V10은 V2~V10을 읽고 빠른 입력어·Task 알림·체크리스트·복합 메모·활동·진행 이벤트·집중 기록과
  회고 첨부를 비파괴 병합한다.
- bounded query/session, 컨테이너 복구 UI, save/rollback, 이미지 다운샘플·제한 캐시,
  iOS/macOS 실행 UI 테스트와 전체 플랫폼 회귀 게이트가 구현됐다.
- 앱 버전 `1.0`(build 76, V11)의 iOS·iPadOS·watchOS 및 macOS TestFlight archive는 앱·위젯
  서명과 App Group·CloudKit 권한을 확인한 뒤 App Store Connect에 업로드됐다.
- 남은 기반 인수 항목은 오프라인 동시 편집, 이미지 추가·삭제 후 재설치,
  iCloud 로그아웃·재로그인과 자동 복구 백업 UX의 실제 기기 시나리오다.

## 핵심 원칙

1. CloudKit은 마지막에 활성화한다. 먼저 로컬 저장소에서 마이그레이션과
   무결성 규칙을 검증한다.
2. `main`에는 빌드와 테스트를 통과한 병합 커밋만 둔다.
3. 모든 데이터 변경은 `PlanBaseCore` 서비스 계층을 통해 실행한다.
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

상태: 완료

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

상태: 완료

- SwiftPM은 `PlanBaseCore`와 공통 테스트를 담당한다.
- Xcode는 iOS와 macOS 앱 번들 타겟을 담당하고 로컬 `PlanBaseCore`
  패키지 제품에 의존한다.
- Xcode 타겟에서 공통 소스 파일을 직접 중복 컴파일하지 않는다.
- iOS/macOS 공유 scheme과 반복 실행 가능한 build smoke 검증을 커밋한다.
- `PlanBaseCore`에는 AppKit, UIKit, PhotosUI 의존성을 허용하지 않는다.

이 단계는 이후 공통 파일 추가가 Package와 Xcode에서 어긋나는 문제를
먼저 제거한다.

### Phase 3. V1 스키마 동결과 컨테이너 통합

브랜치: `feature/schema-v1`

상태: 완료

- 현재 7개 모델을 그대로 표현하는 `EasyTaskSchemaV1`을 만든다.
- `EasyTaskMigrationPlan`과 `PlanBaseContainerFactory`를 추가한다.
- 양쪽 앱 진입점은 같은 팩토리로 컨테이너를 생성한다.
- 이 단계에서는 CloudKit을 명시적으로 비활성화한다.
- 파일 기반 기존 저장소를 열고 재실행하는 마이그레이션 테스트를 추가한다.

예정 파일:

- `shared/Core/Persistence/EasyTaskSchemaV1.swift`
- `shared/Core/Persistence/EasyTaskMigrationPlan.swift`
- `shared/Core/Persistence/PlanBaseContainerFactory.swift`
- `shared/Tests/SchemaMigrationTests.swift`

### Phase 4. V2 무결성 모델과 정리 규칙

브랜치: `feature/schema-v2-integrity`

상태: 완료

- 논리 ID와 물리 레코드 ID를 구분하고 생성/수정 시각을 표준화한다.
- `DailyReview.dayKey`와 기본 템플릿 `seedKey`를 자연 키로 사용한다.
- CloudKit 중복은 가장 큰 `updatedAt`을 가진 후보를 대표로 선택하고,
  수정 시각이 같으면 가장 큰 `instanceID`를 결정적 승자로 판단한다.
- 중복 레코드는 즉시 삭제하지 않고 연결을 대표 레코드로 옮긴 뒤
  `supersededAt`으로 표시한다.
- UUID 외래 키는 검증 가능한 서비스 또는 CloudKit 호환 optional inverse
  relationship으로 단계적으로 이전한다.
- `TemplatePlacement.taskIds`처럼 양방향으로 중복 저장된 값은 원본을 하나로
  줄인다.
- 잘못된 상태, 우선순위, 색상, 날짜 키를 복구하는 무결성 서비스를 추가한다.

예정 파일:

- `shared/Core/Persistence/EasyTaskSchemaV2.swift`
- `shared/Core/Services/DataIntegrityService.swift`
- `shared/Tests/DataIntegrityTests.swift`

구현 결과:

- V1 모델을 버전 내부 타입으로 동결하고 V2 모델과 분리했다.
- V1의 배치 `taskIds`만 남은 작업도 마이그레이션 전에 작업 참조로 복구한다.
- V1 레코드는 내용 기반 안정적 해시로 `instanceID`를 백필해 삽입 순서와 무관하게 수렴한다.
- 논리 ID, 회고 날짜 키, 기본 템플릿/항목 시드 키 중복을 대표 레코드로 병합한다.
- 중복과 고아 레코드는 삭제하지 않고 `supersededAt`으로 표시하며 UI와 백업에서 제외한다.
- 상태, 우선순위, 이벤트 색상, 날짜 키, 예상 시간, 순서와 UUID 참조를 앱 시작 및 백업 전에 정리한다.
- `TemplatePlacement.taskIds`는 V2에서 비영속 호환 값이며 `Task.templatePlacementId`만 원본으로 사용한다.

검증:

- 공통 테스트 60개 Debug/Release 통과
- V1 버전 저장소와 기존 비버전 저장소의 V2 마이그레이션 통과
- V1 중복 레코드 삽입 순서 반전 수렴 테스트 통과
- iOS/macOS Debug/Release 빌드 통과

주의: CloudKit 호환성을 위해 새로운 relationship은 optional, 명시적 inverse,
지원되는 delete rule로 구성하며 ordered relationship은 사용하지 않는다.

### Phase 5. 이미지와 백업 V2

브랜치: `feature/media-backup-v2`

상태: 완료 — 이후 V7 package까지 호환 확장

- 회고 이미지의 원본을 `DiaryAttachment` 모델로 통합한다.
- 첨부에는 ID, 회고 ID, 순서, MIME type, 크기, 해시, 생성/수정 시각과
  external storage 데이터가 들어간다.
- 저장 전에 실제 PNG, JPEG, HEIC 형식을 판별하고 20MB 크기 상한을 적용한다.
- 기존 `imageFileNames`와 `DiaryBlock` 이미지는 V3 컨테이너 개방 후 점진적으로 옮긴다.
- 백업 V2는 `.easytaskbackup` 패키지로 만들고 manifest, records,
  attachments, 크기와 SHA-256 검증값을 포함한다.
- 복원은 전체 검증과 안전 백업 후 stable ID 기준 merge/upsert로 수행한다.
- CloudKit 저장소에서는 replace-all 복원을 거부한다.

구현 결과:

- 기존 V1/V2 스키마를 동결하고 `DiaryAttachment`를 포함한 V3와 V2 → V3 lightweight migration을 추가했다.
- 첨부 원본은 `@Attribute(.externalStorage)` 데이터로 저장하고 MIME, 크기, SHA-256, 순서와 시각을 함께 관리한다.
- ImageIO 실제 디코딩까지 통과한 PNG, JPEG, HEIC만 허용하며 새 추가·삭제는 회고와 한 번에 저장한다.
- 레거시 회고 배열과 이미지 블록을 occurrence 순서 기반의 결정적 첨부 ID로 점진 이관한다.
- 누락·손상 파일이 있으면 레거시 참조를 보존하고, 재실행 시 이미 옮긴 첨부를 중복 생성하지 않는다.
- 레거시 이미지가 회고당 10개를 넘으면 초과분은 이관을 보류하고 원본 참조를 유지하며, 작성 화면에서 미해결 항목을 정리할 수 있다.
- `.easytaskbackup` 패키지는 manifest, records, attachment 원본과 각 크기·SHA-256을 포함한다.
- 복원은 전체 패키지를 먼저 검증하고 `(id, instanceID)` 후보를 병합한 뒤 무결성 정리, 회고당 첨부 수 재검증과 최종 저장을 한 번 수행한다.
- JSON V1은 결정적 인스턴스 ID를 부여해 비파괴 병합하며 포함되지 않은 이미지 원본 목록을 보고한다.
- macOS와 iOS 회고 작성·기록 화면은 첨부, 회고 배열과 block-only 기존 파일을 중복 제거해 함께 표시한다.
- 부분 이관 상태에서는 canonical 이미지 편집을 잠그되 미해결 레거시 항목 삭제는 허용하고, 모두 정리한 저장에서 기존 메타데이터를 제거한다.
- 백업 패키지는 고정 UTI로 등록해 Finder에서 디렉터리가 아닌 package로 취급한다.

검증:

- JSON V1 백업을 읽을 수 있으며 누락된 이미지는 명확히 보고한다.
- 동일 백업을 여러 번 가져와도 레코드가 중복되지 않는다.
- 오류를 주입한 복원 결과는 완전히 이전 상태이거나 완전히 새 상태다.
- 이미지 추가/삭제 중 실패해도 고아 파일과 깨진 참조가 남지 않는다.

검증 결과:

- 공통 테스트 97개 Debug/Release 통과
- V1 → V2 → V3 → V4와 V3 → V4 파일 저장소 reopen 통과
- 실제 PNG/JPEG/HEIC 디코딩, 누락 파일 재시도, 중복 파일 occurrence 이관 통과
- records/첨부 변조, 미선언 파일, 중복 manifest, 동일 인스턴스 충돌 차단 통과
- 반복·부분 겹침 V1/V2 가져오기, 관계·첨부 상대 순서 변조 차단, 최신 로컬 첨부 순서 보존과 동일 시각 후보의 순서 독립 수렴 통과
- 회고 병합 후 첨부 10개 초과 전체 롤백과 레거시 초과분 보류 통과
- iOS/macOS Debug/Release 빌드 통과

### Phase 6. 조회 성능과 공통 저장소 API

브랜치: `perf/bounded-queries`

상태: 핵심 완료

스키마 작업이 끝난 뒤 아래 작업 패키지를 병렬로 진행한다.

- Board: 날짜/상태 조건 fetch와 데이터베이스 기반 다음 순서 계산
- Calendar: 현재 월과 겹치는 이벤트를 한 번 가져와 날짜별 인덱스 생성
- Archive: 기간 제한, 페이지 단위 fetch, 검색 debounce
- Review: `reviewId` 조건 fetch와 오류를 숨기지 않는 동기화
- Template: 템플릿별 아이템을 한 번 그룹화하고 반복 스캔 제거

10,000개 작업 기준 조회 성능 테스트를 추가하고, 이미지 디코딩은 메인
스레드의 SwiftUI `body`에서 수행하지 않는다.

현재 반영:

- 이미지 원본 디코딩을 SwiftUI `body`에서 제거하고 플랫폼별 다운샘플·캐시를 적용했다.
- 앱 루트의 Task/Event/Review 전체 live `@Query`를 제거하고 demo seed와 lazy archive를 action-time 제한 fetch로 전환했다.
- Board는 선택일, 이월 후보, 선택일 겹침 이벤트 쿼리를 분리하고 다음 순서를 `fetchLimit = 1`로 계산한다.
- Calendar는 표시 월의 적응형 5/6주 범위(최대 42일) 이벤트·배치만 관찰하고 날짜 상세와 관계 삭제는 날짜·관계 ID fetch를 사용한다.
- Archive는 행을 자르지 않고 완전한 날짜 그룹 30개씩 페이지를 구성하며, 검색 입력에는 300ms debounce를 적용한다.
- canonical 첨부나 레거시 블록만 있는 회고도 기록 날짜 그룹에 포함한다.
- Review 작성·저장은 선택 날짜의 회고와 선택 회고 ID의 block/attachment만 조회한다.
- 성공한 저장 뒤 기록 세션은 현재 로드한 페이지 깊이를 유지해 갱신한다.
- 10,000개 작업에서 선택 날짜 100개만 반환하는 성능 테스트와 날짜 페이지 경계·희소 검색 테스트를 추가했다.

남은 작업:

- 템플릿 수가 커질 때를 대비한 template item 영속 인덱스는 별도 최적화로 남긴다.
- 실기기 Instruments 기준 메모리·스크롤 계측은 UI smoke test 단계에서 수행한다.

검증 결과:

- 공통 테스트 Debug 122개, Release 121개 통과
- iOS/macOS Debug/Release unsigned build 통과
- 10,000개 작업 중 선택 날짜 100개 조회가 검증 환경에서 약 2.3초로 5초 기준 이내
- 40일 기록의 30/10 날짜 페이지 경계, 하루 31개 작업 원자성, 희소 검색과 이미지 전용 회고 포함 통과

### Phase 7. CloudKit 개발 환경 연결

브랜치: `feature/cloudkit-sync`

상태: 완료 — V8 Development 양방향 probe와 Production 배포까지 확인

- 하나의 private CloudKit container ID를 iOS와 macOS에 적용한다.
- iCloud entitlement와 remote notification capability를 두 타겟에 추가한다.
- 개발 환경에서만 스키마를 초기화한다.
- 앱 시작, 백업 merge, 원격 변경 후 무결성 정리를 실행한다.
- 오프라인 동시 편집은 정해진 대표 레코드와 최신 값 규칙으로 수렴시킨다.
- 개발 스키마를 운영으로 올리는 작업은 실기기 검증 전에는 하지 않는다.

구현 결과:

- `iCloud.com.soraul2.easytask`를 두 앱 타겟의 명시적 private CloudKit 저장소로 설정했다.
- 로컬 테스트와 파일 마이그레이션은 기존 `.none` 저장 모드를 유지한다.
- iCloud, Push Notifications, iOS background remote notification capability와 entitlement를 추가했다.
- 성공적으로 완료된 CloudKit import 뒤 `DataIntegrityService.reconcile`을 실행한다.
- CloudKit 앱 실행에서는 Debug demo seed를 차단한다.
- `--initialize-cloudkit-schema` 인자가 있을 때만 Debug 개발 스키마 초기화를 수행한다.
- 공통 테스트 Debug 102개, Release 101개와 iOS/macOS Debug/Release unsigned build를 통과했다.
- iOS Simulator 설치와 앱 시작을 통과했다.
- 2026-07-11 macOS 기존 87개 레코드 브리지, CloudKit setup/import/export와 iPhone 서명 설치를 확인했다. 동일 Apple ID만으로 충분하다고 간주하지 않고 양 앱의 동일 컨테이너 entitlement, 개발 환경 레코드와 실제 수렴을 계속 확인한다.
- 2026-07-12 macOS ↔ iPhone 기본 create/delete 전파를 고유 진단 레코드로 확인했다.
- 2026-08-14 V7 활동 create/delete 양방향 probe를 통과하고
  `TaskCompletionActivity`를 Production에 배포했다.
- 2026-08-15 V8 진행 이벤트 create/delete 양방향 probe를 통과하고
  `TaskProgressEvent`와 관련 인덱스를 Production에 배포했다.

### Phase 7.1. 저장·동기화 런타임 안정화

브랜치: `fix/runtime-resilience`

상태: 코드·기본 양방향 수렴 완료, 명시적 충돌·재설치 인수 시나리오 유지

- 저장소 개방 실패 시 `fatalError` 대신 원인 표시와 비파괴 재시도를 제공한다.
- 주요 사용자 변경과 무결성 정리를 명시적 save/rollback 명령으로 처리한다.
- CloudKit 이벤트를 ID별로 추적해 동시 작업 상태와 실패를 정확히 유지한다.
- iCloud 계정 상태, 최근 성공 시각, 동기화 오류와 데이터 정리 오류를 앱에서 확인한다.
- 자정과 시간대 변경 뒤 오늘 추적 여부와 사용자가 선택한 날짜 키를 보존한다.
- 모바일 작업 상세·테마·템플릿 생성/삭제를 데스크톱 기능 범위와 맞춘다.
- 공통 테스트 Debug 113개/Release 112개와 iOS/macOS Debug/Release unsigned build를 통과했다.

필수 실기기 시나리오:

- 같은 날짜 회고를 두 기기에서 동시에 생성
- 작업 상태와 회고 본문을 오프라인에서 각각 수정
- 이미지 추가/삭제 후 재설치와 재로그인
- 부모 이벤트/템플릿 삭제와 연결 작업 정리
- 동일 백업을 양쪽 기기에서 반복 가져오기
- 서로 다른 시간대에서 날짜 이동과 완료 처리

### Phase 8. 릴리스 안정화

상태: 앱 버전 1.0(build 76) TestFlight 업로드 완료, 실제 기기 운영 인수 계속

- Debug/Release 양쪽 플랫폼 빌드와 UI smoke test를 통과한다.
- iOS와 macOS launch UI smoke test 타겟을 추가해 앱 시작을 검증한다.
- CloudKit Dashboard의 개발 데이터를 확인하고 운영 스키마를 한 번만
  승격한다.
- `MARKETING_VERSION`과 Git 태그를 일치시킨다.
- 데이터 기반 완료 태그: `v1.1.0-data-foundation`
- 동기화 베타 태그: `v1.2.0-sync.beta.1`
- 운영 동기화 태그: `v1.2.0`

위 브랜치·태그 이름은 최초 계획안이다. 실제 현재 배포 기준은 `MARKETING_VERSION = 1.0`,
`CURRENT_PROJECT_VERSION = 76`이며, 마지막 App Store Connect 업로드도 build 76이다. 태그는
저장소의 실제 릴리스 절차에서 별도로 확정한다.

2026-09-01 검증 결과:

- Debug SwiftPM 337개, Release SwiftPM 336개 통과
- `PlanBaseMobileTests` 16개와 접근성 AX5·기록 이동·기본 글자 크기 UI smoke 통과
- iOS/macOS Debug·Release 전체 빌드 회귀 게이트 통과
- iOS·watchOS/macOS 서명 archive의 앱·위젯 build 62, bundle ID, App Group, CloudKit 및
  iOS Live Activity 선언 검증 통과
- 두 플랫폼 App Store Connect 업로드 성공, Apple package 처리 시작

2026-09-03 검증 결과:

- Focus를 포함한 공통 테스트와 iOS·macOS·watchOS Debug/Release 전체 회귀 게이트 통과
- V10 Development 초기화와 `CD_FocusSession` 확인 후 Production schema 배포·재확인
- iOS 앱·위젯과 Watch 앱·위젯의 build 63, bundle ID, CloudKit·App Group·key-value store
  권한 및 포함 구조 검증 통과
- macOS universal 앱·위젯의 build 63, Production bundle ID와 동일 공유 권한 검증 통과
- iOS와 macOS build 63 App Store Connect 업로드 성공, Apple package 처리 시작
- Focus 진입점 재배치를 포함한 iOS·iPadOS·Watch 앱·위젯 및 macOS 앱·위젯 build 64의
  Release archive, bundle ID, 서명과 공유 권한 검증 통과
- iOS와 macOS build 64 App Store Connect 업로드 성공, Apple package 처리 시작
- Focus·휴식 종료 알림의 빠른 동작, 60분 action token, stale·중복 실행 방지와 foreground
  중복 banner 억제를 iOS·macOS·Watch에 연결
- Debug 356개와 Release 355개 공통 테스트 및 iOS·macOS·watchOS Debug/Release 전체 회귀 통과
- iOS/Watch 네 번들과 macOS 두 번들의 build 65, bundle ID, 서명과 공유 권한 검증 통과
- iOS와 macOS build 65 App Store Connect 업로드 성공, Apple package 처리 시작

2026-09-04 검증 결과:

- 회고 없는 날짜별 활동, 통계 제거, 읽기 전용 작업 기록 및 큰 글자 화면 보완 포함
- build 66 기준 Debug 374개·Release 373개 공통 테스트와 전체 플랫폼 회귀 게이트 통과
- iOS/Watch 네 번들과 macOS universal 두 번들의 버전, 서명, App Group·CloudKit 권한 검증 통과
- App Store Connect 전송 과정의 CloudKit Production 권한 확인
- iOS 13:17:35, macOS 13:17:24 KST 업로드 성공 및 패키지 처리 시작 확인
- 배포 자료와 로그: `.local/releases/build-66/`. Apple 처리 완료와 TestFlight 설치는 별도 확인 대상

같은 날 build 67 업로드 결과:

- 저장한 작업의 검색·즐겨찾기·날짜별 재사용, 칸반 버튼·테마 대비·큰 글자 화면 개선 포함
- 테마 변경 중 날짜·입력 유지와 작업 삭제 안정성 개선, iPhone·iPad 및 실제 Mac 흐름 검증
- 기능 변경 후 Debug 382개·Release 381개 공통 테스트와 전체 플랫폼 회귀 게이트 통과
- build 67의 iOS/Watch 네 번들과 macOS universal 두 번들의 버전·서명·공유 권한 재검증 통과
- 배포 서명의 CloudKit Production 권한, iOS 14:52:20 및 macOS 14:52:19 KST 업로드 성공 확인
- Apple 패키지 처리 시작을 확인했고, TestFlight 설치 가능 상태는 아직 확인하지 않았다.
- 배포 자료·로그·소스 해시 목록: `.local/releases/build-67/`

같은 날 build 68 업로드 결과:

- 집중모드 UI·예상 시간 기본값 반영, 작업 검색·선택, 큰 글자·가로 화면 및 Mac 창 고정 개선
- Debug 385개·Release 384개 공통 테스트와 전체 플랫폼 회귀 통과, 최종 집중 UI 테스트 iPhone·iPad 총 6개 통과
- iOS 앱·위젯, Watch 앱·위젯, macOS universal 앱·위젯의 서명·build 68·공유 권한 검증 통과
- 자동 배포 서명의 CloudKit Production 권한 확인
- iOS 15:49:03 및 macOS 15:49:29 KST 업로드 성공, Apple 패키지 처리 시작 확인
- 배포 자료·로그·소스 해시 목록: `.local/releases/build-68/`. TestFlight 설치 가능 상태는 별도 확인 대상

같은 날 build 70 업로드 결과:

- 무결성 검사의 동일 값 쓰기 제거, 빈 보관 처리 생략, 입력어 후보 계산과 화면 갱신 범위 개선 포함
- Xcode 26.6의 전체 플랫폼 Debug/Release 회귀 게이트 통과. 공통 테스트 Debug 396개·Release 395개 성공 (선택 계측 테스트 각각 3개·2개 제외)
- iOS/Watch 네 번들과 macOS universal 두 번들의 build 70·서명·App Group·CloudKit 권한 검증 통과
- 최종 컴파일 입력 iOS 186개·macOS 178개의 소스 해시 일치, 일반 Release에서 성능 테스트 fixture 제외 확인
- 자동 배포 서명의 CloudKit Production 권한 확인. V11 스키마와 백업 V10은 유지
- iOS 22:16:34 및 macOS 22:18:08 KST 업로드 성공, Apple 패키지 처리 완료 확인
- 기존 내부 그룹 `지인`(2명) 연결과 양 플랫폼 한국어 테스트 안내 저장 확인
- 초기 피드백 100ms 판정은 미검증이며 기존 성능 Goal의 완료를 의미하지 않는다.
- 배포 자료·로그·소스 snapshot: `.local/releases/build-70/`. TestFlight 설치는 별도 확인 대상

2026-09-05 build 71 업로드 결과:

- 버튼·모달·안내 문구와 오류 복구 흐름, 큰 글자·iPad·위젯·집중모드·저장한 작업 화면을 플랫폼 전반에서 정리
- 최신 전체 회귀 iteration424 통과. 공통 테스트 Debug 407개·Release 405개와 iOS/macOS Debug·Release, 포함 Watch·위젯·privacy manifest 검증 성공
- iOS 앱·위젯과 Watch 앱·위젯 네 번들, macOS universal 앱·위젯 두 번들의 앱 버전 1.0·build 71·bundle ID·서명·App Group·CloudKit 권한 검증 통과
- archive가 사용한 컴파일 소스 iOS 190개·macOS 182개가 배포 snapshot과 일치하고 일반 Release에서 검사 fixture가 제외됨을 확인
- V11 스키마와 백업 V10을 유지해 추가 CloudKit schema 배포 없이 iOS 18:20:29, macOS 18:22:09 KST 업로드 성공 및 Apple 패키지 처리 시작 확인
- 배포 자료·로그·검증 결과: `.local/releases/build-71/`. TestFlight 설치 가능 상태와 실제 기기 운영 인수는 별도 확인 대상

2026-09-06 build 72 업로드 결과:

- 칸반 카드의 중립 배경, 제목·보조 정보 배치, 하단 상태·집중 조작 개선 반영
- 전체 플랫폼 Debug/Release 회귀 및 공통 테스트 Debug 407개·Release 405개 통과
- iOS·Watch 네 번들과 macOS universal 두 번들의 버전 1.0·build 72·서명·공유 권한 확인
- 컴파일 소스 iOS 190개·macOS 182개의 배포 snapshot 일치와 운영용 CloudKit Production 권한 확인
- Xcode Organizer에서 iOS 04:00:39, macOS 04:04:12 KST 업로드 성공 및 Apple 패키지 처리 시작 확인
- V11 스키마·백업 V10 유지. 배포 자료는 `.local/releases/build-72/`에 보관하며 실제 설치 가능 상태는 별도 확인 대상

2026-09-07 build 74 업로드 결과:

- 사용자 선택 테마를 밝은 테마 6개와 다크 테마 2개로 정리하고 테마별 대표색·강조 요소 개선
- 전체 플랫폼 회귀 및 공통 테스트 Debug 415개·Release 413개 통과
- iOS·Watch 네 번들과 macOS universal 두 번들의 버전 1.0·build 74·서명·공유 권한 확인
- Xcode Organizer에서 iOS와 macOS 모두 App Store Connect 업로드 성공 확인
- V11 스키마·백업 V10 유지. 배포 자료는 `.local/releases/build-74/`에 보관하며 실제 설치 가능 상태는 별도 확인 대상

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
swift build --target PlanBaseCore
xcodebuild -project PlanBase.xcodeproj -scheme PlanBase-iOS -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PlanBase.xcodeproj -scheme PlanBase-macOS -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

macOS Xcode 타겟 생성 후에는 양쪽 공유 scheme의 Debug/Release 빌드와 테스트를
추가한다. 스키마 변경 브랜치는 파일 기반 저장소 reopen 테스트 없이는 병합하지
않는다.

## 다음 실행 단위

1. 같은 iCloud 계정의 두 기기에서 오프라인 충돌·이미지·재설치·반복 병합 수렴을 검증한다.
2. iCloud 로그아웃·재로그인과 시간대 전환 중 데이터·위젯·알림 재수렴을 확인한다.
3. 실제 기기 Instruments로 대량 기록·이미지 스크롤과 bounded query 메모리를 계측한다.
4. 자동 복구 백업과 복원 UX를 별도 계획으로 설계한다.
5. 다음 schema를 추가할 때 V8 절차처럼 Development 양방향 probe를 완료한 뒤에만
   Production에 배포한다.
