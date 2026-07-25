# 일정 재사용과 계획일·완료일 기록 개선 계획

기준일: 2026-07-25

## 1. 목표

다음 사용자 후기 두 건을 데이터 의미를 손상하지 않는 순서로 해결한다.

1. 같은 일정을 반복 입력할 때 이전 일정의 기간, 색상, 메모를 빠르게 재사용한다.
2. Task를 계획한 날짜와 실제 완료한 날짜를 기록과 통계에서 분리해 확인한다.

우선순위는 다음과 같다.

1. **P0 — 계획일·완료일 구분:** 기록의 신뢰도와 과거 회고의 정확도를 먼저 높인다.
2. **P1 — 일정 복제:** 기존 일정 하나를 선택해 다른 날짜에 동일한 설정으로 복제한다.
3. **P2 — 제목 기반 추천:** 제목 입력 중 최근의 유사 일정을 사용자가 선택해 적용한다.
4. **후속 과제 — 시간·반복 일정:** 현재 모델에 없는 시간대와 반복 규칙은 별도 스키마 계획으로 진행한다.

각 체크박스는 한 번에 하나씩 구현하고 관련 테스트를 통과한 뒤 다음 항목으로 이동한다.

## 2. 현재 코드 판정

### Task 날짜 데이터

현재 `Task`에는 이미 다음 날짜가 분리되어 있다.

- `plannedAt`, `plannedDayKey`: 현재 Task에 마지막으로 지정된 계획 날짜
- `completedAt`: 앱에서 완료 상태를 저장한 기술적 시각
- `completedDayKey`: 사용자가 Task를 완료한 날로 기록한 업무 수행일
- `archivedAt`, `archivedDayKey`: 완료 작업을 이후 보관한 날짜

`TaskRules.applyStatus(.done)`는 일반 완료 시 `completedAt`과 `completedDayKey`를
현재 시각 기준으로 기록한다. 사용자가 이월함의 `원래 날짜에 완료`를 명시적으로
선택하면 `completedAt`은 처리 시각, `completedDayKey`는 사용자가 지정한 원래 날짜가
된다. 따라서 사용자가 목요일 Task를 다른 날짜로 옮기지 않고 토요일에 완료한 후기
시나리오는 `EasyTaskSchemaV7`이나 migration 없이 표시·조회 정책부터 개선할 수 있다.

다만 `TaskRules.move`와 `bringToToday`는 `plannedAt`과 `plannedDayKey`를 새 날짜로
갱신한다. 현재 모델에는 최초 계획일이나 재계획 이력이 없으므로, 사용자가 목요일 Task를
금요일로 명시적으로 옮긴 뒤 완료하면 목요일은 복원할 수 없다. 이번 계획에서 `계획일`은
`최초 계획일`이 아니라 **완료 시점까지 마지막으로 지정된 계획일**을 뜻한다. 최초 계획과
모든 재계획 이력이 필요하면 별도 스키마 과제로 다룬다.

현재 기록 화면은 완료 Task를
`completedDayKey ?? archivedDayKey ?? plannedDayKey` 하나로만 묶는다. 작업 행도 대표
날짜 하나만 보여 주므로, 목요일 계획을 토요일에 완료하면 목요일 계획이었다는 맥락이
화면에서 사라진다.

### 일일 회고

`DailyReviewTaskSummaryRules`는 선택 날짜의 보드 작업을 상태별로 나누지만,
`그날 계획한 일`과 `그날 실제 완료한 일`을 별도 축으로 제공하지 않는다. 늦게 완료한
작업은 계획 날짜를 회고할 때와 완료 날짜를 회고할 때 서로 다른 의미로 보여야 한다.

### 일정 데이터

현재 `CalendarEvent`는 다음 값만 저장한다.

- 제목
- 시작일과 종료일
- 색상
- 메모

`CalendarEventRules.normalizedDraft`는 시작·종료를 일 단위로 정규화한다. 시간대와 반복
규칙은 현재 모델과 편집기에 존재하지 않는다. 따라서 첫 구현에서 안전하게 재사용할 수
있는 값은 제목, 포함 일수, 색상, 메모다.

### 통계

현재 별도의 통계 화면이나 공통 통계 규칙은 없다. 기록 화면의 조회 결과를 단순 집계하는
것과 전체 저장소를 새로 조회하는 것을 섞지 않고, 기간이 제한된 공통 규칙을 먼저 만든 뒤
기록 화면에 작은 요약으로 제공한다.

## 3. 확정 제품 결정

### 3.1 날짜 용어와 기준

| 용어 | 의미 | 기준 필드 |
|---|---|---|
| 계획일 | Task에 마지막으로 지정된 실행 예정일 | `plannedDayKey` |
| 완료일 | 사용자가 Task를 완료한 날로 기록한 업무 수행일 | `completedDayKey` |
| 완료 처리 시각 | 앱에서 완료 상태를 저장한 기술적 시각 | `completedAt` |
| 보관일 | 완료 Task를 화면에서 보관 처리한 날짜 | `archivedDayKey` |

- 보관일을 완료일로 표시하지 않는다.
- 화면에서 `원래 계획일` 또는 `최초 계획일`이라는 문구를 사용하지 않는다. 현재
  `plannedDayKey`로 보장할 수 있는 명칭은 `계획일`이다.
- 화면과 통계의 완료일은 `completedDayKey`를 뜻한다. `completedAt`은 레거시
  fallback과 진단에만 사용하며 별도 사용자 날짜 축으로 만들지 않는다.
- 기본 기록 기준은 기존 사용자 경험과 호환되는 `완료일`로 유지한다.
- 사용자는 기록 필터에서 `완료일 기준`과 `계획일 기준`을 전환할 수 있다.
- 같은 Task의 계획일과 완료일이 다르면 두 날짜를 한 행에 함께 표시한다.
- `원래 날짜에 완료`처럼 제품이 의도적으로 `completedDayKey == plannedDayKey`로
  처리한 동작은 기존 의미를 유지한다.
- 회고 자체는 계속 `DailyReview.dayKey`에 속한다. 날짜 기준 전환은 Task 묶음에만
  적용하며 회고의 작성 날짜를 이동시키지 않는다.

공통 날짜 기준은 다음 형태로 둔다.

```swift
public enum TaskHistoryDateBasis: String, CaseIterable, Identifiable, Sendable {
    case completed
    case planned

    public var id: String { rawValue }
}
```

완료일 기준 key의 fallback은 기존 데이터를 보호하기 위해 다음 순서를 사용한다.

```text
completedDayKey
→ completedAt으로 계산한 DayKey
→ archivedDayKey
→ plannedDayKey
```

`completedAt`만 남은 레거시 데이터는 당시 기기의 시간대를 보존하지 않으므로,
`DayKey.calendar`의 현재 시간대로 계산한 best-effort 완료일이다. 저장된
`completedDayKey`가 있으면 항상 그것을 우선하고, 레거시 fallback을 최초 기록 당시의
절대적인 업무 수행일로 설명하지 않는다.

계획일 기준은 항상 `plannedDayKey`를 사용한다.

### 3.2 기록 화면 표시

- 날짜 기준 선택은 iPhone과 macOS 기록 화면에 같은 의미로 제공한다.
- 섹션 문구는 기준에 따라 `그날 완료한 일` 또는 `그날 계획한 일`로 바꾼다.
- 계획일과 완료일이 다른 완료 Task는 `계획 7월 23일 · 완료 7월 25일`처럼 표시한다.
- 두 날짜가 같으면 중복 문구를 줄여 한 날짜로 표시한다.
- 검색어, 기간, 작업/회고 범위 필터와 날짜 기준은 함께 적용된다.
- 필터 초기화는 날짜 기준도 기본값인 `완료일`로 되돌린다.
- 날짜 기준은 다른 기록 필터와 같은 화면 세션 상태로만 다룬다. 첫 버전에는 별도
  `AppStorage`를 추가하지 않으며 화면을 새로 시작하거나 필터를 초기화하면 `완료일`로
  돌아간다. SwiftData와 CloudKit에는 저장하지 않는다.

### 3.3 회고와 통계

- 일일 회고의 Task 요약을 `선택 날짜에 계획한 작업`과 `선택 날짜에 실제 완료한 작업`으로
  분리한다.
- 계획 목록 안에서는 완료/진행/미완료 상태를 계속 구분한다.
- 다른 날 계획했다가 선택 날짜에 완료한 Task는 완료 축에 표시하되 계획일을 함께
  보여 준다.
- 같은 Task가 한 화면의 계획 축과 완료 축에 모두 해당할 수 있다. 이는 중복 데이터가
  아니라 서로 다른 질문에 대한 의도된 표현이다.
- 통계의 첫 범위는 선택 기간의 `계획 작업 수`, `완료 작업 수`, `계획일 내 완료`,
  `지연 완료`, `미완료`다.
- 완료율의 분모와 분자를 섞지 않는다. `계획 대비 완료율`은 기간 내 계획한 Task를
  코호트로 잡고 그 Task의 현재 완료 여부를 계산한다.
- 계획 코호트 안에서 공통 날짜 규칙으로 해석한 완료일이 `plannedDayKey`보다 같거나
  이르면 `계획일 내 완료`, 늦으면 `지연 완료`로 계산한다.
- 여기서 계획 코호트는 최초 계획 이력이 아니라 각 Task의 현재 `plannedDayKey`를
  사용한다. 재계획 전 날짜를 통계로 복원할 수 있는 것처럼 표현하지 않는다.
- `완료 작업 수`는 선택 기간에 공통 fallback으로 해석한 완료일이 속한 Task 수로 따로
  표시한다.
- 별도의 최상위 통계 탭은 만들지 않고 기록 화면의 기간 요약부터 제공한다.

### 3.4 일정 복제

- 사용자가 원본 일정과 대상 시작일을 명시적으로 선택한다.
- 제목, 포함 일수, 색상, 메모를 복사한다.
- 대상 시작일을 기준으로 원본과 같은 포함 일수가 되도록 종료일을 계산한다.
- 복제본은 새 `id`와 새 `instanceID`를 가진 독립 `CalendarEvent`다.
- 원본 일정에 연결된 Task의 `eventId`는 복사하지 않는다.
- 복제 저장은 `PersistenceCommandService.perform` 안에서 실행하고 실패 시 rollback한다.
- 일정을 실제 저장하기 전에 편집 화면에서 복제된 값을 수정할 수 있게 한다.

### 3.5 제목 기반 일정 추천

- 추천 원본은 별도 이력 테이블이 아니라 활성 `CalendarEvent`에서 찾는다.
- 앞뒤 공백과 대소문자를 정규화한 제목으로 최근 일정을 비교한다.
- 빈 제목에는 추천하지 않는다.
- 정확히 일치하는 제목을 우선하고, 그다음 접두어 일치 항목을 최근 수정 순으로 제공한다.
- 동일한 논리 일정의 CloudKit 중복은 `updatedAt`, `instanceID` 대표 선택 규칙으로
  하나만 노출한다.
- 같은 설정의 후보를 중복 표시하지 않고 최대 5개만 보여 준다.
- 입력 중에는 사용자가 이미 바꾼 값을 자동으로 덮어쓰지 않는다.
- 사용자가 후보를 탭하거나 키보드로 선택했을 때만 기간, 색상, 메모를 적용한다.
- 선택한 새 시작일은 유지하고 원본의 포함 일수만 적용한다.

## 4. 실서비스 벤치마크와 디자인 품질 기준

조사일: 2026-07-25

이 절의 목적은 다른 앱의 화면을 그대로 복제하는 것이 아니다. 실제 서비스에서 검증된
정보 구조와 상호작용 원칙을 추출하고, PlanBase의 현재 `AppTheme`, Apple 플랫폼 관습,
기존 화면 밀도에 맞게 다시 설계한다.

### 4.1 실서비스에서 가져올 원칙

| 서비스·근거 | 확인한 패턴 | PlanBase 적용 | 그대로 가져오지 않을 것 |
|---|---|---|---|
| [Apple Calendar의 기존 이벤트 제안](https://support.apple.com/en-ca/guide/calendar/icalwr13-events/mac) | 이벤트 제목을 입력하면 기존 이벤트 기반 제안이 나타나고, 사용자가 제안을 선택하면 세부 정보를 채우며 `Esc`로 무시할 수 있다. 새 시간을 먼저 입력하면 기존 세부 정보만 다른 시간에 재사용할 수 있다. | 제목 기반 추천은 현재 시작일을 유지한 채 기존 기간·색상·메모를 적용하는 선택형 후보로 만든다. 후보 선택 전에는 draft를 바꾸지 않는다. | 이번 단계에서 자연어 날짜 파서, 시간 입력, 반복 규칙까지 함께 구현하지 않는다. |
| [Fantastical 이벤트·Task 템플릿](https://flexibits.com/fantastical/help/adding-events-and-tasks) | 기존 항목을 템플릿으로 저장하고, 새 항목 생성 화면 안에서 선택한 뒤 세부 값을 검토·수정하고 최종 저장한다. 템플릿 노출도 사용자가 켜고 끌 수 있다. | 일정 복제와 최근 일정 추천은 편집기 안에 draft로 적용하고 사용자가 저장 전에 날짜·색상·메모를 확인하게 한다. | 제목 입력만으로 폼 전체를 자동 덮어쓰거나 별도 템플릿 관리 화면을 첫 버전에 추가하지 않는다. |
| [Todoist Task 복제](https://www.todoist.com/help/articles/introduction-to-tasks-080OAXric) | 단일 항목 복제는 Task의 더보기 또는 context menu에 둔다. 복제는 주 행동이 아니라 기존 항목에서 시작하는 보조 행동이다. | iPhone의 일정 메뉴와 macOS context menu에 `일정 복제`를 배치한다. 캘린더 헤더에 별도 복제 버튼을 늘리지 않는다. | Todoist의 시각 스타일, 빨간 강조색, 메뉴 구성을 복제하지 않는다. |
| [Apple Reminders 템플릿](https://support.apple.com/en-gb/guide/iphone/iph3735c6147/ios) | 기존 목록을 템플릿으로 저장하고 새 목록을 만들며, 원본·템플릿·생성된 목록의 이후 변경은 서로 전파되지 않는다. | 복제 일정은 원본과 연결되지 않는 독립 레코드로 만들고, 원본 수정이 복제본에 전파될 것처럼 보이는 문구를 사용하지 않는다. | 첫 버전에 별도 템플릿 보관함·공유·관리 화면을 추가하지 않는다. |
| [Sunsama 계획 시간과 실제 시간](https://help.sunsama.com/docs/usage-guides/tasks/planned-and-actual-times/) | 계획값과 실제값을 서로 다른 의미로 유지하며, 일별 화면과 누적 상세에서 집계 범위를 명확히 구분한다. | `계획일`과 `완료일`을 명시적인 label로 한 행에서 비교하고, 기록 필터와 통계에 현재 날짜 기준을 표시한다. | 시간 추적 UI나 timer를 이번 날짜 기록 기능에 섞지 않는다. |
| [Things 날짜 목록과 Logbook](https://culturedcode.com/things/support/articles/4001304/) | Today·Upcoming은 지금 할 일과 미래 일을 분리하고, Logbook은 완료 기록을 조용한 날짜 흐름으로 보존한다. | 기록 화면은 날짜와 작업 제목을 먼저 읽게 하고, 통계·필터·보조 정보는 점진적으로 공개한다. | Things의 고유 타이포그래피, 노란 별, 여백 수치를 모사하지 않는다. |
| [Apple HIG](https://developer.apple.com/design/human-interface-guidelines)와 [UI Design Dos and Don’ts](https://developer.apple.com/design/tips/) | 플랫폼 일관성, 명확한 위계, 콘텐츠 가까이에 있는 제어, 44pt 터치 영역, 읽을 수 있는 대비와 정렬을 우선한다. | SwiftUI `Form`, `List`, `Menu`, `Picker`, `contextMenu`, SF Symbols와 시스템 텍스트 스타일을 우선 사용한다. | 웹 dashboard 문법이나 커스텀 컨트롤을 Apple 기본 패턴보다 먼저 도입하지 않는다. |

벤치마크에서 확정한 조합은 다음과 같다.

1. 제목 추천은 Apple Calendar처럼 기존 일정에서 찾되, 사용자가 후보를 선택하거나
   무시할 수 있게 한다.
2. 일정 재사용은 Fantastical처럼 `추천 선택 → 내용 검토 → 저장`의 명시적 흐름으로 만든다.
3. 정확 복제는 Todoist처럼 원본 일정의 보조 메뉴에서 시작한다.
4. 복제본은 Apple Reminders 템플릿 결과처럼 원본과 독립된 snapshot으로 취급한다.
5. 날짜 기록은 Sunsama처럼 계획과 실제를 같은 맥락 안에서 비교하되 label을 생략하지 않는다.
6. 기록의 전체 인상은 Things처럼 차분한 시간순 목록으로 유지한다.
7. 최종 외형과 조작 방식은 Apple 플랫폼 관습과 PlanBase의 기존 테마가 결정한다.

### 4.2 화면별 UI/UX 결정

#### 기록과 회고

- 날짜 기준은 iPhone에서 필터 sheet의 compact picker, macOS에서 기존 controls의 picker로
  제공한다. 화면 상단에 별도 대형 전환 카드나 새 navigation bar를 만들지 않는다.
- 날짜 기준의 선택지는 두 개뿐이므로 iPhone과 macOS 모두 기존 필터 안의 segmented
  `Picker`를 우선 사용한다. 접근성 글자 크기에서 잘리면 메뉴형 `Picker`로 전환한다.
- 작업 행의 첫 읽기 순서는 `제목 → 상태 → 계획일·완료일`이다.
- 날짜가 다르면 `계획 7월 23일 · 완료 7월 25일`처럼 한 줄의 보조 정보로 표시한다.
  두 날짜를 각각 색이 다른 카드나 badge로 분리하지 않는다.
- 같은 날짜면 `계획·완료 7월 25일`처럼 중복을 줄이되 VoiceOver에서는 두 의미를 모두
  읽는다.
- 기록 기간 통계는 화면 전체를 덮는 dashboard가 아니라 기존 기록 요약과 같은 밀도의
  compact summary로 둔다. 5개의 동일 카드 그리드는 만들지 않는다.
- 회고의 `그날 계획한 일`과 `그날 실제 완료한 일`은 제목·개수·목록으로 구분하고,
  장식용 아이콘이나 색상만으로 차이를 표현하지 않는다.

#### 일정 복제와 추천

- iPhone은 기존 편집 버튼을 유지하고, 현재 직접 노출된 삭제 버튼 자리를
  `ellipsis` `Menu`로 바꿔 `일정 복제`와 `삭제`를 함께 제공한다. 행을 길게 눌렀을 때도
  같은 동작을 제공한다.
- macOS는 월간 이벤트 막대와 날짜 inspector 행의 `contextMenu`에 `일정 복제`를
  추가하고 기존 편집·삭제 버튼은 유지한다.
- 복제를 선택하면 대상 날짜가 반영된 기존 일정 편집 sheet를 열고, 상단에
  `복제한 일정`이라는 짧은 맥락만 표시한다. 별도 wizard는 만들지 않는다.
- 최근 일정 추천은 제목 입력 바로 아래에 최대 5개까지 표시하되, 각 후보는
  `제목 · N일 · 색상 · 메모 유무`만 보여 주는 짧은 행으로 만든다.
- 후보마다 그림자 있는 독립 카드를 만들지 않고 현재 `Form`/편집기 행의 시각 언어를
  재사용한다.
- 추천 선택 후 `이전 일정의 기간·색상·메모를 적용했어요`처럼 한 번 피드백하고,
  사용자가 바꾼 값을 다시 자동 적용하지 않는다.
- 추천이 없으면 빈 추천 영역이나 설명 카드를 노출하지 않고 기존 편집기 높이를 유지한다.
- 추천 후보가 보이는 동안에도 `취소`와 `추가`/`저장`의 기존 toolbar·button 위계는
  바꾸지 않는다. 추천은 저장을 대신하는 주 행동이 아니다.

#### iPhone과 macOS의 차이

- iPhone은 한 손 조작, 44pt 터치 영역, sheet 안의 세로 읽기 순서를 우선한다.
- macOS는 context menu, keyboard focus, 위/아래 이동과 Return 선택을 제공하되
  iPhone보다 더 큰 카드나 모바일 sheet 외형을 그대로 이식하지 않는다.
- 두 플랫폼은 데이터 의미, 문구, 후보 정렬은 공유하지만 컨트롤 배치까지 억지로
  동일하게 만들지 않는다.

### 4.3 AI가 만든 듯한 획일화를 피하는 기준

관련 근거는 다음과 같다.

- [Figma, 5 shifts redefining design systems in the AI era](https://www.figma.com/blog/5-shifts-redefining-design-systems-in-the-ai-era/):
  AI가 제품 맥락 없이 만든 결과는 팀의 방향에서 벗어나고 고유한 뉘앙스를 평평하게 만들기
  쉬우므로, 디자인 시스템에 결정·기준·맥락을 명시해야 한다.
- [Figma, What is good design in the age of AI?](https://www.figma.com/blog/what-is-good-design-in-the-age-of-ai/):
  AI는 관습적인 기준점을 빠르게 만들 수 있지만, 사용자 문제와 새로운 관점은 사람이
  더해야 한다. 거대한 추상 프롬프트보다 적은 수의 구체적이고 적용 가능한 원칙이 낫다.
- [Figma Make Designs 회고](https://www.figma.com/blog/inside-figma-a-retrospective-on-make-designs/):
  AI 결과는 첫 초안이며 의미 있는 경험으로 다듬는 책임은 디자이너에게 있다.
- [Built In, AI Makes Bad Design Look Good Enough](https://builtin.com/articles/ai-design-slop-era):
  기술적으로 맞지만 제품 정체성과 관점이 없는 상호 교환 가능한 UI가 신뢰를 낮출 수
  있다는 업계 비평이다.

PlanBase에서는 이를 다음과 같이 운영한다.

1. **AI는 초안을 만들고 제품 규칙이 최종 형태를 결정한다.**
   첫 생성 결과를 그대로 구현하지 않는다. 현재 화면, 실제 데이터, 기존 컴포넌트와
   나란히 비교한 뒤 정보 위계가 더 명확한 부분만 채택한다.
2. **새 기능을 새 미술 스타일로 표현하지 않는다.**
   `AppTheme`, 시스템 글꼴, SF Symbols, 현재 8·12·16pt 계열 여백과 기존 8~16pt
   corner radius 범위 안에서 조정한다. 기능 하나 때문에 새로운 색 체계나 재질을
   도입하지 않는다.
3. **제품 고유성은 장식보다 데이터 의미에서 만든다.**
   PlanBase의 차별점은 계획일·완료일의 정확한 관계, 날짜별 회고, 일정과 Task의 연결이다.
   이를 읽기 쉽게 만드는 것이 임의의 그래픽 효과보다 우선한다.
4. **실제 한국어 콘텐츠로 설계한다.**
   lorem ipsum이나 짧은 영어 placeholder 대신 `공장`, 긴 일정 제목, 지연 완료,
   메모 있음/없음, 0·1·여러 개 결과 fixture로 화면을 검토한다.
5. **한 화면에는 하나의 주 행동만 직접 강조한다.**
   복제·필터·추천은 맥락에 맞는 보조 행동으로 두고, 같은 크기·색의 CTA를 여러 개
   나열하지 않는다.
6. **정보 밀도를 인위적으로 낮추지 않는다.**
   생산성 앱에 불필요한 hero 영역, 설명용 대형 카드, 과도한 빈 공간을 추가하지 않는다.
   사용자가 날짜·제목·상태를 빠르게 훑을 수 있는 밀도를 유지한다.
7. **사람이 시각 검토를 끝내기 전에는 완료로 보지 않는다.**
   기본/다크 모드, 작은 iPhone, macOS 창, Dynamic Type, 실제 fixture를 캡처하고
   기능을 모르는 사람이 날짜 의미와 다음 행동을 설명할 수 있는지 확인한다.

다음 패턴은 이번 기능에서 명시적으로 금지한다.

- 의미 없는 보라·청록 gradient, neon glow, glassmorphism 또는 여러 겹의 반투명 재질
- 모든 내용을 같은 크기의 둥근 카드로 감싸는 dashboard식 card grid
- 아이콘을 다시 색상 원·사각형 안에 넣는 장식용 icon badge의 반복
- 과한 그림자, hover bounce, 목적 없는 animation과 숫자 count-up
- 큰 marketing headline, 감성적인 AI 문구, 기능을 설명하기 위한 장식 일러스트
- label 없는 아이콘, 색상만으로 구분한 계획/완료 상태, 실제 의미 없는 지표
- 다른 서비스의 색·타이포그래피·간격·고유 컴포넌트를 그대로 모사하는 방식

현재 PlanBase가 이미 사용하는 배경 gradient나 theme palette는 제거 대상이 아니다.
다만 이번 기능이 기존 스타일 위에 별도의 장식 gradient, glass, shadow 체계를 추가해서는
안 된다.

### 4.4 이후 AI 디자인 작업에 사용할 프롬프트

아래 프롬프트를 Phase별 화면 설계와 구현 요청의 공통 머리말로 사용한다. 대괄호 안만
현재 작업에 맞게 채우며, 한 번의 프롬프트로 전체 앱을 재디자인하지 않는다.

```text
역할:
PlanBase의 기존 디자인 언어와 Apple 플랫폼 관습을 지키는 제품 디자이너이자
SwiftUI 구현자다. AI가 만든 첫 초안을 그대로 채택하지 말고 사용자 과업을 기준으로
필요한 최소 변경만 제안한다.

사용자 과업:
[예: 목요일에 계획하고 토요일에 완료한 작업의 두 날짜를 오해 없이 확인한다.]

현재 화면과 제약:
- 현재 파일: [관련 SwiftUI 파일]
- 기존 컴포넌트와 토큰: AppTheme, 시스템 글꼴, SF Symbols, 기존 List/Form/Menu
- 유지할 정보 밀도와 읽기 순서: [현재 화면의 핵심 순서]
- 데이터 의미: [계획일/완료일 또는 일정 복제 규칙]
- iPhone과 macOS의 플랫폼별 차이: [필요한 차이]

참고할 상호작용 원칙:
- [Fantastical의 선택 후 검토 / Todoist의 보조 메뉴 / Sunsama의 계획·실제 비교 /
  Things의 조용한 기록 구조 중 관련 원칙]
- 외형, 색상, 타이포그래피, 고유 컴포넌트는 복제하지 않는다.

시각 방향:
- 콘텐츠가 장식보다 먼저 보이는 차분한 개인 생산성 도구
- 한 화면에 하나의 주 행동
- 기존 PlanBase 화면과 이 기능 사이에 새 디자인 시스템이 생긴 것처럼 보이지 않게 한다.
- 실제 한국어 fixture와 긴 제목, 빈 상태, 밀집 상태를 사용한다.

금지:
- 새 장식 gradient, neon, glassmorphism, 과한 shadow
- 동일 카드의 반복 grid, 불필요한 icon badge, hero 문구
- 자동 생성된 감성 문구, 색상만으로 전달하는 상태
- 추천을 선택하기 전에 사용자 입력값을 자동으로 덮어쓰기

산출물:
1. 사용자 과업과 현재 문제를 한 문단으로 설명한다.
2. 기존 컴포넌트를 재사용하는 저충실도 구조안 2개만 제시한다.
3. 각 안의 정보 위계, 주 행동, 접근성, 플랫폼 차이를 비교한다.
4. 더 단순한 안을 기본으로 선택하고 선택 이유와 버린 요소를 적는다.
5. 구현 후 작은 iPhone, macOS, light/dark, Dynamic Type, VoiceOver로 검토한다.
6. 마지막에 ‘AI 생성 UI처럼 보일 수 있는 요소’를 스스로 지적하고 불필요한 장식을
   제거한 뒤 결과를 제시한다.
```

### 4.5 디자인 승인 게이트

각 UI Phase는 다음 질문에 모두 `예`라고 답해야 완료한다.

- 현재 PlanBase 화면을 보지 않고 만든 독립 template처럼 보이지 않는가?
- 새 요소가 기존 `AppTheme`와 시스템 컴포넌트를 재사용하는가?
- 화면을 처음 본 사용자가 계획일과 완료일 또는 복제와 저장의 차이를 설명할 수 있는가?
- 장식을 하나씩 제거해도 의미가 유지되며, 남은 장식에는 정보 역할이 있는가?
- 실제 한국어 긴 제목, 빈 결과, 최대 후보, 지연 완료 fixture에서도 위계가 유지되는가?
- iPhone과 macOS가 같은 의미를 유지하면서 각 플랫폼에 자연스럽게 보이는가?
- VoiceOver, Dynamic Type, 키보드 조작에서 label과 순서가 시각 표현과 일치하는가?
- 비교 서비스의 화면을 베낀 것이 아니라 상호작용 원칙만 PlanBase식으로 재해석했는가?

### 4.6 현재 화면과 구현 연결점

| 화면 | 현재 구조 | 이번 기능의 삽입 위치 | 유지할 경계 |
|---|---|---|---|
| iPhone 일정 편집 | `MobileEventEditorSheet`의 `NavigationStack`과 `Form` | `일정` Section의 제목 입력 바로 아래에 최대 5개의 추천 행을 조건부 표시한다. 복제 draft도 같은 편집기를 연다. | 기존 `취소`·`추가/저장`, 기간·색상·메모 Section 순서와 저장 확인을 유지한다. |
| iPhone 날짜 상세 | `MobileCalendarDaySheet`의 `이벤트` Section | 편집 버튼은 유지하고 삭제 버튼 자리를 `ellipsis` `Menu`로 바꿔 `일정 복제`와 `삭제`를 제공한다. long press context menu도 같은 순서로 맞춘다. | 캘린더 헤더에 전역 복제 버튼을 추가하지 않고 파괴적 삭제를 메뉴 마지막에 둔다. |
| macOS 일정 편집 | `AddEventSheet`/`EventEditorSheet`의 380~400pt 고정 폭 편집기 | 제목 입력 아래에 키보드 이동이 가능한 짧은 추천 목록을 두고 동일한 공통 draft를 사용한다. | 모바일 `Form` 외형을 이식하지 않고 기존 버튼 행과 창 크기를 우선 유지한다. |
| macOS 캘린더 이벤트 | `CalendarEventSegmentButton`의 기존 context menu와 `DesktopCalendarDayInspector`의 일정 목록 | 월간 막대의 기존 context menu를 확장하고 inspector 행에도 같은 `일정 복제` context action을 추가한다. | inspector의 기존 편집·삭제 버튼은 유지하고 별도 전역 복제 버튼을 추가하지 않는다. |
| iPhone 기록 필터 | `MobileArchiveFilterSheet`의 `Form` | 기간보다 앞서 `날짜 기준` Section을 추가하고 두 선택지를 segmented `Picker`로 표시한다. | 검색 대상·사용자 지정 기간·초기화 동작과 medium/large detent를 유지한다. |
| macOS 기록 필터 | `ArchiveFilterPopover`와 filter chip | 기존 popover에 날짜 기준 picker를 추가하고 활성 기준을 chip 또는 현재 섹션 문구로 확인하게 한다. | 기록 toolbar에 새 상시 버튼을 추가하지 않는다. |
| 양 플랫폼 기록 행 | 기존 기록 카드/날짜 그룹의 보조 텍스트 | 제목과 상태 다음 줄에 계획일·완료일 관계를 한 줄로 표시한다. | 색상·아이콘만으로 의미를 전달하거나 날짜마다 독립 카드를 만들지 않는다. |

구현 전에 각 화면의 현재 light/dark 캡처를 기준점으로 남긴다. 구현 후에는 같은 fixture와
같은 창·기기 크기로 다시 캡처해 새 기능 때문에 기존 정보 밀도, 주 행동, 스크롤 시작점이
불필요하게 변하지 않았는지 비교한다.

## 5. 변경 경계와 데이터 안전

- `EasyTaskSchemaV1`~`V6`와 `EasyTaskMigrationPlan`을 수정하지 않는다.
- bundle ID, CloudKit container, App Group, 백업 UTI와 확장자를 수정하지 않는다.
- 첫 구현은 기존 필드만 사용하므로 백업 DTO와 codec format을 변경하지 않는다.
- `id`, `instanceID`, `supersededAt` 수렴 규칙을 우회하지 않는다.
- 기록과 추천 조회는 bounded descriptor/session을 사용하고 전체 테이블 상시 관찰을
  추가하지 않는다.
- 완료일 기준 조회에서 `completedAt` fallback은 dayKey 문자열 predicate에 억지로
  섞지 않는다. `completedDayKey`, `completedAt`, `archivedDayKey`, `plannedDayKey`
  우선순위별 descriptor를 분리하고 결과를 대표 레코드 규칙으로 병합한다.
- 전체 기간 통계는 무제한 객체 fetch 대신 `fetchCount` 또는 고정 크기 pagination으로
  계산한다.
- 위젯은 이번 범위에서 변경하지 않는다. 복제 후 iOS 앱의 기존 데이터 변경 알림과
  snapshot 발행 경로가 정상 동작하는지만 회귀 검증한다.
- 새 공통 규칙은 `shared/Core/Services`에 두고 SwiftPM 테스트를 먼저 작성한다.
- 플랫폼 UI에 날짜 판단이나 추천 정렬 규칙을 중복 구현하지 않는다.

시간대와 반복 규칙을 지원하려면 새 필드와 명확한 recurrence 정책이 필요하다. 이는
`EasyTaskSchemaV7`, migration, 백업, CloudKit schema, 위젯 표시 규칙을 함께 설계하는
별도 계획으로만 진행한다.

Task의 최초 계획일과 재계획 이력도 현재 필드만으로는 복원할 수 없다. 이 요구가 생기면
최초 계획일 단일 필드로 충분한지, 날짜 변경 이력 모델이 필요한지부터 결정하고 같은
스키마·migration·백업·CloudKit 절차를 거친다.

## 6. 단계별 실행 체크리스트

### Phase 0 — 기준점과 회귀 fixture 고정

- [x] `git status --short`로 다른 작업의 미커밋 변경을 확인하고 작업 범위를 분리한다.
- [x] `swift test`와 iOS/macOS Debug 빌드 결과를 기준점으로 기록한다.
- [x] 목요일 계획·토요일 완료 Task fixture를 만든다.
- [x] 계획일과 완료일이 같은 Task fixture를 만든다.
- [x] 완료일 필드가 비어 있고 보관일만 남은 레거시 호환 fixture를 만든다.
- [x] `completedDayKey`가 비어 있고 `completedAt`만 있는 레거시 완료 fixture를 만든다.
- [x] 시간대가 다른 환경에서 `completedAt` fallback의 dayKey와 안내 문구를 검증한다.
- [x] 목요일 Task를 금요일로 이동한 fixture로 `계획일`이 최초 날짜가 아님을 고정한다.
- [x] 같은 제목이지만 기간·색상·메모가 다른 최근 일정 fixture를 만든다.
- [x] 동일 논리 ID의 transient CalendarEvent 중복 fixture를 만든다.
- [x] 변경 전 iPhone/macOS 기록·회고·일정 편집 화면을 캡처한다.

완료 조건:

- 기존 테스트와 양 플랫폼 Debug 빌드가 통과한다.
- fixture가 실제 CloudKit에 접근하지 않고 메모리 또는 로컬 저장소에서 재현된다.

### Phase 1 — P0 공통 날짜 의미와 표시 규칙

#### 1.1 날짜 기준 규칙

- [x] `TaskHistoryDateBasis`를 공통 서비스에 추가한다.
- [x] 완료일 기준과 계획일 기준의 `dayKey` 계산을 한 helper로 통합한다.
- [x] `completedDayKey`가 비어 있는 기존 Task의 fallback 순서를 테스트한다.
- [x] 일반 완료, 원래 날짜 완료, 같은 날 완료의 의미가 기존 `TaskRules`와 일치하는지
  `TaskCompletionRulesTests`로 고정한다.
- [x] `TaskRules.move`와 `bringToToday` 이후 계획일이 마지막 지정 날짜가 되는 동작을
  회귀 테스트로 고정한다.
- [x] `TaskRules.applyStatus`의 저장 동작은 변경하지 않고 표현·조회 계층만 확장한다.

예상 파일:

- `shared/Core/Services/ArchiveQueryRules.swift`
- `shared/Core/Services/ArchivePresentationRules.swift`
- `shared/Core/Services/TaskRules.swift`
- `shared/Tests/TaskCompletionRulesTests.swift`
- `shared/Tests/ArchiveReviewRulesTests.swift`

#### 1.2 작업 행의 두 날짜 표시

- [x] 두 날짜가 다른 경우와 같은 경우의 표시 값을 공통 presentation rule로 만든다.
- [x] iPhone 기록 카드에 계획일·완료일을 표시한다.
- [x] macOS 기록 행에 같은 날짜 정보를 표시한다.
- [x] VoiceOver와 macOS 접근성 문구에서 `계획일`, `완료일` 의미를 생략하지 않는다.
- [x] 좁은 iPhone 화면에서 긴 제목과 두 날짜가 잘리지 않는지 확인한다.

예상 파일:

- `shared/Core/Services/ArchivePresentationRules.swift`
- `mobile/App/Features/Archive/MobileArchiveRecordCard.swift`
- `desktop/App/Features/Archive/ArchiveDayGroupView.swift`
- `shared/Tests/ArchiveReviewRulesTests.swift`

완료 조건:

- 목요일 계획·토요일 완료 Task가 어느 날짜 섹션에 있더라도 두 날짜를 확인할 수 있다.
- schema, migration, backup format에 diff가 없다.

### Phase 2 — P0 기록의 날짜 기준 필터와 bounded 조회

#### 2.1 필터 모델

- [x] `ArchiveFilter`에 날짜 기준을 추가하고 기본값을 `완료일`로 둔다.
- [x] `hasActiveCriteria`, `reset`, `Equatable` 동작을 날짜 기준과 함께 검증한다.
- [x] 날짜 기준 전환 시 debounce 없이 즉시 query session을 갱신한다.
- [x] 검색어·기간·scope와 날짜 기준의 조합 테스트를 추가한다.

#### 2.2 조회와 pagination

- [x] `ArchiveQueryRules.records`가 선택한 기준으로 Task를 묶게 한다.
- [x] `BoundedQueryService`의 Task predicate를 계획일/완료일 기준으로 명시적으로 분기한다.
- [x] 완료일 기준은 다음 결과를 별도 descriptor로 가져와 fallback 우선순위대로 병합한다.
  1. `completedDayKey`가 범위에 속하는 Task
  2. `completedDayKey == nil`이고 `completedAt`이 반열린 날짜 범위에 속하는 Task
  3. 위 두 값이 없고 `archivedDayKey`가 범위에 속하는 Task
  4. 위 세 값이 없고 `plannedDayKey`가 범위에 속하는 Task
- [x] `completedAt` 날짜 범위는 `DayKey`로 시작 시각과 종료 다음 날 시각을 계산해
  DST와 현재 시간대에서도 같은 dayKey가 되게 한다.
- [x] 날짜 extent와 다음 페이지 경계가 선택 기준을 사용하게 한다.
- [x] 완료일 extent가 `completedAt`만 남은 레거시 Task의 최소·최대 날짜를 포함하게 한다.
- [x] 페이지 경계에 걸친 지연 완료 Task가 누락되거나 중복되지 않는지 테스트한다.
- [x] 회고는 날짜 기준과 무관하게 `DailyReview.dayKey`를 유지하는지 테스트한다.
- [x] 검색된 체크리스트 항목이 올바른 날짜 기준의 Task에 귀속되는지 테스트한다.

예상 파일:

- `shared/Core/Services/ArchiveQueryRules.swift`
- `shared/Core/Services/ArchiveQuerySession.swift`
- `shared/Core/Services/BoundedQueryService.swift`
- `shared/Tests/ArchiveReviewRulesTests.swift`
- `shared/Tests/ArchiveQuerySessionTests.swift`
- `shared/Tests/BoundedQueryServiceTests.swift`

#### 2.3 양 플랫폼 필터 UI

- [x] iPhone 필터 sheet에 `완료일 기준`/`계획일 기준` 선택을 추가한다.
- [x] macOS 기록 controls에 동일한 선택을 추가한다.
- [x] 섹션 제목을 현재 기준에 맞게 표시한다.
- [x] 필터 초기화와 새 화면 세션에서 날짜 기준이 `완료일`로 돌아가는지 검증한다.
- [x] 빈 결과 화면이 현재 선택한 날짜 기준을 설명하게 한다.

예상 파일:

- `mobile/App/Features/Archive/MobileArchiveFilterSheet.swift`
- `mobile/App/Features/Archive/MobileArchiveView.swift`
- `desktop/App/Features/Archive/ArchiveControls.swift`
- `desktop/App/Features/Archive/ArchiveView.swift`

완료 조건:

- 후기 예시의 Task는 완료일 기준에서 토요일, 계획일 기준에서 목요일에 나타난다.
- 기간 필터와 pagination을 함께 사용해도 Task가 사라지거나 두 번 나타나지 않는다.

### Phase 3 — P0 회고의 계획 축·완료 축 분리

- [x] `DailyReviewTaskSummary`를 계획 작업과 실제 완료 작업을 함께 표현하도록 확장한다.
- [x] 계획 작업은 선택 날짜의 todo/doing/done을 상태별로 유지한다.
- [x] 완료 작업은 공통 fallback으로 해석한 완료일 기준으로 별도 계산한다.
- [x] 회고용 bounded query가 선택일의 계획 Task와 완료 Task를 함께 가져오고,
  `completedAt`만 남은 레거시 완료도 fallback으로 포함하게 한다.
- [x] 다른 날 계획한 지연 완료 Task에 계획일 표시를 추가한다.
- [x] 동일 날짜 계획·완료 Task의 의도된 양쪽 노출을 테스트한다.
- [x] transient Task 중복이 두 축에서 각각 한 번만 나타나는지 테스트한다.
- [x] iPhone 회고 작성 화면에 두 섹션을 적용한다.
- [x] macOS 회고 화면에 같은 의미의 두 섹션을 적용한다.
- [x] 오늘 이월 작업 정책과 새 완료 축이 충돌하지 않는지 기존 테스트를 유지한다.

예상 파일:

- `shared/Core/Services/DailyReviewTaskSummaryRules.swift`
- `shared/Core/Services/BoundedQueryService.swift`
- `shared/Tests/DailyReviewTaskSummaryRulesTests.swift`
- `shared/Tests/BoundedQueryServiceTests.swift`
- `mobile/App/Features/Review/MobileReviewComposerComponents.swift`
- `mobile/App/Features/Review/MobileReviewComposerSheet.swift`
- `desktop/App/Features/Archive/DiaryView.swift`
- `desktop/App/Features/Archive/DailyReviewSheet.swift`

완료 조건:

- 목요일 회고에서 그날 계획했던 Task를 확인할 수 있다.
- 토요일 회고에서 실제 토요일에 완료한 Task와 계획일을 확인할 수 있다.

### Phase 4 — P1 기록 기간 통계

- [x] `TaskHistoryStatisticsRules`의 입력·출력과 코호트 정의를 순수 값 타입으로 만든다.
- [x] 계획 작업 수, 완료 작업 수, 계획일 내 완료, 지연 완료, 미완료를 계산한다.
- [x] 완료일이 계획일보다 이른 경우도 `계획일 내 완료`로 계산하는지 테스트한다.
- [x] 완료일이 없는 done 레거시 Task의 fallback 정책을 날짜 규칙과 일치시킨다.
- [x] 선택 기간 밖에서 계획하고 기간 안에 완료한 Task가 완료 수에는 포함되지만
  계획 코호트 완료율의 분모에는 포함되지 않음을 테스트한다.
- [x] 기간 제한 descriptor로 필요한 Task만 조회하고 전체 저장소 fetch를 금지한다.
- [x] `TaskHistoryStatisticsSession`이 고정 크기 pagination 또는 `fetchCount` 조합으로
  전체 기간 요약을 계산하고 새 필터가 적용되면 이전 계산을 취소한다.
- [x] 목록의 현재 30일 page만 집계한 값을 전체 기간 통계처럼 표시하지 않는다.
- [x] iPhone/macOS 기록 상단에 동일한 통계 요약을 추가한다.
- [x] 현재 날짜 기준 필터와 통계 label의 의미가 혼동되지 않도록 설명을 표시한다.

예상 파일:

- `shared/Core/Services/TaskHistoryStatisticsRules.swift`
- `shared/Core/Services/TaskHistoryStatisticsSession.swift`
- `shared/Core/Services/BoundedQueryService.swift`
- `shared/Tests/TaskHistoryStatisticsRulesTests.swift`
- `shared/Tests/BoundedQueryServiceTests.swift`
- `mobile/App/Features/Archive/MobileArchiveView.swift`
- `desktop/App/Features/Archive/ArchiveView.swift`

완료 조건:

- 같은 fixture에 대해 iPhone과 macOS의 수치가 같다.
- 각 수치의 날짜 모집단과 의미가 화면에서 구분된다.

### Phase 5 — P1 일정 정확 복제

#### 5.1 공통 복제 규칙

- [x] `CalendarEventReuseRules`와 복제용 draft 값 타입을 추가한다.
- [x] 원본의 시작·종료 포함 일수를 계산한다.
- [x] 대상 시작일을 유지하면서 동일한 포함 일수의 종료일을 계산한다.
- [x] 제목, 색상, 메모가 보존되는지 테스트한다.
- [x] 단일 일정과 월 경계를 넘는 일정의 복제를 테스트한다.
- [x] 복제본이 새 논리·물리 ID를 갖고 Task 연결을 만들지 않는지 테스트한다.
- [x] DST 전환일에도 `DayKey` 기반 포함 일수가 유지되는지 테스트한다.

예상 파일:

- `shared/Core/Services/CalendarEventReuseRules.swift`
- `shared/Core/Services/CalendarEventRules.swift`
- `shared/Tests/CalendarRulesTests.swift`

#### 5.2 양 플랫폼 복제 UI

- [x] iPhone 날짜 상세의 편집 버튼은 유지하고 overflow 메뉴에 `일정 복제`와 `삭제`를
  이 순서로 추가한다.
- [x] iPhone long press context menu가 overflow 메뉴와 같은 동작·순서를 제공한다.
- [x] iPhone 편집 sheet가 복제 draft와 대상 날짜를 받아 저장 전 수정할 수 있게 한다.
- [x] 복제 편집기에는 `복제한 일정` 맥락을 짧게 표시하되 새 wizard나 안내 카드를 만들지 않는다.
- [x] macOS 월간 이벤트 막대의 기존 context menu와 날짜 inspector 행에 같은 기능을 추가한다.
- [x] macOS 편집 sheet가 같은 공통 draft를 사용한다.
- [x] 복제본이 원본과 독립된 일정임을 저장 결과와 접근성 문구에서 오해 없이 전달한다.
- [x] 저장은 양 플랫폼 모두 `PersistenceCommandService.perform`을 통과한다.
- [x] 저장 실패 시 원본을 변경하지 않고 편집 화면과 오류 안내를 유지한다.
- [x] iOS 복제 저장 뒤 기존 위젯 snapshot 갱신이 발생하는지 확인한다.

예상 파일:

- `mobile/App/Features/Calendar/MobileCalendarDaySheet.swift`
- `mobile/App/Features/Calendar/MobileEventEditorSheet.swift`
- `mobile/App/Features/Calendar/MobileCalendarView.swift`
- `desktop/App/Features/Calendar/DesktopCalendarDayInspector.swift`
- `desktop/App/Features/Calendar/DesktopCalendarGrid.swift`
- `desktop/App/Features/Calendar/DesktopEventEditorSheets.swift`
- `desktop/App/Features/Calendar/CalendarView.swift`

완료 조건:

- 같은 원본과 대상 날짜로 복제했을 때 iPhone과 macOS가 같은 draft를 만든다.
- 원본 일정과 연결 Task는 변경되지 않는다.

### Phase 6 — P2 제목 기반 최근 일정 추천

#### 6.1 추천 규칙과 bounded query

- [x] 제목 정규화, 정확 일치, 접두어 일치의 우선순위를 공통 규칙으로 만든다.
- [x] 활성 대표 CalendarEvent만 후보가 되게 한다.
- [x] 논리 중복과 동일 설정 후보를 제거한다.
- [x] 최근 수정일과 `instanceID` tie-break로 정렬을 결정적으로 만든다.
- [x] 추천 수를 최대 5개로 제한한다.
- [x] 최근 일정 후보 descriptor는 활성 일정을 `updatedAt`, `instanceID` 역순으로
  가져오고 명시적인 scan limit을 둔다. 초기 기준은 200개로 두고 성능 테스트 결과로만
  조정한다.
- [x] scan limit 밖의 오래된 일정은 추천되지 않을 수 있음을 제품의 `최근 일정` 의미로
  고정하고 전체 테이블 fallback fetch를 추가하지 않는다.
- [x] 빈 제목, 공백 차이, 대소문자, 한글 제목, 동일 제목의 여러 설정을 테스트한다.
- [x] 현재 편집 중인 원본 이벤트를 추천에서 제외하는 옵션을 테스트한다.

예상 파일:

- `shared/Core/Services/CalendarEventReuseRules.swift`
- `shared/Core/Services/BoundedQueryService.swift`
- `shared/Tests/CalendarRulesTests.swift`
- `shared/Tests/BoundedQueryServiceTests.swift`

#### 6.2 양 플랫폼 추천 UI

- [x] 제목 입력 아래에 최근 일정 후보와 기간·색상 요약을 표시한다.
- [x] 후보 행은 `제목 · N일 · 색상 · 메모 유무`만 표시하고 독립 카드나 그림자를 추가하지 않는다.
- [x] 후보 선택 전에는 날짜, 색상, 메모를 변경하지 않는다.
- [x] 후보 선택 시 현재 시작일을 유지하고 기간·색상·메모를 적용한다.
- [x] iPhone은 후보 tap, macOS는 click·위/아래·Return으로 같은 선택 의미를 제공한다.
- [x] macOS `Esc`와 iPhone의 편집 계속하기로 추천을 무시해도 draft가 유지되는지 확인한다.
- [x] 적용 이후 사용자가 바꾼 값은 제목 입력 변화로 다시 덮어쓰지 않는다.
- [ ] iPhone VoiceOver 선택과 Dynamic Type을 검증한다.
- [x] macOS 키보드 위/아래 이동, 선택, 닫기를 검증한다.
- [x] 후보가 없을 때 편집기 높이나 저장 동작이 바뀌지 않는지 확인한다.
- [x] 제목 입력 연속 변경은 150~250ms debounce하고 이전 추천 query를 취소한다.

예상 파일:

- `mobile/App/Features/Calendar/MobileEventEditorSheet.swift`
- `desktop/App/Features/Calendar/DesktopEventEditorSheets.swift`

완료 조건:

- `공장` 입력 후 최근 후보를 선택하면 현재 선택 날짜를 유지한 채 기존 설정이 적용된다.
- 입력만 했을 때 사용자의 기존 폼 값은 바뀌지 않는다.

### Phase 7 — 전체 회귀와 배포 준비

- [x] `git diff --check`를 통과한다.
- [x] `swift test`를 통과한다.
- [x] `swift test -c release`를 통과한다.
- [x] `./scripts/verify-platform-builds.sh`를 통과한다.
- [x] 관련 iPhone 단위/UI 테스트를 별도 `xcodebuild test`로 실행한다.
- [x] iPhone에서 계획일/완료일 필터, 회고, 복제, 추천을 수동 검증한다.
- [x] macOS에서 같은 fixture와 수치를 수동 검증한다.
- [x] iPhone 17e/17 Pro의 light·dark와 기본/접근성 글자 크기로 전후 캡처를 비교한다.
- [x] macOS의 기본 폭과 좁은 폭, light·dark에서 필터·두 날짜·추천 목록을 비교한다.
- [ ] VoiceOver 읽기 순서와 macOS Full Keyboard Access에서 label·focus 순서를 확인한다.
- [x] 긴 한국어 제목, 일정 0개/1개/5개 추천, 같은 날 완료/지연 완료 fixture를 시각 검증한다.
- [ ] iPhone에서 만든 복제 일정을 macOS에서 확인·수정하고 다시 iPhone에서 확인한다.
- [ ] 실제 CloudKit 환경에서 transient 중복이 추천 목록에 중복 노출되지 않는지 확인한다.
- [x] 새 일정 저장 후 iOS 위젯에 일정이 정상 반영되는지 확인한다.
- [x] schema, migration, backup format, 호환 식별자에 의도하지 않은 diff가 없는지 확인한다.
- [x] 기능별 작은 커밋으로 정리한 뒤 최종 병합·push·TestFlight 순서로 진행한다.

완료 조건:

- 공통 테스트와 iOS/macOS Debug/Release 빌드가 모두 통과한다.
- 동일 데이터가 양 플랫폼에서 같은 날짜 의미와 통계 결과를 보인다.
- 기존 CloudKit 데이터, 백업, 위젯 호환성이 유지된다.

## 7. 구현 순서와 커밋 경계

권장 커밋 순서는 다음과 같다.

1. `test: 계획일·완료일 회귀 fixture 추가`
2. `feat: 작업 기록 날짜 기준 공통 규칙 추가`
3. `feat: 양 플랫폼 기록 날짜 기준과 두 날짜 표시`
4. `feat: 일일 회고 계획·완료 축 분리`
5. `feat: 기록 기간 통계 추가`
6. `feat: 일정 복제 공통 규칙과 양 플랫폼 UI`
7. `feat: 최근 일정 추천과 bounded query`
8. `test: 양 플랫폼 일정 재사용·기록 회귀 검증`

각 커밋은 해당 단계의 공통 테스트와 영향 플랫폼 Debug 빌드를 통과해야 한다. 공통 API,
bounded query 또는 Xcode 설정을 건드린 커밋은 최종 병합 전에 전체 회귀 게이트를 다시
실행한다.

## 8. 완료 정의

다음 시나리오가 모두 성립하면 사용자 후기 대응을 완료한 것으로 본다.

1. 목요일 계획 Task를 다른 날짜로 옮기지 않고 토요일에 완료하면 기록 행에서 계획일과
   완료일을 모두 볼 수 있다.
2. 완료일 기준 기록에서는 토요일, 계획일 기준 기록에서는 목요일에 같은 Task가 나타난다.
3. 목요일 회고에서는 계획한 작업을, 토요일 회고에서는 실제 완료한 작업을 확인할 수 있다.
4. 통계가 지연 완료를 계획일 내 완료와 구분하고 양 플랫폼에서 같은 수치를 보인다.
5. 기존 `공장` 일정을 선택해 다른 날짜로 복제하면 기간·색상·메모가 유지된다.
6. 새 일정 제목에 `공장`을 입력해 후보를 선택하면 현재 시작일은 유지되고 이전 설정이
   적용된다.
7. 후보를 선택하지 않으면 사용자가 입력한 일정 값이 자동으로 바뀌지 않는다.
8. 기존 CloudKit 데이터, 백업 package, 위젯 snapshot, 호환 식별자가 그대로 유지된다.
9. Task를 명시적으로 재계획한 경우 화면과 통계가 최초 계획일을 보존하는 것처럼
   잘못 설명하지 않는다.
