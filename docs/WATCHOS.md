# PlanBase watchOS 운영

## 범위

`PlanBase-watchOS`는 iPhone 연결 없이 실행할 수 있는 Apple Watch 앱이다. 같은 Apple ID의
private CloudKit 데이터베이스에서 V8 모델을 열며 다음 기능을 제공한다.

- 오늘 남은 작업·완료 작업과 겹치는 일정 요약
- 받아쓰기와 watchOS 텍스트 입력을 이용한 오늘 작업 빠른 추가
- `할 일 → 진행 중 → 완료`, 완료 작업 재개
- 미래 알림이 남은 작업의 완료 확인
- `accessoryCircular`, `accessoryRectangular`, `accessoryInline`, `accessoryCorner`
  컴플리케이션

기록·회고, 메모, 템플릿, 백업, 첨부 이미지는 Watch MVP 범위에 포함하지 않는다.

## 데이터 흐름

```text
PlanBase-watchOS
  → PlanBaseContainerFactory / EasyTaskSchemaV9
  → iCloud.com.soraul2.easytask private database
  → bounded 오늘 Task·Event query
  → WatchWidgetSnapshotStore
  → group.com.soraul2.easytask/WatchWidget/watch-widget-v1.json
  → PlanBaseWatchWidgetExtension
```

Watch 앱의 상태 변경은 다른 앱과 동일하게 `PersistenceCommandService.perform` 안에서
`TaskLifecycleService.applyStatus`를 호출한다. 따라서 완료 활동과 진행 이벤트도 같은 저장
명령에서 기록된다. CloudKit import 성공 뒤에는 공통 무결성 수렴을 다시 실행한다.

컴플리케이션 확장은 SwiftData나 CloudKit을 직접 열지 않는다. Watch 앱이 App Group에 쓴
당일 최소 요약만 읽으며, 앱 활성화·저장·CloudKit import 뒤 타임라인을 갱신한다. iPhone과
Watch의 App Group 디렉터리는 기기별 로컬 저장소이므로 각각의 앱이 자신의 snapshot을 쓴다.

## 배포 식별자

- Watch 앱: `com.soraul2.easytask.watchkitapp`
- Watch 컴플리케이션: `com.soraul2.easytask.watchkitapp.widget`
- Companion 앱: `com.soraul2.easytask`
- CloudKit/App Group: 기존 iOS·macOS 식별자를 그대로 사용
- 최소 watchOS: 11.0

Watch 앱은 `PlanBase-iOS`의 `Watch/PlanBaseWatch.app`에 포함되고, Watch 앱 안에는
`PlanBaseWatchWidgetExtension.appex`가 포함된다. 앱 아이콘은 공용 `AppIcon`의 watchOS
1024px 마케팅 이미지를 사용한다.

## 검증과 출시 게이트

Xcode의 Settings > Components에서 현재 SDK와 같은 watchOS Simulator runtime을 먼저
설치한다. 그 뒤 다음 전체 게이트가 iOS 앱 내부 Watch 번들·컴플리케이션의 bundle ID,
실행 파일과 privacy manifest까지 확인한다.

```bash
swift test --filter WatchWidgetSnapshotTests
./scripts/verify-platform-builds.sh
```

TestFlight 업로드와 실제 기기 인수 상태는 다음과 같다.

- [x] iOS 앱, Watch 앱, iOS·Watch 위젯의 `CURRENT_PROJECT_VERSION`을 62로 통일
- [x] Apple Developer의 Watch 앱·위젯 App ID와 iCloud, CloudKit, App Group 권한 확인
- [x] Release archive의 iOS 앱 아래 `Watch/PlanBaseWatch.app`과 Watch 앱의 `PlugIns` 확인
- [x] `WKApplication`, companion ID, 네 번들의 배포 서명과 App Store Connect 업로드 확인
- [ ] 실제 Apple Watch에서 iCloud 최초 가져오기, 오프라인 변경 후 iPhone/Mac 수렴 확인
- [ ] 네 가지 컴플리케이션 family의 갤러리, 저휘도 화면, 긴 제목과 큰 글자 확인
- [ ] 미래 알림 작업 완료 후 iPhone의 로컬 알림 캐시 정리 확인

현재 자동 검증은 snapshot 규칙·저장소, SDK 컴파일과 archive 서명·구조를 다룬다.
실제 기기 CloudKit 수렴은 별도 출시 인수 게이트다.
