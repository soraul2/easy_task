# PlanBase 캘린더 경험 디자인 계획

기준일: 2026-07-24

대상은 iPhone 앱의 캘린더 탭, 홈 화면 캘린더 위젯, 잠금 화면의
`PlanBase 오늘` 위젯이다. 세 화면의 크기와 사용 맥락은 다르지만 날짜, 이벤트,
오늘 상태를 같은 시각 언어와 같은 데이터 의미로 전달한다.

## 1. 참고 기준

### Apple

- [Widgets HIG](https://developer.apple.com/design/human-interface-guidelines/widgets)
  - 위젯은 시의성 있고 한눈에 이해할 수 있는 핵심 정보와 집중된 상호작용을 제공한다.
  - 크기별로 정보량과 기능을 다르게 설계하고, 브랜드가 콘텐츠보다 강해지지 않게 한다.
  - 일반적으로 11pt 이상의 텍스트를 사용하고 색상만으로 의미를 전달하지 않는다.
  - 잠금 화면 accessory 위젯은 단색 `vibrant` 환경에서도 의미가 유지되어야 한다.
- [Typography HIG](https://developer.apple.com/design/human-interface-guidelines/typography)
  - 시스템 텍스트 스타일과 Dynamic Type으로 정보 계층과 가독성을 유지한다.
- [Color HIG](https://developer.apple.com/design/human-interface-guidelines/color)
  - 색상은 관계와 강조를 보조하되 상태의 유일한 표현 수단으로 사용하지 않는다.
- [UI Design Dos and Don’ts](https://developer.apple.com/design/tips/)
  - 앱의 손가락 터치 대상은 최소 44×44pt를 기준으로 한다.

### Toss Design System과 공개 UX 가이드

- [TDS Typography](https://tossmini-docs.toss.im/tds-react-native/foundation/typography/)
  - 글자 크기를 개별 화면에서 임의로 하드코딩하지 않고 계층화된 스타일을 사용한다.
  - 더 큰 텍스트 접근성 설정에서도 정보 계층이 유지되어야 한다.
- [TDS Top](https://tossmini-docs.toss.im/tds-mobile/components/top/)
  - 상단은 주 제목과 우측 보조 행동의 역할을 명확하게 구분한다.
- [TDS Button](https://tossmini-docs.toss.im/tds-mobile/components/button/)
  - 아이콘만 있는 버튼에는 동작을 설명하는 접근성 레이블을 제공한다.
- [TDS 소개](https://developers-apps-in-toss.toss.im/design/components.html)
  - 같은 의미는 같은 컴포넌트와 규칙으로 표현해 일관된 경험을 만든다.
- [Toss UI/UX 가이드](https://developers-apps-in-toss.toss.im/design/consumer-ux-guide.html)
  - 문구는 짧고 명확한 해요체와 긍정적인 표현을 우선한다.
  - 그래픽과 색상은 정보보다 튀지 않게 정돈한다.

TDS 컴포넌트의 외형을 복제하지 않는다. Apple 플랫폼의 시스템 글꼴, SF Symbols,
WidgetKit 렌더링 규칙을 유지하면서 정보 계층, 일관성, 접근성, 간결한 문구 원칙을
PlanBase에 맞게 적용한다.

## 2. 현재 상태 감사

2026-07-24 iPhone 17 Pro, iOS 26.5 시뮬레이터에서 앱 캘린더를 직접 확인했다.

### 앱 캘린더

- 항상 42일, 6주를 그려 5주로 충분한 달에도 불필요한 마지막 행이 남는다.
- 한 행에 이전/다음 달, 테마, 템플릿, 이벤트 추가가 모두 있어 주 제목과 행동이 경쟁한다.
- 아이콘 버튼의 프레임이 32~36pt로 앱 터치 대상 기준보다 작다.
- 날짜 10pt, 공휴일 8pt, 이벤트 제목 9pt로 가독성이 낮다.
- 1pt 표 선이 콘텐츠보다 강하고 큰 빈 셀 때문에 이벤트 정보가 작게 보인다.
- 선택, 오늘, 공휴일, 이벤트 색상이 동시에 경쟁한다.

### 홈 화면 위젯

- Small은 오늘 이벤트 목록, Medium/Large는 월간 막대라는 크기별 역할은 적절하다.
- Medium/Large는 5주/6주 가변 레이아웃과 월 이동을 지원한다.
- 요일 7~9pt, 날짜 8~9pt, Large 이벤트 제목 8pt로 Apple의 일반적인 11pt
  가독성 기준에 미달한다.
- 달력 정보가 없는 오류 상태에도 브랜드 문구가 별도 공간을 차지한다.
- 사용자 테마의 색상 의미가 tinted/clear 또는 잠금 화면 단색 처리에서 사라져도
  날짜와 개수로 의미가 유지되는지 확인이 필요하다.

### 잠금 화면 위젯

- Inline/Circular/Rectangular의 역할 분리가 되어 있고 모든 본문이 11pt 이상이다.
- Inline의 `PlanBase` 접두어는 제한된 공간에서 오늘 정보보다 먼저 노출된다.
- Circular은 남은 작업이 0이고 일정만 있어도 완료 체크로 보여 오해할 수 있다.
- Rectangular의 `남음`은 무엇이 남았는지 즉시 알기 어렵다.
- 갱신/빈 상태 문구가 다른 캘린더 화면의 문체와 완전히 일치하지 않는다.

## 3. 공통 디자인 원칙

1. **오늘과 일정이 브랜드보다 먼저 보인다.**
   화면 안에서 별도 `PlanBase` 로고나 텍스트를 반복하지 않는다.
2. **앱과 위젯은 같은 달을 같은 주 수로 표현한다.**
   모든 월간 표시는 `DayKey.adaptiveMonthGridDates`의 5주/6주를 사용한다.
3. **크기별 역할을 구분한다.**
   Small은 오늘, Medium은 월간 위치와 이벤트 분포, Large는 월간 이벤트 제목,
   잠금 화면은 오늘 요약에 집중한다.
4. **글자를 줄이는 대신 정보를 생략하거나 그래픽으로 바꾼다.**
   앱과 읽어야 하는 위젯 텍스트는 11pt 이상을 기본으로 한다.
5. **색상은 보조 정보다.**
   오늘은 원형 날짜, 선택은 윤곽/배경, 초과 일정은 `+N`, 잠금 상태는 숫자와
   SF Symbol로 함께 표현한다.
6. **행동 우선순위를 드러낸다.**
   앱 헤더의 이벤트 추가는 직접 노출하고 테마와 템플릿은 보조 메뉴로 묶는다.
7. **문구는 짧은 해요체로 통일한다.**
   예: `오늘 계획이 없어요`, `PlanBase를 열면 일정을 갱신해요`.

## 4. 화면별 확정 설계

### 4.1 앱 캘린더

- 현재 달은 5주 또는 6주로 가변 표시한다.
- 월 이동, 메뉴, 이벤트 추가 버튼은 각각 44×44pt 터치 영역을 사용한다.
- 월 제목은 `headline` 계층, 날짜/요일/이벤트는 시스템 caption 계층을 사용한다.
- 테마와 템플릿 배치는 `더보기` 메뉴에 넣고 이벤트 추가만 직접 노출한다.
- 현재 달이 아닐 때 `오늘` 행동을 제공한다.
- 구분선은 0.5pt와 낮은 불투명도로 낮추고 현재 달 밖의 날짜는 배경과 텍스트를 함께
  약화한다.
- 날짜는 11pt 이상, 이벤트 막대 제목은 11pt 이상을 유지한다.
- 5주 달에는 늘어난 셀 높이를 이벤트 레인에 사용한다.

### 4.2 홈 화면 위젯

- Small: 오늘 날짜, 최대 네 이벤트, 정확한 `+N`.
- Medium: 월 위치를 읽을 수 있는 날짜와 요일, 제목 없는 색상 막대, 정확한 `+N`.
- Large: 11pt 이벤트 제목 막대와 가능한 범위의 추가 레인.
- 월 제목을 누르면 이번 달로 돌아가고 좌우 버튼은 snapshot 범위에서만 활성화한다.
- 오류 상태의 별도 브랜드 문구를 제거하고 복구 행동을 한 문장으로 안내한다.
- full color, tinted, clear, light, dark 환경을 각각 확인한다.

### 4.3 잠금 화면 위젯

- Inline: `checklist` 심볼과 `할 일 N · 일정 N`, 빈 상태는 `오늘 계획이 없어요`.
- Circular: 할 일이 있으면 할 일 수, 할 일 없이 일정만 있으면 일정 수, 모두 없으면
  체크 표시를 보여준다.
- Rectangular: 첫 줄은 `할 일 N · 완료 N · 일정 N`, 둘째 줄은 대표 항목의 종류를
  나타내는 SF Symbol과 제목을 표시한다.
- 대표 제목만 `privacySensitive()`를 유지하고 숫자는 잠금 상태에서도 읽을 수 있게 한다.
- vibrant와 Always On 저휘도에서 색 없이도 의미가 유지되어야 한다.

## 5. 구현 순서와 검증 기준

### P0 — 구조와 가독성

- [x] 앱 캘린더를 5주/6주 가변 레이아웃으로 통일한다.
- [x] 앱 헤더 행동 계층과 44pt 터치 영역을 적용한다.
- [x] 앱 날짜, 공휴일, 이벤트 글자와 구분선을 정리한다.
- [x] 홈 위젯의 읽어야 하는 글자를 11pt 기준으로 올린다.
- [x] 잠금 화면 요약 의미와 문구를 정리한다.

### P1 — 상태와 접근성

- [x] Dynamic Type 기본/AX 크기에서 앱 헤더와 날짜 선택을 확인한다.
- [x] VoiceOver 레이블이 날짜, 선택, 실제 이벤트 수, 행동을 정확히 읽는지 확인한다.
- [x] 색상 구분 없이 오늘, 선택, 이벤트 초과, 작업/일정 종류가 구분되는지 확인한다.
- [x] 위젯 privacy redaction과 오류/빈 상태를 확인한다.

### P2 — 렌더링 검증

- [x] iPhone 17e와 iPhone 17 Pro에서 앱 캘린더를 캡처한다.
- [ ] systemSmall/Medium/Large의 light/dark/tinted/clear를 확인한다.
- [ ] accessoryInline/Circular/Rectangular의 vibrant와 저휘도를 실기기에서 확인한다.
- [x] 5주/6주, 이벤트 없음/밀집/장기 이벤트 fixture를 확인한다.

자동 승인 기준:

- `swift test` 전체 통과
- `PlanBase-iOS`와 `PlanBaseWidgetExtension` Debug 빌드 통과
- `git diff --check` 통과
- 캘린더 레이아웃 및 snapshot 단위 테스트 통과

실기기 전용 항목은 출시 승인 체크로 남기되, 시뮬레이터와 preview로 가능한 상태는
코드 작업 중 모두 확인한다.

## 6. 1차 구현 및 검증 결과

- 앱 캘린더는 기본 글자 크기에서 제목 막대, 접근성 글자 크기에서 그래픽 막대로
  자동 전환한다. 큰 글자에서도 날짜를 생략하지 않고 이벤트 밀도를 유지한다.
- 홈 위젯은 읽는 텍스트를 11pt 이상으로 올렸고, Medium의 색상 막대와 Large의
  제목 막대 역할은 유지했다.
- 잠금 화면 Circular은 할 일이 0개이고 일정만 있을 때 체크 표시 대신 일정 수를
  보여준다.
- 홈 위젯의 Small/Medium/Large/갱신 필요와 잠금 위젯의 일정만 있는 Circular을
  Debug preview fixture에 추가했다.
- 자동 테스트, 앱/위젯 빌드, iPhone 17e·17 Pro 기본 화면, 5주·6주,
  Dynamic Type 접근성 크기까지 확인했다.
- 실제 홈 화면의 tinted/clear 렌더링과 잠금 화면의 Always On 저휘도는 실기기
  출시 승인 항목으로 남긴다.
