# 활동 스트릭·히트맵 및 통계 보기 구현 계획

기준일: 2026-08-14
상태: 핵심 구현 및 로컬 검증 완료, 실기기·Production 출시 게이트 대기
대상: macOS, iPhone, iPad의 `기록` 화면

## 구현 현황 (2026-08-14)

완료:

- EasyTaskSchemaV7 활동 모델, V6 → V7 migration, 저장소 호환성 및 Development
  schema 정의
- 완료 전환 lifecycle, 같은 날 중복 방지, 취소·삭제 시 활동 보존, legacy backfill,
  자연 키 및 cross-day CloudKit 중복 수렴
- JSON V1 호환과 package V6 활동 백업·복원·병합·검증
- 16/52주 bounded query, 범위 밖 현재 스트릭 pagination, 최근 365일 최고 기록,
  자정·시간대·request generation 갱신
- 테마 계산 팔레트, 한 개 hit surface의 공용 Canvas 히트맵, future 비활성,
  VoiceOver action, macOS hover·방향키·Escape 조작
- macOS·iPhone·iPad 기록 화면의 기본 활동 보기와 별도 통계 보기, 세 줄
  요약과 선택 날짜 한 줄 상세
- Swift Package Debug/Release, macOS·iOS Debug/Release 빌드, 모바일 앱 단위 테스트
- iPhone UI의 활동 → 통계 전환과 iPad portrait/landscape 활동 화면 검증
- 재점검에서 손상된 cross-day captured 후보가 legacy 증거를 제거하지 않도록 보강하고
  회귀 테스트 추가
- macOS Return/Space 선택과 hover 도움말, 이벤트 기록 UI fixture의 통계 모드 일치 보강

출시 전 남은 항목:

- iPad Split View·macOS 좁은 폭·접근성 옵션의 시각 QA와 실기기 CloudKit
  양방향 수렴/Production schema 출시 게이트

## 1. 목표

사용자가 PlanBase에서 작업을 얼마나 많이 처리했는지보다, 작업을 얼마나 꾸준히
이어왔는지를 먼저 이해하게 한다. 기존 `선택 기간 작업 요약`은 버리지 않고 별도
`통계` 보기로 이동해 필요할 때만 확인하게 한다.

첫 화면에서 항상 보여줄 정보는 세 가지로 제한한다.

1. 현재 연속 활동일
2. 오늘 활동 완료 여부
3. 날짜별 완료 활동 히트맵

날짜별 상세 수치와 작업 목록은 날짜를 선택했을 때만 공개한다. 태그 분석, 생산성
점수, 순위, AI 요약과 여러 종류의 차트는 첫 배포 범위에서 제외한다.

## 2. 확정 제품 결정

### 정보 구조

- 앱의 최상위 탭을 추가하지 않는다.
- 기존 `기록` 화면 안에 `활동`과 `통계` 두 개의 관련 보기만 둔다.
- 첫 진입 기본값은 `활동`이다.
- 사용자가 선택한 보기는 기기 로컬 UI 설정으로 기억하되 CloudKit이나 백업에는
  넣지 않는다.
- 기존 날짜별 기록 피드, 검색, 기간·범위·날짜 기준 필터는 유지한다.
- `활동`은 실제 완료 행동일을 사용하고, `통계`와 기록 피드는 기존 계획일/완료일
  의미를 유지한다. 서로 다른 날짜 축을 한 수치로 섞지 않는다.

### 1차 출시 범위

- 현재 스트릭과 오늘 상태
- 최근 활동 히트맵
- 선택 날짜의 완료 작업 수
- 모든 플랫폼에 동일한 최근 365일 최고 스트릭
- 기존 작업 통계의 간결한 재배치
- macOS, iPhone, iPad의 적응형 레이아웃
- 모든 PlanBase 테마와 Light/Dark Mode
- VoiceOver, Dynamic Type, 키보드와 포인터 접근
- CloudKit, 백업, 중복 수렴을 포함한 영속 활동 기록

### 첫 출시에서 제외

- 태그·우선순위·예상 시간 분포
- 이전 기간과의 증감 비교
- 계획 수용량 예측
- 사용자 간 순위, 공유 스트릭, 친구 기능
- 포인트, 레벨, 재화, 유료 Streak Freeze
- AI가 생성하는 칭찬·평가·회고 문장
- 스트릭 유지용 푸시 알림
- 홈/잠금 화면 위젯의 스트릭 표시
- 회고·메모·체크리스트 완료를 활동으로 계산하는 옵션
- 활동 기록만 별도로 초기화하는 UI와 자동 보존 기간

제외 항목은 핵심 경험이 검증된 뒤 별도 계획으로 평가한다. 첫 구현에 숨은 기능이나
미완성 설정을 미리 넣지 않는다.

## 3. 참고 서비스와 적용 경계

### GitHub

- [GitHub Contributions](https://docs.github.com/en/enterprise-cloud@latest/account-and-profile/concepts/contributions-on-your-profile)는 지난 1년의 활동을 날짜별 칸과 강도로 요약한다.
- PlanBase는 `한 칸 = 하루`, `농도 = 그날 완료한 고유 작업 수`만 참고한다.
- GitHub의 녹색, 문구, 정확한 셀 크기와 프로필 구성을 복제하지 않는다.

### Duolingo

- [Duolingo의 스트릭 설계](https://blog.duolingo.com/how-duolingo-streak-builds-habit/)에서 현재 연속 일수와 오늘 활동 여부를 짧게 보여주는 원칙을 참고한다.
- 캐릭터, 재화, 긴급감을 유도하는 문구, 과도한 축하 애니메이션은 가져오지 않는다.
- 첫 배포는 `하루 한 번 이상 작업 완료`라는 한 문장 규칙을 사용한다. 휴식 요일이나
  보호일은 실제 사용 후 별도 제품 결정으로 남긴다.

### Apple 플랫폼

- [Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls)는 밀접한 관련 보기를 전환하는 데 사용한다.
- [Color](https://developer.apple.com/design/human-interface-guidelines/color)는 색만으로 상태를 전달하지 말라는 원칙을 따른다.
- [UI Design Dos and Don'ts](https://developer.apple.com/design/tips/)의 화면 적응, 대비,
  44pt 주요 조작 영역과 읽기 쉬운 정렬을 따른다.
- 시스템 글꼴, SwiftUI 기본 컨트롤, SF Symbols와 플랫폼 기본 focus/hover 효과를 우선한다.

참고 서비스의 외형을 섞어 새로운 스타일을 만드는 것이 아니라, PlanBase의 기존
표면·간격·테마 안에서 정보 구조만 적용한다.

## 4. 현재 구조와 해결할 문제

### 현재 구현

- macOS `ArchiveView`와 iOS/iPadOS `MobileArchiveView`가 각각
  `선택 기간 작업 요약`을 구현한다.
- `TaskHistoryStatistics`는 계획 작업, 완료 작업, 계획일 내 완료, 지연 완료,
  미완료를 계산한다.
- `TaskHistoryStatisticsSession`은 기간 후보를 bounded query로 읽는다.
- `Task.completedAt`과 `completedDayKey`는 완료를 취소하면 `TaskRules`에서 `nil`로
  돌아간다.
- 모바일 타겟은 `TARGETED_DEVICE_FAMILY = "1,2"`로 iPhone과 iPad를 함께
  지원하지만 기록 요약에는 iPad 전용 정보 배치가 없다.
- `AppTheme`에는 패널·입력·상태·선택 색상이 있지만 활동 강도용 의미 토큰은 없다.

### 해결할 문제

1. 현재 집계 수치만으로는 매일 이어온 흐름을 볼 수 없다.
2. 완료 취소나 Task 삭제 후 현재 Task만 다시 계산하면 과거 스트릭이 소급해 사라진다.
3. `원래 날짜에 완료`는 Task의 완료일을 과거로 기록할 수 있으므로 스트릭 날짜로
   `completedDayKey`를 사용하면 실제 활동하지 않은 과거 날짜가 채워진다.
4. macOS와 모바일에 같은 요약 UI가 중복돼 의미나 문구가 달라질 가능성이 있다.
5. 고정 색상의 히트맵은 PlanBase 테마와 Light/Dark Mode에서 대비가 깨질 수 있다.
6. 작은 히트맵 셀을 개별 버튼으로 만들면 iPhone 터치와 VoiceOver 사용성이 나빠진다.

## 5. 용어와 데이터 의미

### 활동일

사용자가 로컬 날짜 기준으로 Task를 `할 일` 또는 `진행 중`에서 `완료`로 한 번 이상
전환한 날이다.

- 활동 날짜는 완료 명령을 실행한 실제 `occurredAt`에서 `DayKey`로 만든다.
- 완료 순간 만든 `activityDayKey`가 날짜 원본이다. 다른 시간대의 기기가
  `occurredAt`을 다시 변환해 날짜를 바꾸지 않는다.
- Task 기록의 `completedDayKey`가 과거 계획일이어도 활동 날짜를 과거로 옮기지 않는다.
- 같은 논리 Task를 같은 날 여러 번 완료해도 그날 한 작업으로만 센다.
- 같은 Task를 다른 날 다시 완료하면 각 날짜의 실제 활동으로 센다.
- 완료 취소는 이미 발생한 활동 기록을 지우지 않는다.
- Task 삭제 후에도 날짜와 익명 활동 사실은 남긴다. 삭제한 Task의 제목·메모를 활동
  레코드에 복제하지 않는다.
- 첫 배포에서는 활동 기록을 자동 만료하지 않으며 Activity 전용 초기화 UI를 제공하지
  않는다. 데이터 전체 삭제 정책과 별개 기능으로 다루고 후속 평가 없이 숨은 삭제
  동작을 추가하지 않는다.
- 체크리스트, 회고, 메모 저장과 앱 실행만으로는 활동일이 되지 않는다.

### 현재 스트릭

- 활동일이 연속된 달력 날짜 수다.
- 오늘 활동했다면 오늘까지 계산한다.
- 오늘 아직 활동하지 않았지만 어제까지 연속이었다면 오늘이 끝날 때까지 기존
  스트릭을 유지하고 `오늘 활동 전`으로 표시한다.
- 어제 이전에 빈 날짜가 있으면 그 다음 활동일부터 새 스트릭을 계산한다.
- 첫 배포에서는 모든 달력 날짜를 같은 기준으로 취급한다.

### 최고 스트릭

- 모든 플랫폼에서 오늘을 포함한 최근 365일 안의 가장 긴 스트릭이다.
- UI에는 항상 `최근 1년 최고`라고 표시한다.
- iPhone의 16주, iPad/macOS의 52주는 히트맵 표시 범위일 뿐 최고 스트릭의
  계산 범위를 바꾸지 않는다.
- 전체 이력을 모두 읽는 `역대 최고`는 첫 배포에서 계산하지 않는다.

### 히트맵 강도

고유 Task 완료 수에 고정 구간을 사용한다.

| 단계 | 작업 수 | 의미 |
|---|---:|---|
| 0 | 0 | 활동 없음 |
| 1 | 1 | 활동 있음 |
| 2 | 2 | 보통 |
| 3 | 3~4 | 많음 |
| 4 | 5개 이상 | 매우 많음 |

사용자별 상대 백분위는 같은 색의 의미가 기간마다 바뀌므로 사용하지 않는다.

## 6. 화면 구조와 최소 정보 원칙

### 기록 화면 전체 구조

```text
기록

[ 활동 | 통계 ]

선택한 보기의 요약

검색·필터
날짜별 작업·회고 기록
```

보기 전환은 요약 영역만 바꾸고 기존 기록 피드는 유지한다. `활동`과 `통계`를 앱의
새 최상위 탭으로 만들지 않는다.

### 활동 보기 기본 상태

```text
🔥 12일 연속
오늘 작업을 완료하면 이어져요
최근 1년 최고 28일

      5월       6월       7월       8월
월  □ ▪ ■ □ ■ ■ □ ■ ■ ■ □ ■
수  ■ □ ▪ ■ ■ □ □ ■ ■ ■ □ ■
금  □ ■ ■ □ ■ □ ■ ■ ■ □ ■ □

적음  □ ▪ ▪ ▪ ■  많음
```

항상 노출하는 텍스트는 `현재 스트릭`, `오늘 상태`, `최근 1년 최고 기록` 세 줄을
넘기지 않는다. 총 완료 수, 평균, 달성률은 활동 보기에서 반복하지 않는다.

### 오늘 상태 문구

| 상태 | 문구 |
|---|---|
| 오늘 활동 전, 기존 스트릭 있음 | `오늘 작업을 완료하면 이어져요` |
| 오늘 활동 완료 | `오늘도 기록을 이어갔어요` |
| 아직 스트릭 없음 | `작업을 완료하면 활동 기록이 시작돼요` |
| 어제 이전에 끊김 | `오늘부터 다시 시작할 수 있어요` |

`실패`, `손실`, `0일`, `놓쳤어요`처럼 사용자를 평가하는 문구는 사용하지 않는다.

### 현재 스트릭과 히트맵 결합

- 셀 채움 농도는 완료 작업 수만 나타낸다.
- 현재 스트릭에 포함된 셀에는 테마 기반 2pt 테두리를 추가한다.
- 오늘 셀에는 모양이 다른 외곽선을 사용하고 작은 셀 안에 아이콘을 넣지 않는다.
- 외곽선 우선순위는 `선택 > 오늘 > 현재 스트릭`으로 고정한다.
- 오늘 이후의 셀은 `활동 없음`으로 세지 않는 비활성 상태로 그리며 선택할 수 없다.
- 색을 구분하기 어려워도 테두리와 오늘 표식으로 현재 스트릭을 찾을 수 있어야 한다.
- 불꽃을 누르면 현재 스트릭 구간을 강조하고 나머지 셀을 흐리게 하는 기능은
  2차 상호작용으로 두며 첫 배포 필수 조건은 아니다.

### 날짜 선택 시 점진적 공개

기본 상태에서는 날짜 상세를 숨긴다. 셀을 선택하면 히트맵 아래 한 줄만 추가한다.

```text
8월 14일 목요일 · 완료 작업 4개
```

- 같은 날짜를 다시 누르면 선택을 해제한다.
- 활동이 없는 날짜를 선택하면 `완료 작업 없음`을 표시한다.
- 상세 Task 제목 목록과 보드 이동은 첫 배포에서 넣지 않는다. 활동일과 기존
  완료일/계획일의 축이 다를 수 있기 때문이다.
- macOS에서는 hover tooltip으로 날짜와 작업 수를 미리 볼 수 있다.

### 통계 보기

기존 통계를 다음 한 카드로 단순화한다.

```text
8월 8일–8월 14일

계획한 18개 중 14개 완료
계획 이행률 78%

[ 계획일 내 11 | 지연 3 | 미완료 4 ]

이 기간에 완료한 작업 16개
```

- 계획일 기준과 완료일 기준을 같은 숫자 열에 나란히 놓지 않는다.
- 긴 `meaningDescription`을 항상 노출하지 않고 짧은 레이블 자체로 기준을 설명한다.
- 기존 기간 필터는 통계에 적용한다.
- 태그 차트, 증감 비교, 계획 적정도는 핵심 활동 경험 검증 후 별도 단계로 둔다.

## 7. 플랫폼별 UI

### 공통

- 의미, 문구, 강도 구간과 데이터 결과는 공통 코어에서 계산한다.
- 플랫폼별 차이는 배치, 셀 크기, hover와 키보드 동작에만 둔다.
- `ViewThatFits`, size class와 실제 컨테이너 폭으로 레이아웃을 선택한다.
- 고정 기기 모델명이나 화면 픽셀을 조건으로 사용하지 않는다.
- 주 시작일은 하드코딩하지 않고 `DayKey.calendar.firstWeekday`를 사용한다.
- 컨테이너 폭이 compact/regular 경계를 오갈 때 16주/52주 요청을 교체하고 이전
  요청을 취소한다. 선택 날짜가 새 범위 밖이면 선택을 해제한다.

### iPhone

- `Picker`의 segmented style로 `활동 / 통계`를 전환한다.
- 세로 순서는 `스트릭 → 히트맵 → 선택 날짜`로 고정한다.
- compact width에서는 최근 16주를 표시하고 정확한 시작·종료 날짜를 접근성 값에
  포함한다.
- 히트맵을 별도의 가로 스크롤 안에 넣지 않는다. 폭에 맞춰 셀과 간격을 계산한다.
- 텍스트가 접근성 크기일 때 스트릭 제목과 오늘 상태를 세로로 쌓는다.

### iPad

- iPhone과 같은 iOS 타겟·화면을 사용하되 regular width에서 최근 52주를 표시한다.
- portrait에서는 스트릭 요약 위, 히트맵 아래의 세로 배치를 기본으로 한다.
- landscape와 넓은 Split View에서는 `ViewThatFits`로 요약과 히트맵의 좌우 배치를
  허용한다.
- 좁은 Split View가 되면 iPhone compact 배치와 16주 범위로 자연스럽게 돌아간다.
- iPad pointer hover에는 날짜와 완료 수 tooltip을 제공한다.

### macOS

- 기존 최대 콘텐츠 폭 760pt를 기준으로 최근 52주를 표시한다.
- `활동 / 통계` 전환은 현재 Archive 화면 헤더 안의 native segmented picker로
  제공한다. 별도 toolbar를 추가하기 위해 `AppRootView`를 변경하지 않는다.
- 셀 hover는 날짜와 완료 수, click은 선택, Escape는 선택 해제로 동작한다.
- Tab 키로 보기 전환과 날짜 탐색 컨트롤에 접근할 수 있어야 한다.
- 현재 앱의 최소 창 폭을 낮추지 않는다. 실제 Archive 컨테이너가 좁아지는 접근성·배치
  상황에서만 요약과 히트맵을 세로로 쌓고 가로 스크롤을 만들지 않는다.

## 8. AI처럼 보이지 않는 시각·문구 원칙

이 기능은 자동 분석 도구가 아니라 사용자의 과거 행동 기록이다. 다음 원칙을 코드와
디자인 리뷰 기준으로 둔다.

- 시스템 글꼴과 기존 PlanBase typography만 사용한다.
- `sparkles`, 마법봉, 챗봇, AI badge를 사용하지 않는다.
- 네온 glow, 움직이는 배경, 여러 겹 gradient, 과도한 glass surface를 추가하지 않는다.
- 현재 스트릭에 정적인 `flame.fill` 하나만 사용하며 계속 뛰거나 흔들리지 않는다.
- 축하 효과는 숫자의 짧은 `numericText` 전환까지만 허용한다.
- Reduce Motion이 켜져 있으면 숫자·선택 전환도 즉시 변경한다.
- 카드 하나 안에서 설명 문장을 반복하지 않는다.
- `대단해요`, `완벽해요`, `생산성이 높아요`처럼 근거 없이 평가하지 않는다.
- empty/error 상태는 현재 상황과 다음 행동만 말한다.
- iPhone의 카드 corner radius, macOS panel radius와 border는 현재 기록 화면 값을
  재사용한다.

## 9. 테마 적용 계획

### 원칙

- GitHub green과 Duolingo orange를 하드코딩하지 않는다.
- `AppTheme.panel`, `input`, `done`, `selectedTab`, `primaryText`, `border`에서 활동
  의미 팔레트를 만든다.
- 테마 프리셋마다 화면 코드에서 조건 분기하지 않는다.
- Light/Dark Mode와 모든 프리셋에서 동일한 단계 의미를 유지한다.

### 공통 팔레트

`ActivityHeatmapPalette`는 `AppThemeColorSet`의 계산 프로퍼티 또는 extension으로
추가한다. 기존 preset initializer에 저장 프로퍼티를 추가하지 않는다. macOS 위젯
세션이 추가한 `resolvedSemanticForeground`를 포함한 최신 테마 구현을 기준으로
확장하며 기존 helper를 덮어쓰지 않는다.

```text
empty
level1
level2
level3
level4
streakStroke
todayStroke
selectionStroke
```

- `empty`는 `input` 또는 `panel`과 `border` 조합으로 만든다.
- `level1...4`는 `input`과 `done`의 고정 blend 비율로 계산하되 상대 휘도 순서를
  검증한다.
- `streakStroke`와 `todayStroke`는 인접 셀에서 구분되는 semantic foreground를 쓴다.
- 파생 팔레트가 특정 테마에서 구분 기준을 충족하지 못할 때만 preset에 명시적 활동
  토큰을 추가한다.

### 테마 테스트

- 모든 preset × Light/Dark에서 활동 단계가 순서대로 더 강해지는지 확인한다.
- 인접 단계의 상대 휘도 순서와 최소 시각 차이를 테스트한다. RGB distance만으로
  통과 여부를 결정하지 않는다.
- 오늘/선택 외곽선과 배경의 비텍스트 대비를 확인한다.
- 색을 제거한 snapshot에서도 스트릭 테두리와 오늘 모양이 남는지 확인한다.
- 테마 변경 직후 별도 화면 재진입 없이 팔레트가 갱신되는지 UI 테스트한다.

## 10. 접근성 및 입력 설계

작은 셀 182~364개를 개별 Button이나 VoiceOver 요소로 그대로 노출하지 않는다.

- 히트맵 전체를 하나의 `활동 달력` 접근성 요소로 제공한다.
- 접근성 값에는 표시 범위, 활동한 날 수, 현재 스트릭을 포함한다.
- 시각적 히트맵도 하나의 hit surface로 만들고 좌표를 가장 가까운 날짜 셀로 변환한다.
- `이전 날짜`, `다음 날짜` custom accessibility action으로 빈 날짜를 포함해 하루씩
  이동한다. `이전 활동일`, `다음 활동일`은 보조 action으로만 제공한다.
- 선택 날짜 요약은 별도 텍스트 요소로 읽는다.
- 시각 셀 tap은 편의 동작이고, 접근성 사용자는 44pt 이전/다음 날짜 버튼으로 같은
  결과에 도달할 수 있게 한다.
- macOS 키보드는 방향키로 날짜 이동, Return/Space로 선택, Escape로 해제를 지원한다.
- 요일과 월 레이블은 Dynamic Type에서 겹치면 일부를 숨기되 날짜 의미는 접근성 값에
  유지한다.
- 완료 강도는 색뿐 아니라 선택 날짜의 숫자와 스트릭 외곽선으로도 전달한다.
- `Differentiate Without Color`, Increase Contrast, Reduce Motion 환경을 확인한다.

## 11. 영속 데이터 설계

### V7 모델

기존 V1~V6를 수정하지 않고 `EasyTaskSchemaV7`을 추가한다.

```swift
public enum TaskCompletionActivityOrigin: String, Codable, Sendable {
    case captured
    case legacyBackfill
}

@Model
public final class TaskCompletionActivity {
    #Index<TaskCompletionActivity>(
        [\.activityDayKey],
        [\.id],
        [\.taskId, \.activityDayKey],
        [\.taskId, \.occurredAt]
    )

    public var id: UUID = UUID()
    public var instanceID: UUID = UUID()
    public var taskId: UUID = UUID()
    public var activityDayKey: String = ""
    public var occurredAt: Date = Date.distantPast
    public var originRawValue: String = TaskCompletionActivityOrigin.captured.rawValue
    public var createdAt: Date = Date.distantPast
    public var updatedAt: Date = Date.distantPast
    public var supersededAt: Date?

    public init(
        id: UUID,
        instanceID: UUID = UUID(),
        taskId: UUID,
        activityDayKey: String,
        occurredAt: Date,
        origin: TaskCompletionActivityOrigin = .captured,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        supersededAt: Date? = nil
    ) {
        self.id = id
        self.instanceID = instanceID
        self.taskId = taskId
        self.activityDayKey = activityDayKey
        self.occurredAt = occurredAt
        self.originRawValue = origin.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.supersededAt = supersededAt
    }
}
```

- V7의 models는 `EasyTaskSchemaV6.models + [TaskCompletionActivity.self]`로 구성한다.
- CloudKit 호환을 위해 모든 non-optional 저장 프로퍼티에 기본값을 두고 명시적
  initializer를 제공한다.
- CloudKit과 기존 중복 수렴 정책상 `#Unique`는 사용하지 않는다. 자주 필터·정렬하는
  날짜와 자연 키 조회에만 local `#Index`를 사용한다.
- relationship을 만들지 않고 논리 `taskId`만 저장한다.
- Task 제목·메모·태그 snapshot은 저장하지 않는다.
- 논리 `id`는 `(taskId, activityDayKey)`를 안정적으로 hash한 결정적 UUID로 만든다.
  canonical input은 `taskId.uuidString.lowercased() + "|" + activityDayKey`, hash는
  SHA-256의 앞 16바이트를 사용한다. byte 6의 상위 nibble은 UUID v8인 `1000`, byte
  8의 상위 2bit는 RFC 4122 variant인 `10`으로 고정한다. 구현 언어와 기기에 무관한
  고정 test vector를 둔다.
- `instanceID`는 물리 레코드 ID이며 기존 중복 수렴 규칙을 따른다.
- 같은 Task/날짜가 여러 기기에서 생성돼도 논리 ID가 같아 수렴할 수 있어야 한다.
- 활동 레코드는 완료 취소 시 삭제하지 않는 append-only 사실 기록으로 취급한다.
- 같은 날짜의 반복 완료는 기존 레코드의 `occurredAt`을 덮어쓰지 않는
  `insert-if-absent`로 처리한다. `upsert`라는 표현은 사용하지 않는다.
- `(taskId, occurredAt)` index는 날짜 키가 다른 captured/legacy 후보를 같은 완료
  발생으로 찾는 integrity 조회에만 사용한다.
- 잘못된 중복은 즉시 삭제하지 않고 `supersededAt`으로 수렴시킨다.

### 실제 행동일과 Task 완료일

```text
Task.completedDayKey       기록·통계의 완료 날짜
Activity.activityDayKey    사용자가 완료 동작을 실행한 실제 날짜
```

예를 들어 8월 10일 작업을 8월 14일에 `원래 날짜에 완료`해도 기록 목록은 기존 정책대로
8월 10일 완료로 볼 수 있지만, 활동 히트맵은 8월 14일을 채운다.

### 완료 저장 경계

현재 여러 UI가 `TaskRules.applyStatus`를 직접 호출한다. 활동 레코드 누락을 막기 위해
공통 orchestration을 추가한다.

```text
PersistenceCommandService.perform         호출부가 한 번만 소유
  → TaskLifecycleService.applyStatus       save하지 않는 mutation API
      → 이전 상태 확인
      → TaskRules.applyStatus
      → 미완료에서 완료로 실제 전환됐으면 Activity insert-if-absent
```

- 단일 완료와 `원래 날짜에 모두 완료`가 같은 기록 함수를 사용한다.
- 호출부가 Task 저장과 활동 기록을 같은 `PersistenceCommandService.perform` 안에서
  처리하며 `TaskLifecycleService` 내부에서는 `perform`이나 `save`를 호출하지 않는다.
- Task와 Activity에는 호출부가 만든 동일한 `now`를 전달한다.
- 서비스는 `didChange`, `didComplete`, `activityInserted`를 포함한 결과를 반환한다.
- Task 저장 실패 시 활동 레코드도 rollback한다.
- 모든 앱 호출부가 전환된 뒤 `TaskRules.applyStatus`, `completeAll`,
  `completeOnPlannedDays`의 접근 수준을 `package`로 낮춰 앱의 우회를 막는다.
- seed와 UI fixture는 production 기록과 구분된 명시적 시각을 주입한다.
- `.done` 상태로 생성한 뒤 다시 `.done`을 적용하는 기존 seed는 `.todo`에서 lifecycle
  service로 전환하거나 Activity fixture를 함께 삽입하도록 수정한다.

### 기존 데이터 backfill

- `TaskActivityService`는 정상 완료 capture와 insert-if-absent만 담당한다.
- `TaskActivityBackfillService`는 startup/legacy backup/CloudKit 누락 보완을 담당하고
  `TaskActivityIntegrityService`는 page 단위 자연 키 수렴을 담당한다. 세 역할을 한
  저장 함수에 섞지 않는다.
- `TaskActivityImportCoordinator`는 앱 root가 소유하는 `@MainActor @Observable` 장기 객체다.
  주입 가능한 Clock과 하나의 pending task만 보유하고 새 성공 import가 오면 이전
  예약을 취소·교체한다.
- V7 최초 개방 시 현재 대표 완료 Task의 `completedAt`으로 `legacyBackfill` 활동
  레코드를 만든다. 먼저 기존 Task integrity를 실행하므로 과거 `completedAt`이 없던
  완료 Task는 기존 규칙대로 `completedDayKey` 또는 `updatedAt`에서 정규화될 수 있다.
  따라서 V7 이전 이력은 원본 활동 시각을 보장하지 않는 추론 기록임을 코드, 테스트와
  호환성 표에서 명확히 한다.
- legacy 날짜 키는 현재 기기 시간대가 아니라 고정 Gregorian UTC calendar로 만들어
  여러 기기에서 같은 논리 ID가 생성되게 한다.
- 날짜별 논리 ID가 결정적이므로 작업은 반복 실행해도 idempotent해야 한다.
- 앱 시작, 이전 백업 import, 구버전 CloudKit 데이터 보완은 bounded batch로 실행한다.
- 성공한 CloudKit import 직후에는 즉시 Activity를 만들지 않는다. 연속 import를
  generation token과 주입 가능한 Clock으로 coalesce한다. production에서는 마지막
  성공 import 후 2초 debounce 뒤 다시 조회하고 누락된 경우만 추론 레코드를 만든다.
- 기존 `CloudKitSyncService.reconcileIfNeeded`의 일반 모델 DataIntegrity는 import 직후
  지금처럼 즉시 실행한다. 성공 summary가 반환된 뒤 app root가 activity coordinator를
  별도로 예약하며 기존 reference/duplicate 수렴을 debounce 뒤로 미루지 않는다.
- coordinator가 실행하는 backfill과 activity integrity는 하나의
  `PersistenceCommandService.perform` 안에서 저장돼 두 번째 data-changed notification을
  게시한다.
- 동일 Task에서 `occurredAt`이 1초 이내인 `captured`와 `legacyBackfill`이 함께 있으면
  날짜 키가 달라도 captured가 실제 완료 발생을 대표하며 legacy 후보를 supersede한다.
- 동일 자연 키 안의 대표 우선순위도 `captured > legacyBackfill > updatedAt > instanceID`로
  고정한다. 이후 captured가 도착하면 기존 추론 결과가 최종적으로 사라져야 한다.
- 현재 대표 완료 Task는 기존 integrity 후 유효한 `completedAt`이 있으면 모두
  backfill한다. 정확한 실제 행동일 보장은 V7 이후 생성된 `captured`에만 적용한다.
- 기능 출시 전에 이미 삭제된 Task의 활동은 복원할 원본이 없음을 문서화한다.
- V6 앱에서 완료 후 V7 기기가 보기 전에 완료 취소·삭제한 기록은 복원할 수 없다.
  혼합 버전 기간의 이 제한을 호환성 표와 테스트 설명에 포함한다.

실행 순서는 다음으로 고정한다.

```text
앱 시작: 기존 모델 DataIntegrity → legacy activity backfill → activity integrity → seed/fixture → lazy archive
이전 백업: payload merge → legacy activity backfill → integrity → save → notification
CloudKit: import 성공 → 기존 DataIntegrity 즉시 저장/notification → activity 예약
          → debounce/coalesce → backfill → activity integrity → 저장/notification
```

### 무결성

`DataIntegrityService`에 다음 규칙을 추가한다.

- 유효한 `activityDayKey`와 유한한 `occurredAt` 검증
- `originRawValue`가 알려진 값인지 검증
- 날짜 키가 잘못됐거나 `occurredAt`이 유한하지 않거나 origin이 알려지지 않은 레코드는
  수신 기기 시간대로 값을 만들어내지 않고 supersede한다.
- 유효한 `activityDayKey`는 `occurredAt`이나 현재 기기 시간대로 다시 쓰지 않음
- 새 완료를 저장하는 원본 기기에서만 `occurredAt`과 같은 로컬 날짜 키를 생성
- 자연 키 `(taskId, activityDayKey)`로 후보를 모으고 논리 `id`가 결정적 ID와 같은지
  검증한다. 유효한 payload의 잘못된 `id`는 관계 참조가 없으므로 자연 키에서 계산한
  canonical ID로 먼저 정규화한다. 잘못된 ID만 같다는 이유로 서로 다른 자연 키를
  합치지 않는다.
- 대표 선택은 origin 우선순위 뒤 `updatedAt`, `instanceID`를 사용한다.
- 대표 외 레코드 `supersededAt` 처리
- Task가 없어도 활동 레코드는 고아로 삭제하지 않음
- append-only 데이터가 커지는 것을 고려해 활동 무결성과 backfill은 page 단위로
  처리한다. 기존 전체 모델 fetch에 활동 전체 이력을 추가하지 않는다.
- page 안에서 natural-key 수렴을 끝낸 뒤 legacy 후보를 `(taskId, occurredAt ± 1초)`
  indexed query로 조회해 다른 날짜 page의 captured도 확인한다. page 경계 때문에
  cross-day 후보를 놓치지 않는다.
- `DataIntegrityService`는 activity 전용 integrity service를 orchestration하되 기존
  모델 배열에 활동 전체 fetch 결과를 합치지 않는다.
- 백업 직전과 CloudKit import 안정화 후 동일 규칙 실행

## 12. 조회와 성능

### `ActivityOverviewSession`

공통 `@Observable` session을 추가한다.

- iPhone compact: 최근 16주
- iPad regular/macOS: 최근 52주
- 활동 레코드를 `activityDayKey` 범위로 bounded fetch
- 같은 날짜의 고유 `taskId` 수로 강도 계산
- 현재 스트릭은 표시 범위를 넘어갈 수 있으므로 오늘/어제부터 과거 방향으로 page를
  읽고 첫 빈 날짜에서 중지한다.
- 최고 스트릭은 히트맵 폭과 무관하게 최근 365일 고정 범위에서 계산한다.
- `cancel()`을 공개하고 보기 전환, 폭 변경, 화면 이탈 시 pending request를 취소한다.
- request generation을 비교해 오래된 16주/52주 결과가 새 상태를 덮어쓰지 못하게 한다.
- `PersistenceCommandService.dataChangedNotification`과 성공한 CloudKit import 후 갱신
- 자정, 시스템 시간대 변경, 앱 foreground 복귀 때 데이터 변경이 없어도 기준 날짜와
  범위를 갱신한다.
- Activity 보기가 보일 때만 activity session을, Statistics 보기가 보일 때만 기존
  statistics session을 활성화한다. 부모의 기록 query session은 유지해 보기 전환이
  검색 결과와 pagination 깊이를 초기화하지 않게 한다.
- 각 overview session의 loading/error/retry 상태를 UI에 별도로 노출한다.
- Archive 검색·기간·범위 필터는 기록 피드와 통계에만 적용하고 고정 범위 활동에는
  적용하지 않는다. 화면 문구도 `기록 목록 검색`, `기록 목록 필터`로 구분한다.

전체 Task나 전체 활동 레코드를 `@Query`로 계속 관찰하지 않는다. pagination batch 크기와
최대 표시 범위를 테스트에서 고정한다.

Swift 6 concurrency 경계를 지키기 위해 `ModelContext` fetch와 `@Model` 접근은 MainActor
안에서 끝낸다. 백그라운드 순수 계산이 필요하면 먼저 Sendable 값 snapshot으로 변환하고
detached task에 `ModelContext`나 SwiftData 객체를 캡처하지 않는다.

### 순수 규칙

`TaskActivityRules`가 다음을 담당한다.

- 날짜별 고유 Task 집계
- 고정 intensity 단계 계산
- 표시 범위를 넘는 현재 스트릭과 최근 365일 최고 스트릭
- 오늘 pending 상태
- range 시작·종료 정렬과 week column 구성
- 오늘 이후 셀의 unavailable 상태와 locale calendar의 주 시작일
- CloudKit 중복 대표 선택 후 동일 결과 보장

UI에는 날짜 계산과 강도 임계값을 복제하지 않는다.

## 13. 공통 UI와 플랫폼 호스트

### 공유 컴포넌트

`shared/Core/Components`에 모델 객체를 직접 받지 않는 순수 SwiftUI 컴포넌트를 둔다.

```text
ActivityHeatmapView
  input: [ActivityDaySummary]
  range: ActivityHeatmapRange
  palette: ActivityHeatmapPalette
  selectedDayKey
  interaction callbacks
```

- ModelContext, CloudKit, app navigation을 참조하지 않는다.
- 셀 geometry와 날짜 hit testing을 한 구현으로 공유한다.
- iPhone/iPad/macOS 호스트는 범위, 폭, hover와 키보드 행동만 전달한다.

### 플랫폼 호스트

- `MobileActivityOverview`: iPhone/iPad size class와 세로/가로 배치
- `DesktopActivityOverview`: hover, keyboard focus, Archive header mode switch
- `ArchiveOverviewMode`: `activity`, `statistics`
- 기존 macOS/mobile 통계 View는 같은 프레젠테이션 값과 문구를 사용하도록 정리한다.
- overview 선택은 전용 `@AppStorage` key로 기기 로컬에만 저장한다.
- UI test에서는 `--ui-testing-archive-mode activity|statistics` launch argument가
  저장값보다 우선하도록 해 테스트 순서의 영향을 없앤다.

새 앱 소스 파일은 `PlanBase.xcodeproj/project.pbxproj`에서 해당 target membership과
Xcode group에 함께 등록한다. 단, macOS 위젯 세션이 끝나기 전에는 project 파일을
편집하지 않는다. SwiftPM 경로 아래 파일은 자동 발견을 사용한다.

## 14. 백업과 CloudKit

### 백업

- JSON 호환 `BackupPayload` 끝에 optional `taskCompletionActivities` 배열을 추가한다.
- `BackupPackageCodec.currentVersion`은 6, supported range는 `2...6`으로 올린다.
  `BackupCodec.currentVersion`은 JSON V1 호환을 위해 1로 유지한다.
- 새 package V6는 `taskCompletionActivities != nil`을 필수로 검증한다. V2~V5와
  JSON V1에서만 nil을 허용해 손상된 V6가 조용히 통과하지 않게 한다.
- JSON V1 decoder는 optional 활동 배열을 허용하되 기본 내보내기는 계속 package V6를
  사용한다. 구형 decoder가 모르는 필드를 무시하는 호환성은 fixture로 고정한다.
- 이전 백업에는 배열이 없으면 빈 값으로 읽고 현재 완료 Task로 가능한 범위만 backfill한다.
- DTO 변환, makePayload, replaceAll, validation, checksum, merge, 동일성 비교와
  instanceID 충돌 검사에 활동 레코드를 포함한다.
- validation은 날짜 키, 유한한 날짜, origin, 결정적 논리 ID, instanceID, timestamp를
  검사하되 Task가 없는 activity는 허용한다.
- 같은 백업을 반복 가져와도 `(id, instanceID)` 후보가 중복 결과를 만들지 않는다.
- Task가 없는 활동 레코드도 유효한 익명 기록으로 보존한다.
- macOS 백업 import가 성공하면 mobile과 동일하게
  `PersistenceCommandService.dataChangedNotification`을 게시한다.
- 활동 이력이 커졌을 때 records metadata 10MB 제한을 실제 fixture로 먼저 검증하고,
  근거 없이 제한을 올리지 않는다.
- 호환성 표를 테스트와 문서에 둔다. 새 앱은 V2~V6 package와 JSON V1을 읽지만 구형
  앱은 새 V6 package를 읽지 못할 수 있다.

### CloudKit

- V7 Development schema에 활동 모델을 추가한다.
- `CloudKitDevelopmentSchema`가 V7 models를 사용하도록 갱신하지 않으면 Development
  record type이 생성되지 않으므로 schema 전환 체크리스트에 포함한다.
- iPhone 완료 → Mac/iPad 히트맵, Mac 완료 → iPhone/iPad 히트맵 수렴을 확인한다.
- 서로 다른 두 기기가 같은 Task를 같은 날 완료한 충돌 fixture를 검증한다.
- `CloudKitProbeKind.activity`, 활동 전용 writer/reader/cleanup probe와
  `run-cloudkit-convergence.sh` kind 허용값을 추가한다.
- probe cleanup은 제품의 Task 삭제 시 활동 보존 정책과 별개로 probe token으로 만든
  Activity만 명시적으로 정리하고 일반 사용자 Activity는 건드리지 않는다.
- Task 완료 취소와 삭제 후에도 양 기기의 활동일이 동일하게 남는지 확인한다.
- V6/V7 혼합 버전에서 늦게 도착한 captured Activity가 legacy backfill을 이기는지
  검증한다.
- Development 검증과 백업 round trip이 끝나기 전 Production schema를 배포하지 않는다.
- 실기기 절차는 `docs/CLOUDKIT_SYNC.md`를 따른다.

위젯은 이번 변경에서 SwiftData를 열지 않고 기존 App Group snapshot만 계속 사용한다.
`CalendarWidgetSnapshotPublisher`의 `shared/WidgetSupport` 이동을 되돌리거나 snapshot
형식에 활동 필드를 미리 추가하지 않는다.

## 15. 예상 파일 변경

### 공통 코어

- 신규 `shared/Core/Persistence/EasyTaskSchemaV7.swift`
- 수정 `shared/Core/Persistence/EasyTaskMigrationPlan.swift`
- 수정 `shared/Core/Persistence/PlanBaseContainerFactory.swift`
- 수정 `shared/Core/Persistence/CloudKitDevelopmentSchema.swift`
- 수정 `shared/Core/Models/AppModels.swift`
- 수정 `shared/Core/Services/DataIntegrityRecord.swift`
- 신규 `shared/Core/Services/TaskActivityRules.swift`
- 신규 `shared/Core/Services/TaskActivityService.swift`
- 신규 `shared/Core/Services/TaskActivityBackfillService.swift`
- 신규 `shared/Core/Services/TaskActivityIntegrityService.swift`
- 신규 `shared/Core/Services/TaskActivityImportCoordinator.swift`
- 신규 `shared/Core/Services/ActivityOverviewSession.swift`
- 신규 또는 확장 `shared/Core/Services/TaskLifecycleService.swift`
- 수정 `shared/Core/Services/TaskRules.swift`
- 수정 `shared/Core/Services/SeedService.swift`
- 수정 `shared/Core/Services/DataIntegrityService.swift`와 관련 normalization/convergence 파일
- 수정 `shared/Core/Services/BoundedQueryService.swift`
- 수정 `shared/Core/Services/BackupModels.swift`
- 수정 `shared/Core/Services/BackupCodec.swift`
- 수정 `shared/Core/Services/BackupPackageCodec.swift`
- 수정 `shared/Core/Services/BackupRecordConversions.swift`
- 수정 `shared/Core/Services/BackupPackageRecordMerge.swift`
- 수정 `shared/Core/Services/BackupPackageMergeValidation.swift`
- 수정 `shared/Core/Services/CloudKitConvergenceProbe.swift`
- 수정 `shared/Core/Services/CloudKitSyncService.swift`
- 신규 `shared/Core/Services/CloudKitActivityConvergenceProbe.swift`
- 신규 `shared/Core/Components/ActivityHeatmapView.swift`
- 수정 `shared/Core/Theme/AppTheme.swift`

### macOS

- 수정 `desktop/App/Features/Archive/ArchiveView.swift`
- 신규 `desktop/App/Features/Archive/DesktopActivityOverview.swift`
- 필요 시 수정 `desktop/App/Features/Archive/ArchiveControls.swift`
- 수정 `desktop/App/Features/Board/BoardView.swift`
- 수정 `desktop/App/Features/Board/DesktopTaskDetailSheet.swift`
- 수정 `desktop/App/Services/BackupService.swift`
- 수정 `desktop/App/AppRootView.swift`의 완료 command 호출부

### iPhone/iPad

- 수정 `mobile/App/Features/Archive/MobileArchiveView.swift`
- 신규 `mobile/App/Features/Archive/MobileActivityOverview.swift`
- 수정 `mobile/App/Features/Board/MobileBoardView.swift`
- 수정 `mobile/App/Features/Board/MobileTaskDetailSheet.swift`
- 수정 `mobile/App/Features/Board/MobileCarryoverSheet.swift`
- 수정 `mobile/App/PlanBaseMobileApp.swift`의 UI fixture
- 수정 `mobile/Tests/PlanBaseLaunchUITests.swift`

### 테스트

- 신규 `shared/Tests/TaskActivityRulesTests.swift`
- 신규 `shared/Tests/TaskActivityServiceTests.swift`
- 신규 `shared/Tests/TaskActivityBackfillServiceTests.swift`
- 신규 `shared/Tests/TaskActivityImportCoordinatorTests.swift`
- 신규 `shared/Tests/ActivityOverviewSessionTests.swift`
- 수정 `shared/Tests/SchemaMigrationTests.swift`
- 수정 `shared/Tests/DataIntegrityTests.swift`
- 수정 `shared/Tests/DataSafetyTests.swift`
- 수정 backup codec/package/merge 테스트
- 수정 `shared/Tests/CloudKitConvergenceProbeTests.swift`
- 수정 `shared/Tests/CloudKitConfigurationTests.swift`
- 수정 `shared/Tests/AppThemeTests.swift`
- 수정 `scripts/run-cloudkit-convergence.sh`
- 필요 시 macOS UI smoke fixture 추가

### 구현 완료 후 문서

- `AGENTS.md`, 루트 `README.md`, `docs/ARCHITECTURE.md`, `docs/CLOUDKIT_SYNC.md`의
  현재 schema와 백업 버전 설명을 실제 구현 상태에 맞춰 갱신한다.
- schema/백업 버전을 구현 전에 미리 문서에서 올리지 않는다.

## 16. macOS 위젯 세션과 동시 작업 경계

macOS 네이티브 위젯 작업이 같은 worktree에서 진행 중이다. 완료 안내를 받기 전에는
다음 파일과 범위를 편집, 복원, 재생성하거나 이전 위치로 되돌리지 않는다.

- `PlanBase.xcodeproj/project.pbxproj`
- `desktop/App/AppRootView.swift`
- `desktop/App/Features/Calendar/CalendarView.swift`
- `desktop/Configuration/PlanBase-macOS*.entitlements`
- `desktop/Configuration/PlanBase-macOS-Info.plist`
- `desktop/Configuration/PlanBaseWidget-macOS.entitlements`
- `mobile/App/PlanBaseMobileApp.swift`
- `mobile/Widget/*`
- `shared/WidgetSupport/CalendarWidgetSnapshotPublisher.swift`
- `shared/Core/Theme/AppTheme.swift`
- `shared/Tests/AppThemeTests.swift`
- 위젯 관련 테스트와 `scripts/verify-platform-builds.sh`
- `AGENTS.md`, 루트 `README.md`, `docs/ARCHITECTURE.md`

위젯 완료 전에는 V7 schema/migration, lifecycle/activity service, integrity, backup,
bounded query, 순수 규칙과 관련 SwiftPM 테스트만 진행한다. 기존 Archive/Board 파일은
공통 파일을 건드리지 않는 범위에서만 수정할 수 있지만, 새 앱 파일의 target 등록과
테마 연결이 필요하므로 플랫폼 UI 통합은 위젯 handoff 뒤에 실행한다.

검증과 Git 작업은 다음 경계를 지킨다.

- SwiftPM은 세션 전용 `--scratch-path`를 사용한다.
- Xcode는 위젯 완료 후 세션 전용 `-derivedDataPath`를 사용한다.
- `git add .` 또는 전체 파일 commit을 사용하지 않고 활동 스트릭 세션이 수정한 파일만
  명시적으로 stage한다.
- 다른 세션 변경을 reset, checkout, 삭제하거나 project 파일을 재생성하지 않는다.
- 위젯 세션 handoff에서 전달한 최신 공통 파일과 검증 결과를 기준으로 theme와 target
  membership 변경을 다시 대조한다.

## 17. 단계별 실행 계획

### Phase 0 — 기준 화면과 fixture 고정

- [x] 위젯 세션이 수정한 파일과 활동 세션 소유 파일을 `git status --short`로 구분한다.
- [x] 위젯 세션 소유 파일을 편집하지 않고 세션 전용 DerivedData로 현재 Xcode
  Debug/Release baseline을 검증한다.
- [x] 활동 없음, 1/2/3/5개 완료일, 현재 스트릭, 중간 공백, 오늘 pending fixture를 만든다.
- [x] `원래 날짜에 완료`, 완료 취소, Task 삭제, CloudKit 중복 fixture를 포함한다.
- [x] `captured` 지연 도착, UTC legacy 날짜, 365일 최고, 365일보다 긴 현재 스트릭
  fixture를 포함한다.
- [x] 원본 `completedAt`이 없어 기존 integrity가 날짜를 보완한 legacy fixture를
  포함한다.
- [x] 세션 전용 scratch path로 현재 SwiftPM Debug/Release 결과를 기록한다.

완료 조건:

- 기존 데이터 의미와 화면 기준을 재현할 수 있다.
- fixture의 실제 행동일과 Task 완료일 차이가 명확하다.

### Phase 1 — V7과 활동 기록 수명주기

- [x] V1~V6를 수정하지 않고 V7 모델을 추가한다.
- [x] 모든 non-optional 기본값, 명시적 initializer, 날짜/자연 키/cross-day local
  index와 origin을 추가한다.
- [x] V6 → V7 lightweight migration을 추가한다.
- [x] `PlanBaseContainerFactory.schema`, current-store compatibility, recognized-store 목록과
  `CloudKitDevelopmentSchema`를 모두 V7로 갱신한다.
- [x] `AppModels.swift` 공개 alias와 `DataIntegrityRecord` 적합성을 추가한다.
- [x] V6 파일 저장소 직접 migration, V7 재개방, V7 store 인식과 unknown checksum
  회귀 테스트를 추가한다.
- [x] `(taskId, activityDayKey)` 결정적 논리 ID 규칙을 구현한다.
- [x] canonical input, UUID v8 nibble과 RFC 4122 variant bit의 고정 test vector를
  추가한다.
- [x] `TaskLifecycleService`로 모든 production 완료 경로를 수렴시킨다.
- [x] 호출부만 소유한 한 `PersistenceCommandService.perform`에서 같은 `now`로 Task와
  활동을 저장하고 중첩 perform이 없는지 테스트한다.
- [ ] 모든 호출부 전환 뒤 우회 가능한 `TaskRules` 완료 API를 `package`로 낮춘다.
- [x] 완료 취소와 삭제가 활동 레코드를 지우지 않는 테스트를 추가한다.
- [x] 같은 Task의 같은 날 재완료는 1개, 다른 날 재완료는 각 1개가 되는지 검증한다.
- [x] backdated 완료가 실제 행동일에 기록되는지 검증한다.
- [x] `SeedService`의 완료 fixture에 명시적 활동 fixture를 추가한다.
- [ ] 보호 중인 두 앱 루트의 UI fixture 완료 경로를 lifecycle service로 전환한다.

완료 조건:

- V6→V7 migration과 V7 재개방이 기존 데이터를 변경하지 않고 통과한다.
- 저장 실패 시 Task와 활동 레코드가 함께 rollback한다.

### Phase 2 — 무결성·백업·CloudKit 기반

- [x] 활동 중복 대표 선택과 supersede 규칙을 `DataIntegrityService`에 추가한다.
- [x] invalid semantic record supersede, canonical ID 정규화, origin 우선순위와
  indexed cross-day captured 승격을 추가한다.
- [x] cross-day 후보가 서로 다른 pagination page에 있어도 수렴하는지 검증한다.
- [x] 초기 저장소, legacy backup, CloudKit 안정화 후 bounded backfill을 구현한다.
- [x] 기존 integrity가 보완한 `completedAt`도 legacy 추론으로 backfill되는지 검증한다.
- [x] `TaskActivityImportCoordinator`의 취소·교체, Clock 기반 debounce와 늦은 captured
  도착을 테스트한다.
- [x] CloudKit 일반 DataIntegrity는 즉시 수행되고 activity만 지연되는지 기존
  `CloudKitConfigurationTests`에 고정한다.
- [x] orphan 활동 레코드를 보존하는 정책을 테스트한다.
- [x] package V6 write/필수 activity 검증, V2~V5 read compatibility를 구현한다.
- [x] JSON codec version이 1로 유지되는지 테스트한다.
- [x] JSON V1과 이전 package import 후 가능한 backfill을 검증한다.
- [x] 같은 백업 반복 병합과 checksum/validation 실패 rollback을 검증한다.
- [ ] 큰 활동 fixture로 metadata 10MB 제한을 검증한다.
- [x] macOS import 성공 시 data-changed notification을 추가한다.
- [x] activity CloudKit probe, enum과 cleanup을 구현한다.
- [x] 검증 스크립트에 activity probe 허용 kind를 병합한다.
- [x] Development schema 정의를 V7로 갱신하고 Production 배포는 보류한다.

완료 조건:

- migration, backup round trip, merge, duplicate convergence 테스트가 통과한다.
- 새 앱은 V2~V6 package/JSON V1을 읽고 기존 Task 의미를 변경하지 않는다.
- V6/V7 혼합 버전과 구형 앱의 새 package 읽기 제한이 문서화된다.

### Phase 3 — 조회 규칙과 세션

- [x] 날짜별 집계·강도·범위 밖 현재 스트릭·최근 365일 최고 규칙을 만든다.
- [x] 오늘 pending, 자정, 윤년, 연말/연초, 시간대 고정 DayKey 테스트를 추가한다.
- [x] locale 주 시작일, future unavailable 셀, compact 16주와 regular 52주를 검증한다.
- [x] `ActivityOverviewSession`의 bounded fetch, backward pagination, generation 기반
  cancellation, 자정/시간대/foreground refresh를 구현한다.
- [x] MainActor fetch 뒤 Sendable snapshot만 순수 계산에 전달하는지 Swift 6 검사를 한다.
- [x] 기존 `TaskHistoryStatistics` 문구를 간결한 프레젠테이션 값으로 정리한다.

완료 조건:

- UI 없이 같은 입력이 모든 플랫폼에서 같은 현재/최고 스트릭 결과를 만든다.
- 전체 테이블 live query 없이 최대 범위와 페이지 경계가 테스트로 고정된다.

### Phase 4 — 공유 히트맵과 iPhone/iPad UI

- [x] 위젯 handoff를 받고 최신 `AppTheme`, project file과 검증 스크립트 변경을 먼저
  검토한다.
- [x] `PlanBaseMobileApp`이 성공한 CloudKit import summary를 activity coordinator에
  예약하도록 연결한다.
- [x] 계산 프로퍼티 기반 `ActivityHeatmapPalette`와 모든 테마 대비 테스트를 추가한다.
- [x] 모델 비의존 `ActivityHeatmapView`를 구현한다.
- [x] `활동 / 통계` segmented picker와 기본 `활동` 선택을 추가한다.
- [x] `--ui-testing-archive-mode` override를 추가하고 각 UI test가 모드를 명시한다.
- [x] iPhone compact 16주 레이아웃을 구현한다.
- [x] iPad regular 52주와 size-class 기반 16/52주 전환을 구현한다.
- [ ] iPad 넓은 화면의 좌우 배치와 좁은 Split View 시각 QA를 완료한다.
- [x] 기본 상태에는 세 줄과 히트맵만 보이게 한다.
- [x] 날짜 선택 시 한 줄 상세만 점진적으로 노출한다.
- [x] future 셀 비활성, 빈 날짜 요약, 한 hit surface 좌표 매핑을 구현한다.
- [x] 기존 통계를 간결한 통계 보기로 이동한다.
- [x] 검색, 필터, 날짜별 기록 피드와 보드 이동의 기존 동작을 유지한다.
- [x] VoiceOver custom action과 adjustable action을 추가한다.
- [ ] 시각적으로 노출되는 44pt 이전/다음 날짜 대안을 추가한다.
- [x] 신규 공용 Swift 파일은 SwiftPM 자동 발견 경로에 두어 앱 project 등록을 피한다.

완료 조건:

- iPhone에서 가로 스크롤 없이 핵심 활동 정보가 보인다.
- iPad 모든 대표 폭에서 넓은 빈 공간이나 iPhone 확대판처럼 보이는 배치가 없다.
- 통계로 전환해도 피드의 검색·페이지 깊이가 초기화되지 않는다.

### Phase 5 — macOS UI

- [x] `AppRootView`가 성공한 CloudKit import summary를 activity coordinator에
  예약하도록 연결한다.
- [x] Archive 헤더에 native `활동 / 통계` 전환을 추가한다.
- [x] 52주 히트맵과 hover/click/keyboard 상태를 구현한다.
- [x] 좁은 창에서도 세로 배치와 가로 스크롤 없는 fallback을 유지한다.
- [x] 기존 통계와 기록 피드의 페이지네이션을 유지한다.
- [x] 신규 공용 Swift 파일은 SwiftPM 자동 발견 경로에 두어 앱 project 등록을 피한다.
- [x] iPhone/iPad와 같은 공용 규칙에서 스트릭·강도·문구가 나오게 한다.

완료 조건:

- macOS는 포인터와 키보드에 자연스럽고 모바일 UI를 확대 복사한 형태가 아니다.
- 데이터와 접근성 레이블은 모바일과 동일하다.

### Phase 6 — 시각 QA와 전체 회귀

- [x] 위젯 handoff 뒤 현재 기록 화면을 iPhone, iPad portrait/landscape, macOS 기본
  폭에서 캡처하고 변경 전후를 비교한다.
- [ ] iPhone 작은 화면과 접근성 초대형 글자 UI 테스트를 추가한다.
- [x] iPad portrait/landscape에서 활동 화면이 노출되는 UI 테스트를 추가한다.
- [ ] iPad 좁은 Split View UI 테스트를 추가한다.
- [ ] macOS 기본 폭과 좁은 폭을 수동/자동 확인한다.
- [x] 모든 테마 × Light/Dark palette 자동 테스트를 실행한다.
- [ ] 대표 4개 테마의 iPhone/iPad/macOS reference screenshot을 남긴다.
- [ ] VoiceOver, Differentiate Without Color, Increase Contrast, Reduce Motion을 확인한다.
- [x] 세션 전용 `--scratch-path`로 `swift test`와 `swift test -c release`를 실행한다.
- [x] 위젯 세션이 임시 DerivedData 수정을 완료한 최신
  `./scripts/verify-platform-builds.sh`를 실행한다.
- [x] 개별 Xcode 명령도 세션 전용 `-derivedDataPath`를 사용한다.
- [x] `PlanBaseMobileTests`와 iPhone/iPad `PlanBaseLaunchUITests`를 별도로 실행한다.
- [x] `git diff --check`를 통과한다.

완료 조건:

- 기존 기록/회고/통계 테스트가 회귀하지 않는다.
- 새 화면에서 잘림, 겹침, 불필요한 가로 스크롤과 색상 의존이 없다.

### Phase 7 — 실기기 CloudKit 출시 게이트

- [ ] 신버전 iPhone 완료가 신버전 Mac과 iPad 활동에 나타나는지 확인한다.
- [ ] Mac 완료가 iPhone/iPad에 수렴하는지 확인한다.
- [ ] 완료 취소·삭제·재완료·같은 날 충돌 시나리오를 확인한다.
- [ ] import 순서가 Task→Activity와 Activity→Task인 경우 모두 같은 결과인지 확인한다.
- [ ] V6 기기 완료 후 V7 백필, 뒤늦은 V7 captured 도착 수렴을 확인한다.
- [ ] 앱 재설치 후 CloudKit 활동 기록과 스트릭이 복구되는지 확인한다.
- [ ] 이전 백업과 새 V6 package의 호환성 표를 확인한다. 구형 앱이 새 package를 읽는
  양방향 호환을 보장한다고 표현하지 않는다.
- [ ] Development schema와 실제 데이터 검증 후에만 Production schema를 배포한다.

완료 조건:

- 세 플랫폼이 같은 날짜별 강도와 현재 스트릭을 표시한다.
- CloudKit Production 배포 체크리스트와 복구 백업이 준비돼 있다.

## 18. UI 테스트 식별자 제안

```text
archive-overview-mode
archive-overview-mode-activity
archive-overview-mode-statistics
activity-overview
activity-current-streak
activity-today-status
activity-heatmap
activity-selected-day-summary
activity-previous-day
activity-next-day
activity-retry
archive-statistics-overview
archive-statistics-retry
```

기존 `archive-overview` 식별자는 전환 기간 동안 통계 카드에 유지한 뒤 테스트를 새
식별자로 옮긴다. 모든 기록 UI test는 `--ui-testing-archive-mode`를 명시해 로컬
`@AppStorage` 값과 테스트 실행 순서에 의존하지 않는다.

## 19. 완료 기준

- 기록 화면을 열면 기본적으로 현재 스트릭과 히트맵을 바로 이해할 수 있다.
- 활동 화면의 상시 텍스트는 현재 스트릭, 오늘 상태, 최근 1년 최고 기록을 넘지 않는다.
- 히트맵의 색 농도와 스트릭 외곽선 의미가 분리돼 있다.
- 통계는 별도 보기에서 기존 계획일/완료일 의미를 정확히 유지한다.
- 완료 취소, Task 삭제, backdated 완료가 과거 활동일을 부정확하게 바꾸지 않는다.
- CloudKit import 순서와 무관하게 captured Activity가 legacy backfill보다 우선하고
  cross-day 추론 중복이 최종 수렴한다.
- macOS, iPhone, iPad가 같은 규칙 결과를 플랫폼에 맞는 배치로 표시한다.
- 모든 PlanBase 테마와 Light/Dark Mode에서 단계와 선택 상태를 구분할 수 있다.
- VoiceOver와 키보드로 작은 셀을 직접 누르지 않아도 날짜 활동을 탐색할 수 있다.
- schema migration, backup, CloudKit convergence, bounded query와 전체 회귀 게이트가
  통과한다.
- 실제 사용 검증 전에는 태그 분석, AI 요약, 포인트와 추가 차트를 섞지 않는다.

## 20. 후속 평가 항목

첫 배포 후 다음 질문에 실제 사용 근거가 생겼을 때만 범위를 확장한다.

1. 매일 스트릭이 주말 사용자에게 부담이 되는가?
2. 휴식 요일 또는 단순 pause가 필요한가?
3. 16주 iPhone 범위가 꾸준함을 판단하기에 충분한가?
4. 사용자가 히트맵 날짜에서 작업 제목까지 열기를 원하는가?
5. 통계에서 이전 기간 비교가 실제 다음 계획에 도움이 되는가?
6. 위젯에 `현재 스트릭 + 오늘 활동 여부`만 제공할 가치가 있는가?

후속 기능은 이 질문의 답을 기준으로 별도 active plan을 만든다.
