# 앱 테마

현재 소스는 라이트 8개와 다크 4개를 제공한다. 2026-10-03 추가한 네 테마는
TestFlight build 88 이후 변경이며 아직 배포하지 않았다.

## 인기 팔레트에서 추가한 테마

[Color Hunt Popular](https://colorhunt.co/palettes/popular)의 `Month`와 `All time`
목록을 2026-10-03 KST에 확인했다. 아래 순위는 당시 화면에서 좋아요 내림차순으로
표시된 위치이며, 기간별 순위와 좋아요는 이후 달라질 수 있다.

| 테마 ID / 표시 이름 | 모드·색감 | 원본 팔레트 | 확인 당시 인기 순위 |
|---|---|---|---|
| `oliveLinen` / Olive Linen | 라이트, 린넨 베이지·올리브 | [#EEEEEE · #EAE2D6 · #F7F2EB · #8B9A6E](https://colorhunt.co/palette/8b9a6ef7f2ebeae2d6eeeeee) | Month 1위, 좋아요 1,623 |
| `burgundyIvory` / Burgundy Ivory | 라이트, 아이보리·짙은 버건디 | [#D45060 · #FFF9F2 · #F3E6D5 · #800020](https://colorhunt.co/palette/800020f3e6d5fff9f2d45060) | Month 3위, 좋아요 1,517 |
| `forestGold` / Forest Gold | 다크, 깊은 숲색·골드 | [#E8DCC4 · #C49A45 · #2A6B5C · #123F36](https://colorhunt.co/palette/123f362a6b5cc49a45e8dcc4) | Month 14위, 좋아요 653 |
| `cocoaCopper` / Cocoa Copper | 다크, 코코아 브라운·코퍼 | [#7D5A50 · #B4846C · #E5B299 · #FCDEC0](https://colorhunt.co/palette/7d5a50b4846ce5b299fcdec0) | All time 19위, 좋아요 28,767 |

원본은 배색의 근거이며 UI 토큰 전체를 그대로 복사한 것은 아니다. Olive Linen은
밝은 베이지를 유지하고 올리브를 버튼·강조 글자에 맞게 짙게 조정했다. Burgundy Ivory는
원본의 아이보리·베이지·버건디를 직접 활용했다. Forest Gold와 Cocoa Copper는 원본의
숲색·갈색을 어둡게 확장하고 강조색을 밝게 조정해 다크 표면과 구분했다.

기존 파랑·주황·보라·분홍·민트·아쿠아 중심의 라이트 테마와 파랑·분홍 중심의 다크
테마에 비해 흙색, 올리브, 버건디, 숲색이 드러나도록 구성했다. 기존 테마 토큰은 유지한다.

## 적용 경로와 호환성

- 팔레트 기준은 `shared/Core/Theme/AppThemePreset.swift`다. 앱의 미리보기와 실제 화면은
  같은 토큰을 사용하며 시스템 밝기와 관계없이 테마가 정한 모드를 유지한다.
- iOS/iPadOS와 macOS 테마 선택기는 `AppThemePreset.all`에서 목록을 구성한다.
  기존 선택값·과거 ID 별칭·기본 테마는 변경하지 않는다.
- `ThemePreferenceStore`는 등록된 ID로 선택값과 활동 그래프 설정을 저장·동기화한다.
  구버전 앱은 새 ID를 모르면 기존 기본 테마로 해석한다.
- 두 앱 루트는 테마 변경 시 `refreshWidgetSnapshot(forceWrite: true)`를 호출한다.
  캘린더·플래너 위젯은 snapshot의 `themeID`로 같은 팔레트를 읽는다.
  시스템 단색·강조 렌더링에서는 기존 시스템 표시 규칙을 따른다.
- 캘린더 일정 분류색 6개와 완료 상태의 의미색은 유지한다. 활동 히트맵은 새 강조색을
  사용하며, iOS Live Activity는 시스템 표면의 밝기에 맞는 강조색을 사용한다.
- 영속 스키마·CloudKit 스키마·위젯 snapshot 버전은 변경하지 않는다.

## 검증

2026-10-03 확인 결과:

- 관련 공통 테스트 26개 통과. 모든 테마의 주요 텍스트·컨트롤 대비 4.5:1 이상,
  히트맵 외곽선 대비 3:1 이상을 확인했다. Forest Gold의 초기 외곽선 대비 미달은
  강조색을 조정한 뒤 재검증했다.
- 설정 동기화 테스트는 전체 12개 ID를 메모리 저장소로 검증했다. 위젯 snapshot
  저장·중복 쓰기 생략·테마 변경 감지는 기본 테마에서 다른 11개 ID로 전환해 확인했다.
- Xcode 26.6의 macOS Debug 앱·위젯 빌드와 iOS Debug 앱·위젯·내장 Watch 구성이 통과했다.
- iPhone 17 Pro / iOS 26.5의 `testKanbanEveryThemeVisuals` 1개 통과. 전체 12개 테마를
  실행해 화면 21장을 저장했고, 새 네 테마의 칸반 화면을 직접 검토했다.
- 실제 iCloud 왕복, iPad·Mac의 수동 화면 확인, Release archive와 TestFlight 업로드는
  이번 검증에 포함하지 않았다.

검증 로그와 화면은 `.local/theme-expansion-20261003/`에 저장했다.
