# PlanBase Task 중심 잠금 화면·Live Activity 확장 계획

기준일: 2026-08-31
최종 갱신: 2026-09-01
상태: build 56 실기기 피드백 반영·build 60 서명 업로드 완료, 최종 저휘도·인증·iPad/macOS 인수 대기
우선순위: iPhone → iPad → macOS

## 구현 결과 (2026-08-31)

- 잠금 화면 family별 구성을 구현했다: Inline은 오늘 CalendarEvent, Rectangular는 현재/다음
  Task와 완료 수치, Circular는 오늘 Task 빠른 추가를 담당한다.
- 오늘 `doing` Task가 있을 때만 하나를 유지하는 Live Activity와 잠금 화면·Dynamic Island
  표현, `완료/전체`, 48×48pt `→`·`✓` Task 버튼을 구현했다.
- 상태 변경 App Intent는 앱 프로세스의 기존 SwiftData container와
  `PersistenceCommandService.perform`을 사용하고, Widget Extension은 계속 App Group
  snapshot만 읽도록 경계를 유지했다.
- 이월 Task 제외, 오늘 이동 시 포함, 결정적 대표 Task 선택, 딥링크 규칙을 공통 서비스와
  단위 테스트로 고정했다.
- Debug 328개와 Release 327개 Swift Package 테스트 및 iOS/macOS Debug·Release 전체 빌드
  회귀 게이트를 통과했다.
- Live Activity의 진행 막대를 제거하고 좌측 제목·완료 수치, 우측 58×48pt 완료·다음 버튼
  구조로 개선했다. 앱·위젯 build 43, 기존 App Group·CloudKit 권한,
  `NSSupportsLiveActivities=true`를 서명 archive에서 검증한 뒤 App Store Connect 업로드에
  성공했다.
- Dynamic Island 개선판을 iOS TestFlight build 44로 archive했다. Release 테스트 327개와
  iOS Release 빌드, 앱·위젯 build number, App Group·CloudKit entitlement,
  `NSSupportsLiveActivities=true`, RunCat 5프레임 및 라이선스 포함 여부를 검증한 뒤 App Store
  Connect 업로드에 성공했다.
- build 44 실기기 확인에서 Cat이 정지 프레임으로만 보였다. Apple의 Live Activity는
  timeline 기반으로 계속 실행되지 않고, 콘텐츠 변경 애니메이션도 최대 2초로 제한되므로
  프레임 애니메이션을 안정적으로 지속할 수 없다고 결론 내렸다. Cat 코드·자산·라이선스는
  제거했다.
- Cat을 대신해 SwiftUI 시스템 timer text를 최소형·축소형·확장형과 잠금 화면에 배치했다.
  과거에 끝난 진행 구간의 `recordedDuration`과 현재 세션 경과 시간을 합산한 기준 시각을
  전달하므로 앱이 실행 중이지 않아도 누적 진행 시간이 실시간으로 증가한다.
- 실시간 누적 진행 시간과 Cat 자산 제거를 포함한 iOS TestFlight build 45는 Release 패키지
  테스트와 서명 archive 생성을 통과했다. 앱·위젯 build number, App Group·CloudKit
  entitlement, `NSSupportsLiveActivities=true`, 캘린더·플래너·잠금 화면 widget kind와
  Activity 타입 포함 여부를 검증한 뒤 App Store Connect 업로드에 성공했고 패키지 처리가
  시작됐다.
- Dynamic Island 축소형에서 긴 Task 제목을 제거하고 leading에 7pt 파란 활성 점과 누적
  진행 시간을 함께 배치했다. trailing은 비워 폭 증가를 줄였으며 iOS TestFlight build 46은
  Release 패키지 테스트 327개, 서명 archive, 앱·위젯 build number, App Group·CloudKit
  entitlement와 `NSSupportsLiveActivities=true` 검증을 통과한 뒤 App Store Connect 업로드에
  성공했고 패키지 처리가 시작됐다.
- build 46 실기기 확인을 반영해 Dynamic Island compact의 leading에는 누적 진행 시간,
  trailing에는 7pt 파란 활성 점을 분리 배치했다. 모든 Live Activity 타이머를 숫자형 count-up
  interval로 교체해 잠금 화면에서도 `hours`, `minutes` 없이 `5:09:27`처럼 표시한다. iOS
  TestFlight build 47은 Release 패키지 테스트 327개, Debug 빌드, 서명 archive와 앱·위젯
  build number, App Group·CloudKit entitlement, `NSSupportsLiveActivities=true` 검증을 통과한
  뒤 App Store Connect 업로드에 성공했고 패키지 처리가 시작됐다.
- build 47의 iPhone·macOS 표시를 확인한 뒤 기존 Live Activity UI 타입과 타이머 표현식을
  폐기하고 새 구조로 재작성했다. compact에는 leading 숫자 시간과 trailing 6pt 활성 점만
  두고 제목·Spacer·고정 너비·수동 여백·그림자를 전혀 사용하지 않는다. 모든 시간은
  시스템 stopwatch 최대 3칸으로 표시했다. iOS Debug·Release simulator와 Release 패키지
  테스트 327개를 통과했다. 앱·위젯 build number 48, App Group·CloudKit entitlement와
  `NSSupportsLiveActivities=true`를 서명 archive에서 검증한 뒤 App Store Connect 업로드에
  성공했고 패키지 처리가 시작됐다.
- build 48 실기기 확인 후 compact와 minimal 시간을 숫자 전용 discrete format으로 추가
  축소했다. 1시간 미만에는 `mm:ss`, 1시간 이상에는 `h:mm`으로 전환하고, 확장형은 시스템
  stopwatch 최대 3칸을 유지한다. iOS Debug·Release simulator와 Release 패키지 테스트
  327개를 통과했다. 앱·위젯 build number 49, App Group·CloudKit entitlement와
  `NSSupportsLiveActivities=true`를 서명 archive에서 검증한 뒤 App Store Connect 업로드에
  성공했고 패키지 처리가 시작됐다.
- build 49 실기기에서 사용자 정의 discrete format이 회색 대시로 redaction되는 것을
  확인했다. 사용자 정의 format을 제거하고 iOS가 직접 갱신하는 시스템 stopwatch를 사용하되
  `00:00` 다섯 글자 너비로 clipping하도록 변경했다. 1시간 미만 시스템 출력 `mm:ss`는
  그대로 보이고, 1시간 이상 `hh:mm:ss`는 앞의 `hh:mm`만 표시한다. 동일 SwiftUI 조합의
  로컬 이미지에서 `05:16` 표시를 확인했고 iOS Debug·Release simulator와 Release 패키지
  테스트 327개를 통과했다. 앱·위젯 build number 50, App Group·CloudKit entitlement와
  `NSSupportsLiveActivities=true`를 서명 archive에서 검증한 뒤 App Store Connect 업로드에
  성공했고 패키지 처리가 시작됐다.
- build 50 실기기에서는 숨은 기준 문자열의 overlay 안에 배치한 시스템 시간도 표시되지
  않았다. overlay·clipping을 모두 제거하고 compact와 minimal에는 시스템
  `durationOffset + hourMinute` Text 하나만 직접 배치했다. 제한 렌더링에서의 안정성을 위해
  compact와 minimal은 항상 `h:mm`, 잠금 화면과 확장형은 기존 `h:mm:ss`를 사용한다. 동일
  시스템 Text의 로컬 이미지에서 `5:16` 표시를 확인했고 iOS Debug·Release simulator 빌드를
  통과했다. Release 패키지 테스트 327개와 서명 archive 생성도 통과했으며 앱·위젯 build
  number 51, App Group·CloudKit entitlement와 `NSSupportsLiveActivities=true`를 검증한 뒤
  App Store Connect 업로드에 성공했고 패키지 처리가 시작됐다.
- build 51 실기기 확인 후 Dynamic Island compact의 trailing 활성 점을 제거했다. compact는
  leading의 시스템 `h:mm` 시간 하나만 표시하며, 잠금 화면과 확장형의 활성 점은 유지한다.
  iOS Debug·Release simulator 빌드와 Release 패키지 테스트 327개를 통과했다. 앱·위젯 build
  number 52, App Group·CloudKit entitlement와 `NSSupportsLiveActivities=true`를 서명
  archive에서 검증한 뒤 App Store Connect 업로드에 성공했고 패키지 처리가 시작됐다.
- build 52 실기기에서 시간만 표시해도 compact 캡슐 폭이 유지되는 것을 확인했다. Apple HIG의
  iOS 규격상 compact 전체 폭은 기기별 230pt 또는 250pt이고, leading·trailing은 한 쌍으로
  표시되므로 빈 trailing으로 외곽 폭을 줄일 수 없다. 후속 소스는 별도 padding 없이 leading에
  시스템 `h:mm`, trailing에 짧은 `완료/전체` 수치를 배치해 고정 영역을 균형 있게 사용한다.
  minimal은 여러 Live Activity가 함께 표시될 때를 위해 시간 하나만 유지한다. compact와
  minimal 전용 Preview를 추가했으며 iOS Debug·Release simulator 빌드와 Release 패키지
  테스트 327개를 통과했다. 앱·위젯 build number 53, App Group·CloudKit entitlement와
  `NSSupportsLiveActivities=true`를 서명 archive에서 검증한 뒤 App Store Connect 업로드에
  성공했고 패키지 처리가 시작됐다.
- build 53 실기기에서 leading `h:mm`, trailing `완료/전체` 조합이 여전히 크게 보이는 것을
  확인했다. Apple Clock 앱 내부 코드는 공개되어 있지 않지만 공식 Live Activities 예제의
  `leading 심볼 + trailing 동적 값` 구조와 제공된 Stopwatch 화면을 기준으로 후속 소스는
  leading에 padding·배경 없는 주황색 `stopwatch.fill`, trailing에 주황색 시스템 `h:mm`만
  배치한다. 진행률은 확장형과 잠금 화면에서 계속 제공하고 minimal은 시간 단독 표현을 유지한다.
  iOS Debug·Release simulator 빌드와 Release 패키지 테스트 327개를 통과했다. 앱·위젯 build
  number 54, App Group·CloudKit entitlement와 `NSSupportsLiveActivities=true`를 서명
  archive에서 검증한 뒤 App Store Connect 업로드에 성공했고 패키지 처리가 시작됐다.
- build 54 실기기에서 Stopwatch형 compact도 최대 폭에 가깝게 표시되는 것을 확인했다. 폭
  원인을 분리하기 위해 후속 소스의 Dynamic Island expanded에서 제목·진행률·완료·다음
  버튼을 모두 제거하고 점과 시간만 유지한다. compactLeading은 6pt 파란 점,
  compactTrailing은 시스템 `h:mm`만 사용하며 두 뷰와 minimal 시간에 `.fixedSize()`를
  적용한다. 센서에 인접한 compact content margin은 0으로 줄이고 잠금 화면 구성은 유지한다.
  iOS Debug·Release simulator 빌드와 Release 패키지 테스트 327개를 통과했다. 앱·위젯 build
  number 55, App Group·CloudKit entitlement와 `NSSupportsLiveActivities=true`를 서명
  archive에서 검증한 뒤 App Store Connect 업로드에 성공했고 패키지 처리가 시작됐다.
- build 55 실기기에서는 compact 시간이 사라지고 expanded 시간이 대시로 깨졌다. compact와
  expanded 모두에 공통으로 새로 적용된 `.fixedSize()`가 제한된 Dynamic Island의 제안 크기를
  무시해 실시간 `TimeDataSource`가 잘리는 회귀로 판단했다. 후속 소스는 모든 Dynamic Island
  시간과 점의 `.fixedSize()`를 제거하고 compact별 강제 content margin도 제거해 시스템 기본
  레이아웃 제안을 복원한다. Dynamic Island에는 계속 점과 시간만 유지한다.
- 후속 simulator 교차검증에서 폭의 직접 원인은 숨긴 Task 제목이나 expanded 콘텐츠가 아니라,
  동적 시스템 stopwatch가 compact trailing에 큰 이상 너비를 제안하는 것이었다. 시스템
  stopwatch 갱신은 유지하고 시간 뷰에만 32pt 숫자 슬롯을 부여했다. expanded와 잠금 화면은
  56pt 슬롯을 사용하며 `.fixedSize()`와 사용자 정의 compact margin은 사용하지 않는다.
  iPhone 17 Pro(iOS 26.5) simulator에서 긴 Task 제목으로 compact 약 189pt, `MM:SS` 초 단위
  갱신, expanded의 점·시간 단독 표시, 잠금 화면 제목·`완료/전체`·58×48pt 완료/다음 버튼을
  확인했다. `다음`은 새 Task와 `00:00` 타이머로 교체되고 `완료`는 Activity를 종료했다.
  저휘도 Always On에서는 시스템이 초를 `--`로 낮추고 화면을 깨우면 숫자 초가 즉시 복원된다.
  Debug·Release iOS simulator 빌드, 공통 테스트 328개와 iPhone launch smoke test도 통과했다.
  이 변경을 포함한 iOS TestFlight build 56은 Release 패키지 테스트 327개와 서명 archive
  생성을 통과했다. 앱·위젯 build number, App Group·CloudKit entitlement와
  `NSSupportsLiveActivities=true`를 검증한 뒤 App Store Connect 업로드에 성공했고 패키지
  처리가 시작됐다.
- 실제 iPhone의 잠금 인증·Always On·Dynamic Island와 iPad 잠금 화면, macOS 시스템 표현은
  후속 실기기 인수 항목으로 남긴다.
- build 56 실기기에서 1시간 이상 경과 시간이 `7h…`로 잘리고 시스템 stopwatch의 초가 저휘도
  상태에서 `--`로 바뀌는 것을 확인했다. 후속 소스는 1초 주기의 숫자 포맷으로 교체해 1시간
  미만은 `MM:SS`, 1시간 이상은 `H:MM:SS`로 직접 렌더링한다. Dynamic Island compact는
  leading의 46pt 이내 Task 제목과 trailing의 50pt 시간을 사용하고, 잠금 화면과 expanded는
  72pt 시간을 사용한다. iPhone 17 Pro(iOS 26.5) simulator의 7시간 fixture에서 compact 제목
  말줄임과 초 단위 증가, 잠금 화면 `7:21:39`를 확인해 단위 문구와 `--`를 모두 제거했다.
  잠금 화면 오른쪽은 테마 색상의 48×48pt `→`, `✓` 순서로 구성했다. Live Activity state에
  호환 가능한 선택형 `themeID`를 추가해 앱 테마를 전달하고, 정적 잠금 위젯도 full-color
  렌더링에서 같은 테마를 사용한다. 모든 테마 preset은 시스템 라이트/다크 모드와 무관하게
  하나의 고정 팔레트와 다크 표현 모드를 사용한다. 시스템 라이트 모드의 iPhone 17 Pro
  simulator에서 8개 preset을 모두 순회해 배경·카드·상태·강조색·텍스트 대비를 확인하고,
  시스템 다크 모드에서도 동일한 팔레트가 유지되는 것을 재확인했다. Debug 328개·Release
  327개 테스트와 iOS/macOS Debug·Release 전체 빌드를 통과했다. 앱·위젯 build 57, App Group,
  CloudKit entitlement와 `NSSupportsLiveActivities=true`를 서명 archive에서 검증한 뒤 App
  Store Connect 업로드에 성공했고 패키지 처리가 시작됐다.
- build 57 후속 점검에서 시스템 모드 고정을 어두운 팔레트로만 처리해 원본 테마보다 앱
  전체가 과도하게 어두워지는 문제를 확인했다. 시스템 라이트/다크 설정과 무관하게 각
  preset의 밝은 고유 팔레트를 사용하도록 공통 선택 함수를 바로잡고, iOS/macOS 시스템
  control 표현도 밝은 모드로 고정했다. iPhone 17 Pro simulator에서 Apple System, Maroon
  Ember, Navy Blush, Plum Night, Rose Lilac, Forest Cream, Teal Paper, Solar Berry를 모두
  순회해 배경·카드·상태·강조색을 확인했고 공통 328개 테스트가 통과했다.
- 밝은 테마 후속 조정에서 기존 호환 ID는 유지하면서 화면 팔레트와 표시 이름을 Clean
  White, Peach Cream, Sky Blue, Lavender Cloud, Blush Pink, Mint Cream, Aqua Mist, Sunny
  Apricot으로 재구성했다. 모든 화면은 흰 panel을 기준으로 옅은 파스텔 배경과 상태색을
  사용한다. iOS 13~14 시기의 grouped background, 흰 카드, system blue 조합을 재현한
  `Apple 2020` preset도 별도 추가했다. iPhone 17 Pro simulator에서 Sky Blue, Blush Pink,
  Apple 2020을 시각 확인했고 공통 330개 테스트와 iOS/macOS Debug 빌드를 통과했다.
- 위 변경과 단일 완료 입력 보호, 계획 Task `▶`를 포함한 앱·위젯 build 58은 Release 패키지
  테스트 329개와 iOS Release 빌드를 통과했다. 서명 archive에서 앱·위젯 build number,
  App Group·CloudKit entitlement, `NSSupportsLiveActivities=true`와 Activity 타입을 확인한 뒤
  App Store Connect 업로드에 성공했고 패키지 처리가 시작됐다.
- 고정 다크 테마 Midnight Blue와 Charcoal Rose를 추가하고 테마 선택 화면을 밝은 테마와
  다크 테마로 구분했다. 선택한 테마에 따라 iOS/macOS 시스템 표현도 각각 light/dark로
  고정된다. 두 테마를 iPhone 17 Pro simulator에서 확인하고 Release 패키지 테스트 330개와
  iOS Release 빌드를 통과했다. 앱·위젯 build 59의 서명·공유 권한·Live Activity 선언을
  검증한 뒤 App Store Connect 업로드에 성공했고 패키지 처리가 시작됐다.
- `doing` Task가 둘 이상일 때 잠금 화면 `✓` 한 번이 갱신된 다음 Task의 `✓`에도 연속
  적용될 수 있는 전환 경쟁 상태를 막기 위해 성공한 잠금 화면 액션 뒤 1초 동안 후속
  액션을 무시한다. Live Activity는 종료하지 않고 다음 대표 `doing` 세션으로 갱신한다.
  별도 단위 테스트 3개와 simulator의 `진행 2 / 완료 0 → 진행 1 / 완료 1` 흐름으로
  단일 완료만 적용됨을 확인했다. 계획 Task용 정적 잠금 위젯은 우측 `▶`를 명확히 표시해
  기존 `todo → doing` Intent를 계속 사용한다.
- 최종 build 60은 Debug 331개·Release 330개 SwiftPM 테스트, 모바일 테스트 16개,
  접근성·기록 이동·기본 글자 크기 UI smoke와 iOS/macOS Debug·Release 전체 빌드를
  통과했다. 서명 archive에서 앱·위젯 build 60, App Group·CloudKit 권한,
  `NSSupportsLiveActivities=true`와 Activity 타입을 확인한 뒤 iOS와 macOS 모두
  App Store Connect에 업로드했고 package 처리가 시작됐다.

## 1. 목표

기존 읽기 전용 `PlanBase 오늘` 잠금 화면 위젯을 Task 실행 흐름 중심으로 개편하고,
오늘 이벤트 인라인 위젯과 진행 중 Task 전용 Live Activity를 추가한다.

사용자는 잠금 화면에서 다음 흐름을 수행할 수 있어야 한다.

1. 오늘 CalendarEvent 제목을 한 줄로 확인한다.
2. 오늘 진행 중인 Task를 확인한다.
3. 진행 중인 Task가 없으면 첫 번째 계획 Task를 진행 상태로 전환한다.
4. 진행 중인 Task가 있을 때만 Live Activity로 진행률을 확인하고 완료하거나 다음 Task로
   전환한다.
5. `+` 버튼으로 앱의 오늘 Task 빠른 입력 위치를 바로 연다.

## 2. 확정 제품 결정

### 2.1 잠금 화면 구성

같은 `PlanBase 오늘` widget configuration이 family에 따라 서로 다른 역할을 맡는다.

```text
       📅 팀 미팅 · +1          accessoryInline

            10:21

┌─────────────────────────┐  ┌─────┐
│ ● 기획서 작성       3/4 │  │  ＋ │
└─────────────────────────┘  └─────┘
 accessoryRectangular       accessoryCircular

┌──────────────────────────────┐
│ 기획서 작성       [✓ 완료] [→ 다음] │
│ 3/4                          │
└──────────────────────────────┘
 진행 중 Task가 있을 때만 나타나는 Live Activity
```

- 월간 캘린더는 잠금 화면에 표시하지 않는다.
- 일정 시각과 Task 타이머는 표시하지 않는다.
- 배경화면 이미지 생성과 단축어 자동화는 사용하지 않는다.
- `3/4`는 오늘 대상 Task 중 완료 Task 수/전체 Task 수다.
- 정적 위젯과 Live Activity가 동시에 보일 때 같은 진행 수치를 표시한다.
- Task 제목은 한 줄 말줄임 처리하고, 숫자보다 제목에 우선적으로 폭을 배정한다.

### 2.2 오늘 이벤트 인라인 위젯

시계 위 `accessoryInline`은 CalendarEvent 전용으로 사용한다.

```text
이벤트 1개:   📅 팀 미팅
이벤트 여러 개: 📅 팀 미팅 · +2
이벤트 없음:   일정 없음
```

- 일정 시각은 표시하지 않는다.
- 여러 날 이벤트도 오늘 날짜가 범위에 포함되면 오늘 이벤트로 계산한다.
- 첫 이벤트는 기존 CalendarEvent 결정적 정렬을 따른다.
- 추가 개수는 `totalEventCount(onDayKey:)`를 기준으로 계산한다. count는 있지만 제한된
  snapshot에 제목이 없으면 잘못된 빈 상태 대신 `일정 N개`를 표시한다.
- 탭하면 `planbase://calendar?scope=today`로 캘린더의 오늘 화면을 연다. snapshot의 날짜를
  URL에 고정하지 않고 앱이 route를 처리하는 시점의 오늘로 해석해 자정 timeline 지연에도
  전날을 열지 않는다.
- 이벤트 제목에는 `privacySensitive()`를 적용하고 VoiceOver에는 전체 이벤트 수를 함께
  제공한다.
- privacy redaction 상태에서는 제목 대신 `일정 N개`처럼 개수만 남긴다.

### 2.3 Task 직사각형 위젯

`accessoryRectangular`은 오늘의 현재 Task 또는 다음 계획 Task 하나만 표시한다.

진행 중 Task가 있을 때:

```text
● 기획서 작성       3/4
```

진행 중 Task가 없고 계획 Task가 있을 때:

```text
▶ 기획서 작성       3/4
```

오늘 대상 Task가 없을 때:

```text
오늘 할 일 없음
```

오늘 Task를 모두 완료했을 때:

```text
✓ 오늘 완료          4/4
```

- `●`는 현재 진행 중인 Task를 뜻한다.
- `▶`는 해당 계획 Task를 `todo → doing`으로 변경하는 App Intent 버튼이다.
- 진행 중 Task가 여러 개면 기존 order, 제목, ID 정렬의 첫 Task 하나만 대표로 표시한다.
- 진행 중 Task가 없으면 같은 정렬의 첫 `todo` Task를 표시한다.
- `todo`와 `doing`은 없지만 오늘 `done`이 있으면 완료 상태와 `전체/전체`를 표시한다.
- 제목은 `.privacySensitive()`를 적용한다.
- 제목 영역을 탭하면 오늘 보드로 이동한다.
- root의 `widgetURL`은 하나만 두고 `▶`만 별도 App Intent `Button`으로 구성한다. 갱신 대기
  중인 제목과 상태에는 `invalidatableContent(_:)`를 제한적으로 적용한다.
- `▶` 실행은 잠금 상태에서 시스템 인증이 필요할 수 있으며, 인증 실패나 저장 실패 때
  snapshot을 성공 상태로 미리 바꾸지 않는다.
- privacy redaction 상태에서는 제목 대신 `진행 중` 또는 `시작 가능`을 표시하고 진행
  수치는 유지한다.

### 2.4 원형 빠른 추가 위젯

`accessoryCircular`은 숫자 요약 대신 `plus` 심볼 하나만 표시한다.

- 탭하면 `planbase://board?scope=today&action=new-task`를 연다.
- snapshot이 누락·손상·만료돼도 생성 동작은 데이터 표시와 무관하므로 `+`를 유지한다.
- 앱은 오늘 보드로 이동하고 기존 `BoardQuickAdd` 입력란에 포커스를 준다.
- 잠금 화면 안에서 직접 텍스트를 입력하거나 빈 Task를 미리 생성하지 않는다.
- 실제 저장은 사용자가 제목을 입력하고 기존 추가 동작을 실행할 때
  `PersistenceCommandService.perform`을 사용한다.

### 2.5 진행 중 Task 전용 Live Activity

Live Activity는 오늘 대상 `doing` Task가 있을 때만 존재한다.

```text
┌──────────────────────────────┐
│ 기획서 작성         [→] [✓] │
│ ● 1:28:34        3/4        │
└──────────────────────────────┘
```

- 왼쪽: 현재 대표 `doing` Task 제목, 활성 점, 숫자형 누적 진행 시간과 오늘 Task `완료/전체`
- 오른쪽: 각각 48×48pt의 테마 색상 `→`, `✓` 버튼
- 진행 막대와 버튼 텍스트는 제거하고 제목·진행 수치와 직접 조작 영역을 분리한다.
- 일정, 월간 캘린더, 시작 시각과 남은 시간은 넣지 않는다.
- 높이는 최소 표현인 약 84~96pt를 목표로 하고 내용 때문에 160pt까지 불필요하게 늘리지
  않는다.
- 제목과 상태는 잠금 화면, Always On, 저휘도에서 읽을 수 있어야 한다.
- 제목에는 `privacySensitive()`를 적용하고 redaction 상태에서는 `진행 중인 작업`으로
  대체한다.
- 버튼은 각각 `현재 작업 완료`, `다음 작업 시작` 접근성 레이블을 제공한다.

상태별 수명주기는 다음과 같다.

```text
오늘 doing 없음
  → Live Activity 없음

앱 또는 위젯에서 todo → doing
  → Live Activity 시작

doing Task 제목·진행률 변경
  → 기존 Live Activity 갱신

✓ 완료 후 다른 doing 존재
  → 대표 doing Task로 Live Activity 갱신

✓ 완료 후 doing 없음
  → Live Activity 종료

doing → todo, 삭제, 보관, 다른 날짜로 이동 후 doing 없음
  → Live Activity 종료
```

하나의 PlanBase Live Activity만 유지한다. 중복 Activity가 발견되면 대표 하나를 남기고
나머지를 종료한다.

#### Dynamic Island 적응형 표현

```text
최소형:  07:20
축소형:  작업명                    07:20
확장형:  ● 07:20
```

- 최소형은 제한된 폭에서 최대 2필드의 경과 시간만 표시한다.
- 축소형은 leading에 46pt 이내의 현재 Task 제목, trailing에 50pt 숫자형 누적 진행 시간을
  표시한다. 제목은 한 줄 말줄임 처리하고 진행률·버튼은 넣지 않는다.
- 누적 진행 시간은 날짜 상대 표현이 아니라 숫자형 시간 format을 사용해 잠금 화면과
  Dynamic Island에서도 `hours`, `minutes` 같은 단위 문구 없이 1시간 미만 `MM:SS`, 1시간
  이상 `H:MM:SS` 형태로 표시한다.
- 확장형도 점과 시간만 유지한다. 제목·완료 수치·완료/다음 버튼은 조작하기 쉬운 잠금 화면
  Live Activity에서 제공한다.
- 임의 이미지의 지속 프레임 애니메이션은 사용하지 않는다. 경과 시간은 직접 만든 숫자
  포맷으로 렌더링해 저휘도에서도 초 자리를 `--`로 대체하지 않는다. 다만 Always On에서의
  실제 갱신 빈도는 iOS가 낮출 수 있다.

### 2.6 Live Activity 버튼 의미

- `✓`: 현재 Task를 `done`으로 변경한다.
- `→`: 현재 Task를 `todo`로 되돌린다. 다른 오늘 `doing` Task가 이미 있으면 그것을 다음
  대표로 사용하고, 없을 때만 첫 오늘 `todo` Task를 `doing`으로 변경한다.
- 다른 `doing`과 `todo`가 모두 없으면 `→`를 숨긴다.
- `✓` 후 계획 Task를 자동으로 진행시키지는 않는다. 사용자가 `▶` 또는 `→`로 명시적으로
  시작해야 한다.
- 예정된 `reminderAt`이 남은 Task는 기존 완료 확인을 우회하지 않는다. 이 경우 `✓`는
  App Intent 버튼 대신
  `planbase://board?scope=today&action=confirm-completion&task=<UUID>`를 여는 `Link`로
  렌더링한다. 앱은 현재 Task를 다시 fetch한 뒤 기존 완료 확인 alert를 표시한다.
- 두 저장 동작은 모두 앱 프로세스의 `PersistenceCommandService.perform` 안에서
  `TaskLifecycleService.applyStatus`를 사용한다.
- `✓` 저장이 성공한 뒤에만 기존 `TaskNotificationScheduler`의 해당 Task pending 알림을
  취소한다.

## 3. 오늘 Task 집계 규칙

이월함 제외 원칙을 정적 위젯과 Live Activity에 동일하게 적용한다.

오늘 대상 Task 조건:

1. `supersededAt == nil`
2. `archivedAt == nil`
3. `plannedDayKey == 오늘`
4. 상태가 `todo`, `doing`, `done` 중 하나

따라서 과거 날짜에 남아 있는 이월 Task는 표시·집계·Live Activity 대상에서 제외한다.
사용자가 이월 Task를 오늘로 옮겨 `plannedDayKey == 오늘`이 되면 즉시 포함한다.

진행률 계산:

```text
전체 = 오늘 todo + doing + done
완료 = 오늘 done
진행률 = 완료 / 전체
```

- 전체가 0이면 진행 수치를 숨긴다.
- 완료 수는 오늘 대상 Task 기준으로 계산해 과거 이월 Task를 오늘 완료했다는 이유만으로
  분모 없이 완료 수에 추가하지 않는다.
- 같은 논리 ID의 CloudKit transient 중복은 기존 `updatedAt`, `instanceID` 대표 선택 규칙을
  유지한다.

## 4. 데이터·저장 경계

### 4.1 SwiftData와 snapshot

- 현재 `EasyTaskSchemaV8` 모델을 그대로 사용하고 새 schema나 migration을 추가하지 않는다.
- App Group 파일 이름, App Group ID, CloudKit container와 기존 widget kind를 변경하지
  않는다.
- 정적 위젯은 계속 App Group의 `CalendarWidgetSnapshot`만 읽고 SwiftData/CloudKit을 직접
  열지 않는다.
- 현재 snapshot v5의 `LockScreenWidgetDaySummary`,
  `plannerTaskPreviewsByDayKey`, CalendarEvent snapshot으로 필요한 읽기 데이터를 구성할 수
  있으므로 JSON schema version은 올리지 않는 것을 기본으로 한다.
- `LockScreenWidgetRules.doneCount`는 이월 제외 원칙과 진행률 분모가 일치하도록 오늘 계획
  Task 기준으로 재정의하고 테스트를 갱신한다.

가용성은 하나의 공통 화면 상태로 묶지 않고 family별로 판단한다.

- Inline: CalendarEvent snapshot coverage가 유효하면 Task summary 실패와 무관하게 표시
- Rectangular: Task summary와 planner preview coverage가 모두 유효할 때 표시
- Circular: snapshot 상태와 무관하게 항상 빠른 추가 표시
- 미래 snapshot schema는 데이터를 해석하는 Inline/Rectangular에서 업데이트 필요 표시

### 4.2 App Intent 저장 경계

위젯과 Live Activity 버튼은 원본 저장소를 Widget Extension에서 직접 수정하지 않는다.

1. 상태를 변경하는 `▶`, `✓`, `→`는 `LiveActivityIntent`로 정의해 앱 프로세스에서
   실행한다.
2. 논리 Task ID로 활성 후보를 bounded fetch하고 `updatedAt`, `instanceID` 순서로 현재 대표
   레코드를 선택한다. 기존 `fetchLimit = 1` descriptor의 unique 가정에 의존하지 않는다.
3. 현재 상태와 오늘 대상 여부를 다시 검증한다.
4. `PersistenceCommandService.perform`에서 상태 전환과 진행 이벤트 기록을 함께 저장한다.
5. 성공 후 widget snapshot을 다시 발행하고 timeline과 Live Activity를 갱신한다.
6. 실패하면 rollback하고 기존 UI 상태를 유지한다.

앱 프로세스 intent가 현재 `ModelContainer`를 안전하게 재사용할 수 있도록 앱 시작 시
container를 등록하는 작은 runtime/coordinator 경계를 둔다. 별도 App Group 저장소나 command
queue는 만들지 않는다.

Intent 실행 시 SwiftUI root observer가 활성 상태라고 가정하지 않는다. intent의
`perform()`이 저장 완료 후 snapshot 발행과 Live Activity coordinator 호출을 직접 await한
뒤 반환한다.

앱과 extension이 함께 컴파일하는 Intent 타입은 parameter와 명령 프로토콜만 포함한다.
SwiftData, `ModelContainer`, snapshot publisher와 Activity coordinator를 사용하는 concrete
executor는 iPhone 앱 타겟에만 두고 앱 프로세스 dependency로 등록한다. Widget Extension에는
원본 저장소 접근 코드가 링크되지 않게 한다.

`→`의 다음 후보는 current Task 상태를 바꾸기 전에 결정하고 current logical ID를 제외한다.
Intent 실행 시 상태가 달라졌으면 후보를 다시 계산하며, stale payload의 Task를 임의로
전환하지 않는다.

### 4.3 Live Activity 상태 payload

Activity attributes는 Activity 동안 변하지 않는 값만 보관한다. `→` 동작이나 여러 doing
Task의 대표 교체로 현재 Task와 Task 진행 세션이 바뀔 수 있으므로 두 값 모두 immutable
attributes에 넣지 않고 갱신 가능한 ContentState에 둔다.

```text
PlanBaseTaskActivityAttributes
  activityID
  dayKey

ContentState
  taskSessionID
  taskID
  title
  completedCount
  totalCount
  hasNextTask
  requiresCompletionConfirmation
  elapsedTimerStartedAt (wire key: updatedAt)
```

- 원본 Task 배열, 메모, 태그, 체크리스트 제목은 payload에 넣지 않는다.
- `elapsedTimerStartedAt`은 과거 완료 구간과 현재 진행 구간을 합친 누적 시간을 시스템 timer
  text로 표시하기 위한 기준 시각이다. build 44 진행 중 Activity와의 decode 호환성을 위해
  wire key는 기존 `updatedAt`을 유지한다.
- 서버/APNs push 업데이트는 첫 버전에서 제외하고 로컬 앱/intent 변경으로만 갱신한다.
- 사용자가 Live Activities를 비활성화했거나 시스템이 표시하지 못해도 정적 위젯과 앱 기능은
  그대로 동작해야 한다.

Task 세션은 현재 `TaskProgressEvent.started`의 Task ID와 시작 시각으로 식별한다. 기존
데이터의 doing Task처럼 started event가 없는 경우에는 논리 Task ID 기반 `legacy-doing`
세션 ID를 한 번만 사용한다. Activity 시작에 성공했거나 사용자가 표시를 거부·종료한 세션
ID는 기기 로컬의 bounded receipt store에 기록한다.

- 새 `todo → doing` 전환은 새 Task 세션이므로 Activity를 시작할 수 있다.
- 이미 처리한 세션의 Activity가 시스템 종료 또는 사용자 제거로 사라지면 generic app
  launch, `scenePhase.active`, snapshot refresh가 같은 Activity를 다시 만들지 않는다.
- 활성 Activity가 남아 있으면 app launch와 data change에서 내용만 update/end한다.
- `→`로 Task 세션이 바뀌어도 오늘 Activity 하나의 ContentState만 교체한다.
- receipt는 CloudKit에 동기화하지 않는 기기별 UI 상태이며 최근 세션만 bounded하게
  보관한다.

## 5. 플랫폼별 표현

### 5.1 iPhone 우선

- 잠금 화면: 위 확정 레이아웃 전체를 구현한다.
- Dynamic Island compact: leading에 말줄임한 Task 제목, trailing에 누적 진행 시간을 표시한다.
- Dynamic Island minimal: 누적 진행 시간만 표시한다.
- Dynamic Island expanded: 파란 활성 점과 누적 진행 시간만 표시한다.
- Dynamic Island가 없는 기기도 잠금 화면 Live Activity가 동일 의미를 유지해야 한다.

### 5.2 iPad

- iOS 공통 accessory family와 Live Activity state를 재사용한다.
- 더 넓은 폭에서도 정보를 추가하지 않고 제목의 말줄임 여유만 늘린다.
- Stage Manager, 가로·세로, 잠금 화면 preview를 확인한다.

### 5.3 macOS

- iPhone과 iPad 승인 뒤 ActivityKit이 제공하는 macOS 표현을 검증한다.
- macOS 때문에 iPhone payload나 정보 계층을 확장하지 않는다.
- 네이티브 macOS에서 지원되지 않는 잠금 화면 accessory UI를 별도로 흉내 내지 않는다.
- macOS 지원이 시스템 전달 범위에 한정되면 그 사실을 출시 문서에 명시한다.

## 6. 구현 단계

### Phase 1. 공통 표시 규칙과 테스트

- 오늘 대상 Task, 완료/전체 진행률, 대표 doing/todo, 다음 Task 선택 규칙을 공통 서비스로
  고정한다.
- 이월함 제외와 오늘 이동 포함 규칙을 기존 planner preview와 일치시킨다.
- 오늘 이벤트의 첫 제목과 `+N` 표시 규칙을 테스트한다.

완료 조건:

- 위젯과 Live Activity가 같은 fixture에서 같은 `3/4`를 만든다.
- 이월 Task는 오늘로 이동하기 전까지 집계되지 않는다.
- 여러 doing Task와 CloudKit transient 중복에서도 대표 결과가 결정적이다.

### Phase 2. 딥링크와 오늘 Task 빠른 입력

- `calendar?scope=today` 생성·파싱과 처리 시점 오늘 해석을 추가한다.
- Calendar route는 `.today`와 `.day(dayKey)`를 구분하는 타입으로 확장하고 기존
  `calendar?date=yyyy-MM-dd` 링크 동작을 유지한다.
- `board?scope=today&action=new-task` 생성·파싱을 추가한다.
- reminder 완료 확인용
  `board?scope=today&action=confirm-completion&task=<UUID>`를 추가한다.
- 앱 root가 오늘 보드 선택과 quick-add 포커스 요청을 전달한다.
- 완료 확인 route는 오늘 보드에서 현재 Task를 다시 fetch하고 기존
  `requestTaskStatusChange` 확인 흐름으로 전달한다.
- cold/warm/background 상태에서 같은 결과를 검증한다.

완료 조건:

- 원형 `+` 탭 후 빈 Task가 생성되지 않고 입력란만 활성화된다.
- Inline은 entry 생성 날짜가 지나도 처리 시점의 오늘 캘린더를 연다.
- 잘못되거나 모호한 scope/action/task/date 조합은 거부된다.

### Phase 3. 잠금 화면 accessory UI 개편

- Inline을 오늘 CalendarEvent 제목 전용으로 변경한다.
- Rectangular를 한 줄 Task 제목·진행률·`▶` 상태로 변경한다.
- Circular를 `+` 전용으로 변경한다.
- 기존 entry의 단일 availability 판단을 event/task/action family별 상태로 분리한다.
- 정상 빈 상태, 갱신 필요, 앱 업데이트 필요 표현을 family별로 유지한다.

완료 조건:

- 일반 iPhone 약 160×72pt rectangular와 72×72pt circular에서 잘리지 않는다.
- 기본 글자 크기를 기존 11~12pt보다 키우고 제목은 한 줄 말줄임 처리한다.
- wallpaper tint, vibrant, Always On, privacy redaction에서 읽을 수 있다.
- Task query 실패가 정상 CalendarEvent Inline을 가리지 않고, snapshot 실패가 Circular `+`를
  가리지 않는다.

### Phase 4. Task 상태 App Intent

- `▶`, `✓`, `→` intent와 앱 프로세스 persistence runtime을 구현한다.
- 기존 Task 수명주기·알림 확인·진행 이벤트 기록을 재사용한다.
- 성공 후 snapshot/timeline reload, 실패 시 rollback을 검증한다.

완료 조건:

- Widget Extension이 SwiftData/CloudKit을 열지 않는다.
- 잠금 상태 인증 취소가 Task 상태를 변경하지 않는다.
- reminder가 남은 Task를 확인 없이 완료하지 않는다.

### Phase 5. ActivityKit 수명주기

- Activity attributes와 `ActivityConfiguration`을 추가한다.
- 앱 Info.plist에 Live Activity 지원 키를 추가한다.
- app start, dataChanged, scene active, CloudKit import 후 대표 doing Task를 재평가한다.
- 시작·갱신·종료·중복 정리 coordinator를 구현한다.
- Task 세션 receipt를 사용해 app start와 scene active는 기존 Activity의 update/end만
  수행하고 이미 처리한 세션을 재시작하지 않는다.

완료 조건:

- 오늘 doing Task가 없으면 Live Activity가 존재하지 않는다.
- 앱 또는 `▶`에서 doing이 시작되면 Live Activity가 시작된다.
- 현재 Task와 진행률 변경이 기존 Activity에 반영된다.
- 마지막 doing이 사라지면 Activity가 종료된다.
- 사용자가 제거했거나 시스템이 끝낸 같은 Task 세션을 앱 활성화만으로 다시 시작하지
  않는다.

### Phase 6. 플랫폼·출시 검증

- build 56 실기기 피드백과 build 60의 자동 회귀·서명 archive·TestFlight 업로드까지
  완료했다.
- 최종 iPhone 실기기에서 잠금 인증, Always On, Dynamic Island, cold/warm route를 확인한다.
- iPad 레이아웃을 확인하고 macOS 시스템 표현의 지원 범위를 기록한다.
- iPad/macOS 인수 결과와 build 60의 실제 TestFlight 설치 결과를 기록한다.

## 7. 예상 변경 파일

### 공통 코어

- `shared/Core/Services/LockScreenWidgetRules.swift`
  - 오늘 대상 완료율과 대표 Task 규칙 보완
- `shared/Core/Services/CalendarWidgetSnapshot.swift`
  - 기존 날짜 route를 보존한 calendar today, new-task, confirm-completion deep link
    생성·파싱
- `shared/Tests/LockScreenWidgetRulesTests.swift`
  - 이월 제외, 대표 Task, 진행률 테스트
- `shared/Tests/CalendarWidgetSnapshotTests.swift`
  - deep link action round-trip/거부 테스트

### iPhone 앱

- `mobile/App/PlanBaseMobileApp.swift`
  - calendar today/new-task/confirm-completion route, quick-add 포커스, Live Activity
    reconciliation 연결
- `mobile/App/Features/Board/MobileBoardView.swift`
- `mobile/App/Features/Board/MobileBoardComponents.swift`
  - 외부 quick-add 포커스 요청 수용
- `mobile/App/Infrastructure/TaskLiveActivityCoordinator.swift` 신규
  - Activity 시작·갱신·종료·중복 정리와 Task 세션 receipt
- `mobile/App/Infrastructure/PlanBaseTaskIntentRuntime.swift` 신규
  - 앱 프로세스 저장 명령과 container 경계
- `mobile/Configuration/PlanBase-iOS-Info.plist`
  - Live Activity 지원 선언

### Widget Extension

- `mobile/Widget/PlanBaseLockScreenWidget.swift`
  - Inline/Rectangular/Circular 역할과 family별 가용성 개편
- `mobile/Widget/PlanBaseTaskActivityAttributes.swift` 신규
  - 앱과 extension 양쪽 target membership
- `mobile/Widget/PlanBaseTaskLiveActivity.swift` 신규
  - Lock Screen/Dynamic Island ActivityConfiguration
- `mobile/Widget/PlanBaseTaskWidgetIntents.swift` 신규
  - `▶`, `✓`, `→` intent 정의
- `mobile/Widget/PlanBaseWidgetBundle.swift`
  - Live Activity configuration 등록
- `PlanBase.xcodeproj/project.pbxproj`
  - 신규 파일과 app/widget target membership

파일명과 분리는 구현 시 현재 Xcode target dependency를 확인해 조정할 수 있지만, app
process 저장과 extension 렌더링 경계는 유지한다.

## 8. 테스트 계획

### 공통 단위 테스트

1. 오늘 `todo`, `doing`, `done`으로 `3/4`를 정확히 만든다.
2. 과거 이월 Task는 제외하고 오늘로 옮기면 포함한다.
3. 대표 Task는 doing 우선, 없으면 todo이며 정렬이 결정적이다.
4. 완료 후 다음 doing이 있으면 대표 Task가 교체된다.
5. 전체 0일 때 ratio와 progress를 표시하지 않는다.
6. 오늘 Task가 전부 완료되면 `오늘 완료 4/4`를 표시한다.
7. 오늘 CalendarEvent 1개/여러 개/0개와 여러 날 이벤트 문구를 만든다.
8. event count는 있지만 제목이 제한된 snapshot에 없으면 `일정 N개`를 표시한다.
9. calendar today, new-task, confirm-completion deep link가 두 지원 scheme에서
   round-trip한다.
10. 모호하거나 잘못된 scope/action/task/date 조합을 거부한다.

### 저장·Intent 테스트

1. `▶`가 선택 Task만 `doing`으로 바꾸고 progress started event를 기록한다.
2. `✓`가 완료·완료 활동·progress stopped event를 하나의 transaction으로 저장한다.
3. reminder가 남은 Task는 직접 완료하지 않는다.
4. `→`가 현재 Task를 todo로 바꾸고, 기존 다른 doing을 우선하며 없을 때만 다음 todo를
   doing으로 원자적으로 바꾼다.
5. stale/superseded/다른 날짜 Task ID 요청을 거부한다.
6. 같은 논리 ID의 transient 중복에서 현재 대표만 결정적으로 선택한다.
7. 저장 실패가 rollback되고 성공 snapshot을 발행하지 않는다.

### Live Activity 테스트

ActivityKit 호출을 adapter protocol로 감싸 fake 구현으로 아래를 검증한다.

1. doing 없음 → 시작하지 않음
2. 첫 doing 생성 → 하나 시작
3. 같은 상태 재평가 → 중복 시작하지 않음
4. 제목·진행률 변경 → update
5. 대표 doing 변경 → 같은 Activity ContentState 교체
6. 마지막 doing 종료 → end
7. 중복 Activity 발견 → 대표 하나 외 종료
8. Live Activity 권한 비활성 → 정적 위젯과 저장 동작 유지
9. 이미 처리·제거된 Task 세션 + scene active → 재시작하지 않음
10. 새 todo → doing 세션 → 새 Activity 시작 가능

### Preview·실기기 인수

1. 긴 한글/영문/이모지 제목과 기본·큰 글자 크기
2. Inline/Rectangular/Circular gallery와 실제 잠금 화면
3. Dynamic Island compact/minimal/expanded
4. 잠금 인증 성공·취소와 reminder 완료 확인
5. privacy redaction, Always On, 저휘도, Light/Dark
6. 자정·시간대 변경과 App Group coverage 만료
7. CloudKit import 뒤 앱이 활성화됐을 때 snapshot/Activity 수렴
8. iPhone 우선 인수 후 iPad, 마지막으로 macOS 표현 확인
9. Task snapshot 오류 중에도 Inline event와 Circular `+`의 독립 동작 확인

검증 명령:

```bash
swift test
./scripts/verify-platform-builds.sh
```

ActivityKit의 compact/expanded/잠금 화면 렌더링과 완료·다음 수명주기는 simulator에서 직접
검증한다. Always On 저휘도, 잠금 인증과 실제 Dynamic Island 물리 규격은 실제 iOS 18 이상
기기 검증을 최종 게이트로 둔다.

## 9. 알려진 제약

- 잠긴 기기에서 위젯/Live Activity 버튼은 시스템 인증이 필요할 수 있다.
- CloudKit에서 다른 기기가 상태를 바꿔도 iPhone 앱이 import하고 실행 기회를 얻기 전에는
  로컬 Live Activity를 즉시 시작하거나 갱신할 수 없다. 첫 버전에는 서버 push-to-start를
  넣지 않는다.
- WidgetKit timeline 갱신 시점은 시스템이 조정하므로 intent 성공 직후 짧은 표시 지연이
  있을 수 있다.
- 사용자가 Live Activities를 비활성화하면 Live Activity는 표시하지 않으며 Task 위젯만
  사용한다.
- `doing` Task가 시스템의 Live Activity 권장 지속 시간보다 오래 유지돼도 Activity를
  반복 재시작해 상시 고정하지 않는다. 시스템이 종료한 뒤에는 정적 Task 위젯이 상태를
  계속 보여 주고, 다음 명시적 상태 전환 때 새 Activity를 시작한다.
- 제목은 잠금 화면에 노출될 수 있으므로 privacy 설정과 redaction을 실기기에서 확인해야
  한다.

## 10. 완료 기준

1. Inline에서 오늘 이벤트 제목과 추가 개수를 확인하고 오늘 캘린더로 이동한다.
2. Rectangular에서 대표 doing Task 또는 시작 가능한 첫 todo Task와 오늘 진행률을 본다.
3. Circular `+`가 오늘 보드 quick-add를 정확히 연다.
4. `▶`가 오늘 계획 Task를 진행 상태로 안전하게 변경한다.
5. Live Activity는 오늘 doing Task가 있을 때만 하나 존재한다.
6. 잠금 화면 Live Activity에 제목, 숫자형 누적 시간, 완료/전체, 큰 `→`·`✓` 버튼이 표시되고
   Dynamic Island는 compact 제목·시간과 expanded 점·시간만 표시된다.
7. `✓`, `→`가 기존 저장·알림·progress event 규칙을 우회하지 않는다.
8. 이월 Task는 오늘로 옮기기 전까지 모든 잠금 화면 집계에서 제외된다.
9. 정적 위젯은 App Group snapshot만 읽고 원본 저장소를 열지 않는다.
10. SwiftData/CloudKit schema와 배포 호환 식별자를 변경하지 않는다.
11. 관련 단위·통합 테스트와 전체 플랫폼 빌드가 통과한다.
12. build 60 업로드 상태에서 iPhone 최종 인수 후 iPad, macOS 순으로 확인 결과를 기록한다.

## 11. 공식 구현 기준

- [Widgets HIG](https://developer.apple.com/design/human-interface-guidelines/widgets)
- [Live Activities HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities)
- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent)
- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [Linking to specific app scenes](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity)
