# PlanBase macOS 바탕화면 네이티브 위젯 구현 계획

기준일: 2026-08-14
상태: 구현 및 서명 배포 산출물 검증 완료 — 실기기 위젯 인수·CloudKit 출시 게이트 대기
대상: macOS 26 이상, 기존 iPhone/iPad 위젯 회귀 포함

## 1. 목표

PlanBase macOS 앱이 현재 iPhone 앱과 같은 캘린더 위젯을 네이티브 Mac 위젯으로
제공하게 한다. 사용자는 macOS 위젯 갤러리에서 PlanBase를 찾아 바탕화면과 알림
센터에 추가하고, Mac 앱의 로컬 SwiftData·CloudKit 수렴 결과를 확인할 수 있어야 한다.

첫 배포의 핵심 목표는 다음과 같다.

1. `systemSmall`, `systemMedium`, `systemLarge`, `systemExtraLarge` 캘린더 위젯을
   macOS에 제공한다. 바탕화면에서는 네 family 모두를 검증하고, 알림 센터에서는
   OS가 제공하는 `systemSmall`/`systemMedium`/`systemLarge`를 필수 검증한다.
2. 위젯은 기존처럼 SwiftData나 CloudKit을 직접 열지 않고 App Group JSON
   스냅샷만 읽는다.
3. macOS 앱이 시작·활성화·데이터 변경·CloudKit import 이후 스냅샷을 발행한다.
4. 위젯의 날짜와 오늘 보드 링크가 iPhone 앱이 아니라 네이티브 macOS 앱의
   해당 화면을 연다.
5. 기존 iPhone 홈 화면·iPad 위젯과 iPhone 잠금 화면 위젯을 깨뜨리지 않는다.
6. SwiftData schema, CloudKit schema, 백업 형식과 배포 호환 식별자를 변경하지 않는다.

## 2. 제품 결정

### 네이티브 위젯을 기준으로 한다

- macOS의 `iPhone 위젯 사용` 기능은 보조 경로일 뿐 이번 작업의 완료 기준으로
  인정하지 않는다.
- 위젯 갤러리에서 iPhone 출처가 아닌 설치된 PlanBase macOS 앱의 위젯으로
  나타나야 한다.
- 데이터는 페어링된 iPhone이 아니라 현재 Mac의 PlanBase 앱이 발행한다.
- 앱 설치 후 최소 한 번 macOS 앱을 실행해 WidgetKit이 extension을 발견하고
  최초 스냅샷을 만들게 한다.

### 기존 Widget Extension을 멀티플랫폼으로 확장한다

- 새로 복제한 `PlanBaseMacWidgetExtension`을 만들지 않는다.
- 기존 `PlanBaseWidgetExtension`이 iOS/iPadOS와 macOS를 함께 지원하게 한다.
- 캘린더 provider, intent, theme, view와 snapshot availability 코드는 같은 소스를
  사용한다.
- iPhone 잠금 화면용 `PlanBaseLockScreenWidget`만 `#if os(iOS)` 경계로 macOS
  빌드에서 제외한다.
- 위젯 kind와 snapshot 파일 이름은 플랫폼별로 새로 만들지 않고 기존 호환 값을
  유지한다.

### 지원 family

| 플랫폼 | 제공 family |
|---|---|
| iOS/iPadOS extension | 기존 네 system family 등록, 실제 노출은 기기별 WidgetKit 정책 적용 |
| iPhone 잠금 화면 | 기존 `accessoryInline`, `accessoryCircular`, `accessoryRectangular` |
| macOS | `systemSmall`, `systemMedium`, `systemLarge`, `systemExtraLarge` |

macOS에는 accessory 잠금 화면 위젯을 등록하지 않는다. macOS SDK에서 해당 family는
사용할 수 없으므로 단순히 갤러리에서 숨기는 것이 아니라 소스 컴파일 자체에서
제외한다.

[`systemExtraLarge`](https://developer.apple.com/documentation/widgetkit/widgetfamily/systemextralarge)는
macOS SDK에서 지원하지만 알림 센터에 항상 노출된다고 가정하지 않는다. 바탕화면에서는
필수 인수하고, 알림 센터에서는 현재 OS가 해당 family를 제공할 때만 추가 검증한다.

### 테마 표현 계약

macOS 위젯은 앱 테마를 반영하되 WidgetKit의 렌더링 모드를 거스르지 않는다.

- `.fullColor`에서는 snapshot의 `themeID`와 위젯 환경의 Light/Dark appearance로
  `AppThemePreset`을 해석해 앱의 배경 gradient, panel, text, event palette를 표현한다.
- `.accented`와 `.vibrant`에서는 시스템이 배경을 제거하거나 색을 tint할 수 있으므로
  앱과 픽셀 단위로 같은 색을 완료 조건으로 삼지 않는다. 대신 오늘, 일반 날짜,
  이벤트, 보조 텍스트의 정보 계층과 대비가 유지돼야 한다.
- `widgetRenderingMode`를 읽고 이벤트 표식과 오늘 badge처럼 의미 있는 소수의 요소만
  `widgetAccentable()` 그룹에 둔다. 전체 캘린더를 accentable로 묶지 않는다.
- `containerBackground`는 시스템이 제거할 수 있는 현재 정책을 유지한다.
  테마 배경을 강제로 보존하기 위해 `.containerBackgroundRemovable(false)`를 추가하지
  않는다.
- snapshot의 알 수 없는 `themeID`는 `AppThemePreset.defaultID`로 안전하게 fallback한다.
  snapshot `themeID`는 테마 선택, 위젯의 `colorScheme`은 해당 테마의 Light/Dark variant
  선택이라는 책임을 유지한다.

관련 동작은 Apple의
[추가 위젯 문맥과 appearance 준비](https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-contexts-and-appearances)와
[accented 렌더링 및 Liquid Glass 최적화](https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass)를
기준으로 검증한다.

### 데이터와 저장 경계

```text
PlanBase-macOS
  -> 기존 ModelContainer와 CloudKit import 수렴
  -> bounded query로 CalendarWidgetSnapshot 생성
  -> group.com.soraul2.easytask/Widget/calendar-widget-v1.json 원자적 기록
  -> WidgetCenter timeline reload

PlanBaseWidgetExtension (macOS)
  -> App Group JSON 읽기
  -> TimelineEntry 생성
  -> 바탕화면/알림 센터 렌더링
```

- extension에서 `ModelContainer`, CloudKit container 또는 실제 앱 저장소를 열지 않는다.
- 현재 snapshot v4와 `CalendarWidgetSnapshotStore`를 그대로 사용한다.
- App Group 이름, widget kind, deep-link scheme은 `PlanBaseCompatibility`의 기존 값을
  사용하고 새 상수를 만들지 않는다.
- iPhone과 Mac은 서로 다른 기기의 App Group container에 쓰므로 같은 snapshot 파일
  이름을 사용해도 충돌하지 않는다.

## 3. 현재 상태와 확인된 차이

### Xcode 타겟

- `PlanBaseWidgetExtension`의 `SUPPORTED_PLATFORMS`는 현재
  `iphoneos iphonesimulator`뿐이다.
- extension dependency와 `Embed Foundation Extensions` 단계는 `PlanBase-iOS`에만
  연결되어 있다.
- `PlanBase-macOS`에는 extension dependency와 embed 단계가 없다.
- macOS Debug 앱 bundle ID는 `com.soraul2.easytask.macos`, Release 앱은 배포 호환을
  위해 `com.soraul2.easytask`를 사용한다.

### 소스 호환성

현재 extension을 macOS 26 SDK로 설정만 덮어써서 컴파일한 결과, 캘린더 위젯 소스는
macOS에서 컴파일되고 `PlanBaseLockScreenWidget.swift`의 `accessoryInline`,
`accessoryCircular`, `accessoryRectangular`만 unavailable 오류를 냈다. 따라서
캘린더 위젯을 별도로 복제할 필요가 없다.

### 계획 재검토 기준선

- 2026-08-14에 다른 세션의 `.build` lock과 분리된 scratch path로 `swift test`를
  실행했고 265개 테스트가 통과했다.
- 공통 package의 Debug build가 통과했다.
- 현재 widget target을 macOS SDK로 점검했을 때 calendar source의 추가 compile 오류는
  없었고, 위 iOS accessory family unavailable 오류만 재현됐다.
- 따라서 구현의 첫 compile 수정은 lock-screen 소스 경계이며, schema/persistence
  변경으로 우회할 이유가 없다.

### App Group과 발행

- iOS 앱과 기존 widget entitlement에는 `group.com.soraul2.easytask`가 있다.
- macOS Debug/App Store entitlement에는 App Group이 없다.
- `CalendarWidgetSnapshotPublisher.swift`는 `#if os(iOS)`로 제한되어 있고 iOS 앱
  target membership만 가진다.
- macOS `AppRootView`에는 DataIntegrity 준비 이후 publisher를 활성화하는 경로가 없다.

### 딥 링크

- 위젯은 `planbase://calendar?date=...`와 `planbase://board?scope=today`를 만든다.
- iOS 앱은 URL scheme과 `.onOpenURL` 처리가 모두 있다.
- macOS Info.plist에는 `planbase`/`easytask` URL scheme 등록이 없고 macOS 앱에도
  위젯 route 처리가 없다.

### 렌더링

- 현재 캘린더 위젯은 제거 가능한 `containerBackground`와 콘텐츠 margin 정책을
  이미 사용한다.
- 이벤트 제목에는 privacy 처리가 있지만 캘린더 view는 macOS의 accented 렌더링을
  명시적으로 확인하지 않는다.
- `CalendarWidgetTheme.sundayText`는 event palette의 raw red를 panel/input 위에 그대로
  사용한다. 전체 preset의 Light/Dark token을 점검한 결과 모든 dark preset과
  `roseLilac` light에서 4.5:1 대비를 충족하지 못했다. 측정 범위는 panel 기준
  약 1.61~3.58:1, input 기준 최저 약 1.54:1이었다. 이는 base token 점검값이며
  구현 뒤 opacity가 합성된 실제 표면도 별도로 확인한다.
- event bar의 foreground 계산은 `AppThemeColorSet.resolvedEventForeground(on:)`와 같은
  의미를 widget 파일 안에서 중복 구현하고 있다.
- compact weekday는 7pt, overflow는 6pt이며 expanded/extra-large event title도
  7pt/8pt다. native Mac font metrics에서는 너무 작을 수 있으므로 family별 clipping뿐
  아니라 최소 가독 크기를 함께 확인해야 한다.
- `widgetRenderingMode`와 `widgetAccentable()`을 현재 calendar widget에서 사용하지
  않으므로 full-color 색상만으로 오늘과 이벤트를 구분하는 부분을 점검해야 한다.

## 4. 변경 경계

- `EasyTaskSchemaV1`~`V6`와 `EasyTaskMigrationPlan`을 수정하지 않는다.
- CloudKit Development/Production schema를 초기화하거나 배포하지 않는다.
- 백업 DTO, codec, merge와 `.easytaskbackup` 형식을 수정하지 않는다.
- 다음 호환 식별자를 바꾸지 않는다.
  - Release 앱 bundle ID `com.soraul2.easytask`
  - CloudKit container `iCloud.com.soraul2.easytask`
  - App Group `group.com.soraul2.easytask`
  - 캘린더/잠금 화면 widget kind
  - `planbase`와 `easytask` deep-link scheme
  - `calendar-widget-v1.json` 파일 이름과 snapshot schema 의미
- 위젯에서 작업 완료, 이벤트 생성·편집, 스크롤, 새 사용자 설정을 추가하지 않는다.
- 기존 위젯 밀도와 월 이동 AppIntent 동작을 이번 작업에서 재설계하지 않는다.
- 다른 세션이 수정 중인 파일이 있으면 Xcode project와 entitlement 작업 전에
  변경 소유권을 다시 확인하고 한 작업 트리에서 동시에 편집하지 않는다.

## 5. Xcode와 서명 설계

### 5.1 멀티플랫폼 build settings

`PlanBaseWidgetExtension`에 다음 원칙을 적용한다.

- `SUPPORTED_PLATFORMS`: `iphoneos iphonesimulator macosx`
- `IPHONEOS_DEPLOYMENT_TARGET`: 기존 18.0 유지
- `MACOSX_DEPLOYMENT_TARGET`: 26.0
- `APPLICATION_EXTENSION_API_ONLY`: 계속 `YES`
- `PlanBaseCore` package dependency: 그대로 유지
- macOS scheme이 extension을 Mac SDK로 빌드하도록 `PlanBase-macOS` target dependency 추가
- macOS 앱에 별도 `Embed Foundation Extensions` copy phase를 추가하고 extension의
  CodeSignOnCopy/RemoveHeadersOnCopy 속성을 유지

같은 copy build phase 객체를 두 앱 타겟에 억지로 공유하지 않는다. iOS와 macOS host가
각자 자신의 embed phase와 `PBXBuildFile` 항목을 갖게 한다.

### 5.2 bundle ID

host prefix 검증을 통과하도록 configuration/platform별 ID를 아래처럼 고정한다.

| 빌드 | 앱 bundle ID | 위젯 bundle ID |
|---|---|---|
| iOS Debug/Release | `com.soraul2.easytask` | `com.soraul2.easytask.widget` |
| macOS Debug | `com.soraul2.easytask.macos` | `com.soraul2.easytask.macos.widget` |
| macOS Release | `com.soraul2.easytask` | `com.soraul2.easytask.widget` |

- 기존 iOS/Release extension ID는 변경하지 않는다.
- 새 macOS Debug extension ID는 개발 데이터 병행을 위한 기존 Debug host 예외에만
  사용한다.
- `PRODUCT_BUNDLE_IDENTIFIER[sdk=macosx*]` 같은 조건부 build setting으로 한 target에서
  플랫폼별 값을 선택한다.

### 5.3 entitlement

새 파일을 제안한다.

```text
desktop/Configuration/PlanBaseWidget-macOS.entitlements
```

포함 항목:

- `com.apple.security.app-sandbox = true`
- `com.apple.security.application-groups`
  - `group.com.soraul2.easytask`

추가 변경:

- `desktop/Configuration/PlanBase-macOS.entitlements`에 같은 App Group 추가
- `desktop/Configuration/PlanBase-macOS-AppStore.entitlements`에 같은 App Group 추가
- iOS widget은 기존 `mobile/Configuration/PlanBaseWidget.entitlements`를 계속 사용
- `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`로 macOS extension entitlement를 선택

Debug macOS 앱은 현재 비샌드박스 개발 정책을 유지한다. App Group entitlement만
추가하고 이 작업을 이유로 Debug 앱 전체를 App Sandbox로 전환하지 않는다.

### 5.4 Developer portal과 provisioning

코드 완료와 별개로 아래 외부 설정을 확인한다.

1. 기존 App Group `group.com.soraul2.easytask`에 macOS Release 앱 ID와 macOS widget
   extension App ID를 연결한다.
2. Debug와 Release archive는 Automatic signing으로 앱과 위젯의 개발 프로파일을
   관리한다.
3. App Store Connect export는 앱과 위젯을 Apple Distribution으로 재서명하고 Xcode가
   관리하는 Store provisioning profile을 사용한다.
4. archive와 export package 안의 앱·extension에 실제로 포함된 entitlement와 profile을
   각각 `codesign`, `security cms`로 확인한다.

프로파일 준비가 늦어져도 `CODE_SIGNING_ALLOWED=NO` 빌드와 공통 테스트는 진행할 수
있지만, 실제 바탕화면 위젯 인수 검증은 서명된 설치본 없이는 완료로 표시하지 않는다.

## 6. 단계별 구현 계획

### 2026-08-14 구현 진행 기록

- iOS/macOS extension 직접 Debug 컴파일과 양 앱 Debug/Release embed 빌드가 통과했다.
- `./scripts/verify-platform-builds.sh`가 종료 코드 0으로 통과했다. SwiftPM 테스트는
  Debug 267개, Release 266개가 통과했으며 Release에서 제외되는 Debug 전용 테스트
  1개가 차이를 만든다.
- iOS publication 통합 테스트에서 non-default theme 보존과 theme-only 갱신을 확인했다.
- Release 산출물의 macOS host/widget bundle ID는 각각
  `com.soraul2.easytask`, `com.soraul2.easytask.widget`이고 iOS도 기존 두 ID를 유지한다.
- plist/entitlement/project lint와 `git diff --check`가 통과했다.
- 서명 Debug 빌드는 `com.soraul2.easytask.macos.widget`용 Mac App Development
  provisioning profile 부재로 중단됐다. `-allowProvisioningUpdates`는 Apple Developer
  계정에 외부 변경을 만들 수 있어 자동 실행하지 않았다.
- 따라서 Phase 0~6의 자동 검증 범위는 완료됐고, Developer portal capability/profile,
  서명 설치본의 갤러리·렌더링·딥 링크·VoiceOver 확인은 Phase 7에 남아 있다.

### Phase 0 — 작업 기준점과 충돌 경계 고정

- [ ] `git status --short`로 다른 세션의 변경 파일을 다시 확인한다.
- [ ] `PlanBase.xcodeproj/project.pbxproj`, macOS entitlement/Info.plist, widget source와
  `desktop/App/AppRootView.swift`가 다른 세션에서 편집 중이지 않은지 확인한다.
- [ ] 기존 `swift test` 결과를 기록한다.
- [ ] iOS와 macOS Debug scheme의 서명 없는 build를 기준점으로 기록한다.
- [ ] 현재 iOS widget target을 직접 빌드해 변경 전 회귀 기준을 남긴다.

완료 조건:

- 작업 대상 파일의 동시 편집자가 없다.
- 기존 공통 테스트와 양 앱 Debug build 결과를 알고 있다.

### Phase 1 — Widget Extension의 macOS 컴파일 경계

- [ ] `PlanBaseWidgetExtension`에 macOS 26 destination을 추가한다.
- [ ] `PlanBaseWidgetBundle`에서 `PlanBaseCalendarWidget`은 모든 지원 플랫폼에
  등록하고 `PlanBaseLockScreenWidget`만 iOS 조건부로 등록한다.
- [ ] `PlanBaseLockScreenWidget.swift` 전체를 iOS 컴파일 경계로 감싸 macOS SDK가
  accessory family 심볼을 해석하지 않게 한다.
- [ ] 캘린더 widget configuration의 네 system family를 macOS에서도 유지한다.
- [ ] macOS widget gallery 설명은 `홈 화면` 대신 `바탕화면` 문맥을 사용한다.
- [ ] `CalendarWidgetIntent`, timeline, theme, views가 양 SDK에서 컴파일되는지 확인한다.
- [ ] iOS widget build에서 잠금 화면 세 family가 그대로 남는지 확인한다.

완료 조건:

- extension target이 iPhoneSimulator SDK와 macOS SDK에서 모두 컴파일된다.
- macOS build에는 calendar widget만, iOS build에는 calendar와 lock-screen widget이
  함께 포함된다.

### Phase 2 — macOS 앱 embed와 App Group 연결

- [ ] `PlanBase-macOS`에 widget target dependency를 추가한다.
- [ ] macOS 앱 전용 Embed Foundation Extensions phase를 추가한다.
- [ ] Debug/Release 및 플랫폼 조건부 bundle ID를 적용한다.
- [ ] macOS 앱 두 entitlement에 기존 App Group을 추가한다.
- [ ] macOS widget 전용 sandbox/App Group entitlement를 추가한다.
- [ ] macOS App Groups capability metadata와 서명 설정을 Xcode에서 확인한다.
- [ ] 서명 없는 macOS 앱 build 결과의
  `PlanBase.app/Contents/PlugIns/PlanBaseWidgetExtension.appex` 존재를 확인한다.
- [ ] iOS app bundle에도 기존 extension이 계속 embed되는지 확인한다.

완료 조건:

- 양 host가 자신의 플랫폼용 extension을 번들에 포함한다.
- extension bundle ID가 각 host bundle ID의 prefix 규칙을 만족한다.
- App Group 값은 새 이름 없이 기존 호환 값을 사용한다.

### Phase 3 — 공통 snapshot publisher와 macOS 수명주기

publisher는 양 앱에서 같은 구현을 사용하되 `PlanBaseCore` 안에 WidgetKit 의존성을
넣지 않는다. 기존 파일을 아래의 SwiftPM target 밖 중립 위치로 옮기는 것을
기본안으로 한다.

```text
shared/WidgetSupport/CalendarWidgetSnapshotPublisher.swift
```

- [ ] 기존 `#if os(iOS)`를 제거하고 iOS/macOS 공통 컴파일 가능 상태로 만든다.
- [ ] 옮긴 파일을 `PlanBase-iOS`, `PlanBase-macOS` 두 앱 target에 명시적으로 등록한다.
- [ ] Swift Package의 `shared/Core` target에는 포함하지 않는다.
- [ ] 현재 bounded CalendarEvent/Task query와 150ms coalescing을 그대로 유지한다.
- [ ] macOS `AppRootView`에 `isWidgetSnapshotPublisherReady` gate를 추가한다.
- [ ] DataIntegrity reconciliation과 레거시 이관이 끝난 뒤 publisher를 활성화한다.
- [ ] 시작 중 다른 정리 작업이 실패해도 `defer`에서 best-effort publication을
  활성화하는 iOS 정책을 macOS에도 적용한다.
- [ ] 앱 활성화, 테마 변경, data changed notification, CloudKit import, 자정과 시간대
  변경 후 snapshot이 최종 상태로 수렴하는지 확인한다.
- [ ] Mac에서 선택한 non-default `themeID`가 snapshot에 기록되고, 이벤트 내용이 같아도
  theme만 바뀌면 content change로 판정해 파일 기록과 timeline reload가 발생하게 한다.
- [ ] Mac publisher가 두 widget kind를 reload해도 macOS에 없는 lock-screen kind로
  인한 오류가 없는지 확인한다. 필요하면 timeline reload 목록만 플랫폼별로 나눈다.
- [ ] App Group container를 얻지 못한 오류를 실제 빈 일정으로 바꾸지 않고 로그와
  갱신 상태로 유지한다.

완료 조건:

- Mac 앱 첫 실행 뒤 App Group에 현재 Mac 데이터의 v4 snapshot이 기록된다.
- 이벤트·테마·CloudKit import 이후 내용 변경 시 macOS calendar timeline이 reload된다.
- widget extension은 계속 snapshot 파일만 읽는다.

### Phase 4 — macOS deep link

- [ ] macOS Info.plist에 `planbase`, 레거시 `easytask` URL scheme을 등록한다.
- [ ] `AppRootView`에 `.onOpenURL` route 처리를 추가한다.
- [ ] `AppRootView`에 `selectedBoardDate`와 별개인 `calendarNavigationDate` 상태를
  만들고 `CalendarView`에 `@Binding`으로 전달한다.
- [ ] calendar route의 유효한 day key를 `calendarNavigationDate`에 전달한 뒤 캘린더
  탭을 선택한다.
- [ ] `CalendarView`는 iOS `MobileCalendarView`와 같은 소비 패턴으로 새 날짜를 감지해
  `visibleMonth`와 `selectedDate`를 갱신하고 `.day(date)` sheet를 연 뒤 binding을
  비운다. 템플릿 배치 같은 다른 활성 sheet가 있으면 일관된 규칙으로 정리한다.
- [ ] `board?scope=today`는 처리 시점의 오늘 날짜를 계산해 보드 탭을 연다.
- [ ] 명시 날짜 board route가 들어오면 해당 day key를 복원해 보드 탭을 연다.
- [ ] 잘못된 scheme, host, 중복 파라미터, 유효하지 않은 날짜는 화면 상태를
  바꾸지 않는다.
- [ ] cold launch, 이미 실행 중인 앱, 백그라운드 상태를 각각 확인한다.
- [ ] `open 'planbase://calendar?date=2026-08-14'`와
  `open 'planbase://board?scope=today'`로 macOS route smoke test를 수행한다.

가능하면 URL 해석은 기존 `PlanBaseDeepLink`만 사용하고 macOS UI에서 날짜 문자열을
다시 파싱하거나 별도 scheme 규칙을 만들지 않는다.

완료 조건:

- 위젯 날짜 탭은 네이티브 macOS 캘린더의 같은 날짜를 연다.
- 오늘 위젯 링크 의미는 iOS와 macOS에서 같다.
- 기존 iOS deep link 테스트와 실제 동작에 회귀가 없다.

### Phase 5 — macOS 렌더링과 접근성

- [ ] `CalendarWidgetTheme`가 snapshot `themeID`와 environment `colorScheme`으로
  preset/appearance를 결정하고, 알 수 없는 ID는 기본 preset으로 fallback하게 한다.
- [ ] event foreground의 중복 계산을 제거하고
  `AppThemeColorSet.resolvedEventForeground(on:)`를 재사용한다.
- [ ] 일요일 semantic color는 raw red를 무조건 쓰지 않는다. panel/input 등 실제
  표면에서 4.5:1 이상이면 red를 사용하고, 미달이면 `primaryText`를 포함한 공통
  readable-foreground resolver로 fallback한다. 일요일 의미는 첫 열 위치와 font
  weight로도 유지한다.
- [ ] 위 semantic foreground 계산은 WidgetKit에 의존하지 않는 Core theme 규칙으로
  두어 전체 preset의 Light/Dark 조합을 SwiftPM 테스트할 수 있게 한다.
- [ ] `.fullColor`, `.accented`, `.vibrant`를 명시적으로 분기 또는 수용하고 오늘 badge,
  event mark처럼 필요한 요소만 `widgetAccentable()`로 표시한다.
- [ ] `containerBackground`의 제거 가능 상태를 유지하고, `.contentMarginsDisabled()`와
  현재 수동 padding 조합이 Mac에서 과도하거나 부족하지 않은지 family별로 확인한다.
  시스템 margin을 되살리는 편이 낫다면 한 플랫폼 상수를 추가하고 근거를 기록한다.
- [ ] `systemSmall`, `systemMedium`, `systemLarge`, `systemExtraLarge`를 실제 Mac
  바탕화면에서 확인한다. 알림 센터는 small/medium/large를 필수 확인하고 extra-large는
  현재 OS가 제공할 때만 확인한다.
- [ ] Light/Dark와 macOS 위젯 스타일의 full-color/accented/vibrant 표현을 확인한다.
- [ ] 색상만으로 이벤트, 오늘, 선택 월을 구분하지 않게 한다.
- [ ] native Mac font metrics에서 요일, 날짜, 긴 이벤트 제목, `+N`이 잘리지 않는지
  확인한다.
- [ ] Mac에서 표시하는 weekday/day/event title은 8pt 이상, overflow `+N`은 7pt
  이상을 하한으로 둔다. 공간이 부족하면 6pt까지 축소하지 않고 표시 lane/label의
  수를 줄인다.
- [ ] 크기 변경은 shared style의 iPhone/iPad 회귀를 막도록 필요하면
  `#if os(macOS)` 또는 platform metric으로 분리한다.
- [ ] 이벤트 제목의 privacy 처리가 macOS 잠금/개인정보 설정에서 유지되는지 확인한다.
- [ ] VoiceOver가 날짜, 전체 이벤트 수, 표시 제목과 overflow를 중복 없이 읽는지
  확인한다.
- [ ] 월 이동 Button intent와 날짜별 Link가 포인터·키보드 환경에서 동작하는지
  확인한다.
- [ ] 최소 apple-system/rose-lilac preset의 Light/Dark와 empty/populated/overflow
  데이터를 모든 family preview 또는 수동 캡처 matrix로 남긴다.

완료 조건:

- 모든 Mac system family에서 잘림 없이 핵심 정보가 읽힌다.
- 전체 preset의 Light/Dark semantic text가 4.5:1 이상이며 일요일 raw red 대비 결함이
  재발하지 않는다.
- accented/vibrant 렌더링에서도 오늘과 이벤트 존재 여부를 구분할 수 있다.
- iPhone/iPad의 기존 위젯 디자인에 의도하지 않은 변화가 없다.

### Phase 6 — 자동 검증과 회귀 게이트

- [ ] 기존 `CalendarWidgetSnapshotTests`, `PlanBaseBoardDeepLinkTests`를 유지한다.
- [ ] 플랫폼 분기 때문에 순수 규칙 테스트를 복제하지 않는다.
- [ ] publisher 파일 이동 후 기존 `PlanBaseWidgetSnapshotIntegrationTests`가 계속
  publication service를 검증하게 한다.
- [ ] `AppThemeTests`에서 모든 preset의 Light/Dark에 대해 widget semantic text,
  특히 일요일 foreground가 실제 panel/input surface에서 4.5:1 이상인지 검증하고,
  알 수 없는 theme ID가 기본 preset으로 해석되는지도 확인한다.
- [ ] `CalendarWidgetSnapshotTests`의 동일 이벤트·변경된 theme content-change 테스트를
  유지한다.
- [ ] `PlanBaseWidgetSnapshotIntegrationTests`에서 non-default theme ID가 publication
  service를 거쳐 snapshot에 보존되고 theme-only 변경도 `didWrite == true`인지 검증한다.
- [ ] 필요하면 macOS platform compile 전용 smoke fixture를 추가하되 실제 App Group이나
  CloudKit에 접근하는 자동 테스트는 만들지 않는다.
- [ ] `scripts/verify-platform-builds.sh`의 macOS scheme build가 extension까지
  의존 빌드하고 앱 bundle 안의 `.appex` 존재도 확인하게 한다.
- [ ] iOS/macOS extension 직접 build에서 AppIntent metadata extraction과 WidgetKit
  extension validation 오류가 없는지 확인한다.
- [ ] `plutil -lint`로 변경한 Info.plist와 entitlement 파일을 검증한다.
- [ ] `git diff --check`를 통과한다.
- [ ] SwiftPM Debug/Release 테스트와 양 플랫폼 Debug/Release build를 통과한다.

단계별 빠른 명령:

```bash
swift test

xcodebuild -project PlanBase.xcodeproj \
  -target PlanBaseWidgetExtension \
  -configuration Debug \
  -sdk macosx \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild -project PlanBase.xcodeproj \
  -scheme PlanBase-macOS \
  -configuration Debug \
  -sdk macosx \
  CODE_SIGNING_ALLOWED=NO \
  build
```

최종 회귀 게이트:

```bash
./scripts/verify-platform-builds.sh
```

구현 중에는 아래 게이트를 순서대로 통과한다. 앞 게이트가 실패하면 뒤 단계의 수동
검증으로 성공을 추정하지 않는다.

| 게이트 | 통과 조건 |
|---|---|
| A. SDK compile | extension 직접 build가 iPhoneSimulator/macOS SDK에서 성공하고 macOS에서 accessory symbol 오류가 없다 |
| B. host embed | iOS/macOS 앱 build가 성공하고 각 앱 bundle의 `PlugIns`에 올바른 `.appex`가 한 번만 들어 있다 |
| C. identity/signing | host-extension bundle ID prefix, App Group entitlement, provisioning profile이 configuration별 계약과 같다 |
| D. runtime data | 서명 설치본에서 App Group URL을 얻고 Mac 앱이 snapshot을 쓴 뒤 WidgetKit이 native extension을 발견한다 |
| E. theme/UI | family·appearance·rendering-mode matrix에서 대비, 최소 글자 크기, margin, interaction을 통과한다 |

완료 조건:

- 공통 Debug/Release 테스트가 통과한다.
- iOS/macOS Debug/Release 앱 build가 모두 통과한다.
- 두 앱 bundle에 올바른 플랫폼의 extension이 포함된다.

### Phase 7 — 서명된 설치본과 출시 인수

- [ ] Automatic signing Debug 앱을 Mac에 설치하고 한 번 실행한다.
- [ ] 위젯 갤러리에서 PlanBase native Mac 위젯을 찾는다.
- [ ] 같은 계정의 iPhone 위젯이 함께 보일 때 native Mac 출처를 구분한다.
- [ ] 네 system family를 바탕화면에 각각 추가한다.
- [ ] 알림 센터에는 small/medium/large를 추가하고, extra-large는 OS가 제시할 때만
  추가·표시한다.
- [ ] 이벤트 0개, 1개, 여러 날 이벤트, lane overflow, 긴 한글/영문/이모지 제목을
  확인한다.
- [ ] Mac 앱에서 이벤트를 추가·수정·삭제한 뒤 위젯 갱신을 확인한다.
- [ ] 다른 기기에서 변경한 이벤트가 CloudKit import와 reconciliation 뒤 위젯에
  반영되는지 확인한다.
- [ ] 테마, 날짜, 월, 시스템 시간대 변경 뒤 snapshot coverage와 표시가 맞는지
  확인한다.
- [ ] 모든 앱 theme preset의 Light/Dark를 full-color에서 확인하고 대표 preset을
  accented/vibrant에서도 확인한다. 시스템 tint 때문에 달라진 색은 결함으로 보지
  않되 정보 계층과 semantic contrast 손실은 결함으로 기록한다.
- [ ] 앱 종료 상태에서도 마지막 정상 snapshot을 표시하고 timeline 날짜 전환이
  잘못된 빈 상태를 만들지 않는지 확인한다.
- [ ] 날짜/월 이동/딥 링크를 cold/warm launch에서 확인한다.
- [ ] Console에 App Group denial, extension crash, future-schema overwrite 오류가
  없는지 확인한다.
- [x] Release archive의 앱과 extension entitlement, bundle ID, provisioning profile을
  검사한다.
- [ ] TestFlight 또는 App Store Connect 배포 빌드에서 위젯 갤러리 등록을 최종 확인한다.

완료 조건:

- native Mac 위젯의 지원 family가 실제 바탕화면과 알림 센터에서 표시·갱신·이동한다.
- 서명된 Release archive가 App Group과 host/extension ID 검증을 통과한다.
- iOS/iPadOS 위젯과 잠금 화면 위젯의 출시 전 수동 항목에 회귀가 없다.

## 7. 예상 변경 파일

### 새 파일

- `desktop/Configuration/PlanBaseWidget-macOS.entitlements`
- `shared/WidgetSupport/CalendarWidgetSnapshotPublisher.swift`
  - 기존 `mobile/App/Infrastructure/CalendarWidgetSnapshotPublisher.swift` 이동

### 수정 파일

- `PlanBase.xcodeproj/project.pbxproj`
  - multiplatform widget 설정, macOS dependency/embed, target membership와 조건부 서명
- `mobile/Widget/PlanBaseWidgetBundle.swift`
  - lock-screen widget의 iOS 조건부 등록
- `mobile/Widget/PlanBaseLockScreenWidget.swift`
  - iOS 전용 컴파일 경계
- `mobile/Widget/PlanBaseCalendarWidget.swift`
  - macOS gallery 설명과 필요 시 platform family/preview 조정
- `mobile/Widget/CalendarWidgetViews.swift`
  - rendering mode, accentable grouping, font metric, margin 보정
- `mobile/Widget/CalendarWidgetTheme.swift`
  - 공통 contrast resolver 재사용과 preset fallback 확인
- `shared/Core/Theme/AppTheme.swift`
  - WidgetKit-free semantic foreground resolver
- `shared/Tests/AppThemeTests.swift`
  - 전체 preset/appearance의 widget semantic contrast와 unknown-ID fallback
- `shared/Tests/CalendarWidgetSnapshotTests.swift`
  - 기존 theme-only content change 회귀
- `mobile/Tests/PlanBaseWidgetSnapshotIntegrationTests.swift`
  - non-default/theme-only publication 회귀
- `mobile/App/PlanBaseMobileApp.swift`
  - publisher 이동에 따른 참조/target membership 확인
- `desktop/App/AppRootView.swift`
  - snapshot readiness, publisher, deep-link routing
- `desktop/App/Features/Calendar/CalendarView.swift`
  - calendar navigation binding 소비와 day sheet 표시
- `desktop/Configuration/PlanBase-macOS-Info.plist`
  - `planbase`/`easytask` URL scheme
- `desktop/Configuration/PlanBase-macOS.entitlements`
  - Debug App Group
- `desktop/Configuration/PlanBase-macOS-AppStore.entitlements`
  - Release App Group
- `scripts/verify-platform-builds.sh`
  - macOS extension build/embed 검증
- `docs/ARCHITECTURE.md`
  - 양 플랫폼 위젯 발행과 native Mac extension 경계
- `AGENTS.md`
  - 디렉터리 지도, 타겟, 검증 항목 갱신
- `docs/README.md`
  - active 계획 인덱스 등록

`docs/README.md`가 다른 세션에서 수정 중이면 이번 계획 문서 작성 시점에는 건드리지
않고, 해당 변경이 정리된 뒤 구현 작업 또는 통합 단계에서 링크 한 줄만 추가한다.

## 8. 위험과 대응

| 위험 | 대응 |
|---|---|
| macOS Debug host와 widget bundle ID prefix 불일치 | macOS Debug에만 `.macos.widget` 조건부 ID 사용 |
| macOS Release provisioning에 App Group 누락 | host/extension App ID capability와 profile 재생성, `codesign` 검사 |
| accessory family가 macOS build를 막음 | bundle 등록과 lock-screen source 전체를 iOS 조건부 컴파일 |
| Mac 앱이 snapshot을 쓰지 않아 실제 빈 일정처럼 보임 | DataIntegrity 이후 readiness gate와 missing/stale 상태 유지 |
| 위젯 탭이 iPhone 앱 또는 아무 앱도 열지 않음 | macOS URL scheme 등록과 cold/warm `.onOpenURL` 검증 |
| raw red 일요일 글자가 dark/rose-lilac 표면에서 저대비 | semantic foreground resolver와 전체 preset 4.5:1 테스트 |
| Mac accented/vibrant 렌더링에서 앱 색 구분 손실 | exact palette가 아닌 정보 계층을 계약으로 삼고 최소 accentable group 적용 |
| Mac native font metric에서 6~8pt 글자가 읽히지 않음 | Mac 크기 하한 적용, 공간 부족 시 lane/label 수 축소 |
| system margin과 수동 padding이 중복돼 내용이 작아짐 | removable background 유지 상태로 family별 실제 content bounds 확인 |
| 알 수 없는 또는 변경된 theme ID가 반영되지 않음 | default fallback, theme-only content change와 publication 테스트 |
| 한 target을 두 host가 embed하며 Xcode project 충돌 | host별 dependency/copy phase를 분리하고 양 scheme을 연속 빌드 |
| 다른 세션이 project.pbxproj를 동시에 수정 | Phase 0에서 파일 소유권 확인 후 단일 세션만 편집 |
| iPhone 위젯을 native Mac 위젯으로 오인 | 갤러리 출처와 Mac 앱 단독 데이터 갱신으로 구분 검증 |

## 9. 완료 기준

다음 항목이 모두 충족돼야 계획을 `plans/completed/`로 옮긴다.

1. `PlanBaseWidgetExtension`이 iOS/iPadOS와 macOS에서 같은 캘린더 소스를 빌드한다.
2. macOS 앱 bundle에 서명된 widget extension이 포함된다.
3. macOS 바탕화면에서 네 system family를 추가할 수 있고 알림 센터에서
   small/medium/large를 추가할 수 있다. extra-large는 OS가 제공할 때만 확인한다.
4. Mac 앱이 기존 App Group snapshot을 발행하고 위젯은 그것만 읽는다.
5. Mac 이벤트·테마·CloudKit import 변경이 snapshot과 timeline에 수렴한다.
6. 캘린더 날짜와 오늘 보드 링크가 native Mac 앱의 올바른 화면을 연다.
7. 실제 빈 일정과 missing/corrupt/stale/future-schema 상태를 구분한다.
8. 전체 preset의 Light/Dark에서 semantic text 대비가 4.5:1 이상이고,
   full-color/accented/vibrant, 긴 제목과 VoiceOver에서 핵심 정보가 읽힌다.
9. macOS Debug/Release의 host-extension bundle ID와 entitlement가 유효하다.
10. 기존 iPhone/iPad 캘린더 위젯과 iPhone 잠금 화면 위젯에 회귀가 없다.
11. `swift test`, Release 테스트와 양 플랫폼 Debug/Release build가 통과한다.
12. 실제 서명 설치본과 TestFlight/App Store Connect 빌드에서 위젯 갤러리를 확인했다.

## 10. 제외 범위와 후속 후보

이번 작업에서 제외:

- 위젯 안에서 이벤트 생성·수정·삭제
- 위젯에서 Task 상태 직접 변경
- macOS 전용 별도 위젯 디자인이나 별도 widget kind
- SwiftData/CloudKit을 여는 독립 widget persistence stack
- 실시간 CloudKit push를 extension이 직접 처리하는 구조
- 새로운 snapshot schema와 데이터 모델 migration
- 캘린더 외 메모·통계·활동 스트릭 위젯

후속 후보:

- Mac용 `오늘 작업` system widget
- 사용자 선택 캘린더/색상 필터가 있는 configurable widget
- macOS Control Center용 PlanBase control
- 활동 스트릭·히트맵 요약 위젯
- 위젯 개인정보 표시 수준을 선택하는 AppIntent configuration

후속 후보는 native 캘린더 위젯의 갱신 신뢰성과 실제 사용성을 확인한 뒤 별도 계획으로
설계한다.

## 11. 권장 커밋 순서

```text
1. build(widget): add macOS destination and native extension embedding
2. fix(widget): isolate iOS lock-screen families from macOS builds
3. feat(widget): publish shared snapshots from the macOS app
4. feat(macOS): handle calendar and board widget deep links
5. fix(widget): adapt native Mac rendering and accessibility
6. test(widget): verify cross-platform builds and embedded extensions
7. docs(widget): document native macOS widget operations and release checks
```
