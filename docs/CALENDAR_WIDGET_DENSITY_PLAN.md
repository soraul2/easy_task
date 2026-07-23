# PlanBase 캘린더 위젯 이벤트 밀도 개선 계획

## 1. 목표

- 홈 화면 캘린더 위젯에서 제한된 면적 안에 가능한 한 많은 이벤트를 정확하게 표시한다.
- 대형 위젯을 iPhone 앱 캘린더의 시각 언어와 맞춘다.
- 날짜별 독립 카드와 여러 날 이벤트 제목의 반복을 제거하고, 하나의 연속된 월간 표와 주간 단위 이벤트 막대를 사용한다.
- 위젯 크기마다 읽을 수 있는 최소 크기를 지키면서 서로 다른 정보 밀도를 제공한다.
- 현재 월과 다음 월의 날짜별 표시 우선 이벤트가 스냅샷 개수 제한 때문에 특정 날짜의 대량 이벤트에 밀려 누락되지 않게 한다.
- 손상된 스냅샷, 월 변경, 시간대 변경, CloudKit import 이후에도 위젯이 스스로 최신 상태로 수렴하게 한다.
- 실제 빈 일정과 snapshot 누락·손상·coverage 만료를 구분해 잘못된 빈 상태를 표시하지 않는다.
- SwiftData와 CloudKit 스키마, 기존 App Group, widget kind, deep link 호환 식별자는 변경하지 않는다.

## 2. 핵심 성공 기준

1. 중형·대형 위젯은 월에 필요한 5주 또는 6주를 하나의 연속된 표로 표시한다.
2. 대형 위젯은 한 주에 최대 3개 이벤트 lane을 기본 목표로 삼는다.
3. 여러 날 이벤트 제목은 날짜마다 반복하지 않고 주간 구간당 한 번만 표시한다.
4. 표시 lane을 넘는 이벤트는 날짜별 `+N`으로 정확하게 안내한다.
5. 중형 위젯은 모바일 캘린더와 같은 막대 표현을 사용하되 제목 없이 기간·색상·개수를 압축 표시한다.
6. 소형 위젯은 오늘 이벤트를 최대 4개까지 유지하고 헤더의 `+N`으로 overflow를 안내한다.
7. 현재 월과 다음 월의 각 날짜에서 표시 우선 이벤트 최대 3개를 cap보다 먼저 보존한다.
8. 기존 JSON 파일이 손상되어도 다음 앱 발행 시 정상 스냅샷으로 자동 복구된다.
9. 앱 루트가 전체 캘린더 이벤트 테이블을 상시 관찰하지 않는다.
10. 날짜를 누르면 기존처럼 해당 날짜의 모바일 캘린더 상세로 이동한다.
11. snapshot이 없거나 현재 월을 포함하지 않으면 실제 이벤트 없음으로 표시하지 않고 갱신 안내를 표시한다.

## 2.1 확정된 제품 결정

- 월간 표는 하단 floating bar가 없는 위젯 공간을 활용해 5주 달은 5줄, 6주 달은 6줄로 표시한다.
- 모바일 앱, 중형 위젯, 대형 위젯 모두 여러 날 이벤트를 가로 막대로 표현한다.
- 대형 막대에는 이벤트 제목을 표시하고 중형 막대는 작은 공간 때문에 색상과 기간만 표시한다.
- 소형 위젯은 이벤트 제목 최대 4개를 유지하고 초과 개수는 헤더 우측 `+N` 배지로 표시한다.
- 날짜별 카드 모음이 아니라 하나의 연속된 표라는 시각 언어를 중형·대형에서 공유한다.

## 3. 현재 상태

### iPhone 앱 캘린더

- 42일을 간격 없는 `LazyVGrid`로 배치한다.
- 전체 그리드에 하나의 외곽선을 두고 셀에는 행·열 구분선만 둔다.
- 날짜 숫자는 10pt다.
- 이벤트는 날짜 셀 내부가 아니라 그리드 위에 주간 단위 막대로 겹쳐 표시한다.
- 한 날짜에 표시할 수 있는 이벤트 lane은 화면 높이에 따라 최대 3개다.
- 여러 날 이벤트는 각 주의 시작·끝 구간으로 나뉘며 lane을 재사용한다.

관련 코드:

- `mobile/App/MobileCalendarView.swift`
- `mobile/App/MobileCalendarGrid.swift`

### 현재 홈 화면 위젯

- 소형: 오늘 이벤트를 최대 3개 표시한다.
- 중형: 42일 그리드에서 날짜별 이벤트 색상 점을 최대 2개 표시한다.
- 대형: 각 날짜를 둥근 독립 카드로 만들고 날짜마다 이벤트 제목을 최대 2개 표시한다.
- 여러 날 이벤트는 포함되는 모든 날짜에 같은 제목이 반복된다.
- 대형 날짜 셀의 padding, 카드 간격, 둥근 배경과 테두리가 이벤트 영역을 사용한다.
- 스냅샷은 현재 월 기준 이전 1개월부터 이후 3개월 직전까지 정렬한 뒤 최대 256개만 저장한다.
- 스냅샷 발행용 `@Query`는 캘린더 이벤트 전체를 상시 조회한다.
- 기존 JSON 디코딩이 실패하면 새 스냅샷을 덮어쓰지 못한다.

관련 코드:

- `mobile/Widget/PlanBaseCalendarWidget.swift`
- `mobile/App/CalendarWidgetSnapshotPublisher.swift`
- `shared/Core/Services/CalendarWidgetSnapshot.swift`
- `shared/Tests/CalendarWidgetSnapshotTests.swift`

## 4. 확정 디자인 방향

### 4.1 공통 원칙

- 위젯을 작은 앱 화면처럼 만들지 않고 빠르게 읽히는 월간 요약으로 유지한다.
- 글자를 7pt 이하로 계속 줄여 절대 표시 개수만 늘리는 방식은 사용하지 않는다.
- 날짜 숫자 축소보다 카드 padding, 카드 사이 간격, 반복 이벤트 제목 제거를 먼저 적용한다.
- 5주로 충분한 달에 불필요한 여섯 번째 행을 만들지 않고 확보된 높이를 lane과 가독성에 사용한다.
- 이벤트 색상과 정렬 순서는 iPhone 앱 캘린더와 동일하게 유지한다.
- 이벤트 막대는 날짜 링크의 탭을 방해하지 않도록 hit testing에서 제외한다.
- 이벤트가 생략됐다는 사실을 숨기지 않고 `+N`으로 표시한다.
- 이벤트 제목과 이를 포함한 접근성 정보는 개인정보 보호 상태를 유지한다.

### 4.2 소형 위젯: 오늘 집중형

목표는 오늘 일정의 제목을 가장 빠르게 확인하는 것이다.

- 날짜 숫자를 30pt에서 26~28pt 범위로 줄인다.
- 헤더와 이벤트 목록 사이 여백을 축소한다.
- 이벤트 행 간격을 줄이되 제목은 10pt 이상을 목표로 한다.
- 세로 공간이 허용되면 이벤트 제목을 최대 4개 표시한다.
- 이벤트가 4개를 넘으면 제목 행을 교체하지 않고 헤더 우측에 `+N` 배지를 표시한다.
- 작은 systemSmall 실측에서 4개가 안전하지 않은 경우에만 제목을 3개로 줄이고 같은 `+N` 배지를 유지한다.
- 접근성 레이블은 잘린 배열 개수가 아니라 오늘의 전체 이벤트 개수를 읽는다.
- 이벤트가 없을 때의 빈 상태는 유지한다.

### 4.3 중형 위젯: 압축 월간형

중형에서는 7열 안에 이벤트 제목을 넣으면 읽기 어려우므로 기간과 밀도를 중심으로 표시한다.

- 월 제목, 요일, 해당 월에 필요한 5주 또는 6주 그리드를 하나의 연속된 표로 만든다.
- 날짜 숫자는 8pt를 기본값으로 하고 오늘만 굵게 강조한다.
- 날짜별 원형 점 대신 모바일 캘린더와 같은 주간 단위의 얇은 이벤트 막대를 사용한다.
- 각 주에는 기본 2개 strip lane을 제공한다.
- row 높이가 충분한 기기에서는 측정값에 따라 세 번째 lane을 허용할 수 있다.
- 숨겨진 이벤트는 해당 날짜의 작은 `+N` 표시로 안내한다.
- 제목은 표시하지 않지만 모바일·대형 위젯과 같은 막대 문법으로 이벤트 색상과 여러 날에 걸친 기간을 한눈에 볼 수 있게 한다.
- `PlanBase` 브랜드 텍스트는 정보 공간과 충돌하면 제거한다.

### 4.4 대형 위젯: 연속형 월간 표

대형 위젯은 iPhone 앱 캘린더의 압축판으로 재설계한다.

- 날짜별 둥근 카드, 카드 사이 2pt 간격, 셀별 border를 제거한다.
- 전체 그리드에 하나의 외곽선을 두고 내부에는 0.5pt 수준의 연속 구분선만 둔다.
- 현재 월에 필요한 행만 계산해 5주 또는 6주로 표시한다.
- 현재 월과 인접 월은 배경·텍스트 opacity로 구분한다.
- 날짜 숫자는 8~9pt, 날짜 영역 높이는 약 13~14pt를 목표로 한다.
- 오늘은 작은 원 또는 얇은 강조선으로 표시해 이벤트 영역을 침범하지 않게 한다.
- 헤더와 요일 영역의 높이를 줄이고 `이벤트 N개` 문구는 제거하거나 한 줄 안에서 더 작게 배치한다.
- 이벤트는 주간 단위 가로 막대로 표시한다.
- 막대 높이는 9~10pt, 제목은 8pt 이상을 목표로 한다.
- GeometryReader로 실제 row 높이를 계산해 최대 2~3개 lane을 선택한다.
- 여러 날 이벤트가 주 경계를 넘으면 주별 segment로 나누되 제목은 segment당 한 번만 표시한다.
- 같은 주에서 앞 이벤트가 끝난 뒤의 빈 lane은 뒤 이벤트가 재사용한다.
- 현재 월을 가로지르는 인접 월 이벤트는 연속성을 유지하고 opacity로만 구분한다.
- lane을 초과한 이벤트 수는 날짜별 `+N`으로 표시한다.
- 날짜별 `Link`는 유지하고 막대는 `.allowsHitTesting(false)`로 둔다.

## 5. 공통 이벤트 배치 엔진

모바일 앱의 private lane 계산을 위젯에 복사하지 않고 공통 순수 규칙으로 분리한다.

제안 위치:

```text
shared/Core/Services/CalendarEventGridLayout.swift
```

입력 값 타입:

```text
CalendarEventGridLayoutItem
  renderID
  eventID
  title
  startDayKey
  endDayKey
```

출력 값 타입:

```text
CalendarEventGridSegment
  renderID
  eventID
  weekIndex
  startColumn
  span
  lane
  isDimmed
```

추가 결과:

```text
hiddenEventCountByDayKey
```

규칙:

1. 입력 day key가 유효하고 범위가 정상인 이벤트만 배치한다.
2. CloudKit 수렴 전 같은 논리 `eventID`가 보이더라도 `renderID`는 물리 `instanceID` 기반으로 고유하게 유지한다.
3. snapshot 발행은 reconciliation 이후 대표 논리 이벤트를 사용하고 count도 논리 이벤트 기준으로 계산한다.
4. 시작일 오름차순, 종료일 내림차순, 제목, ID 순으로 결정적으로 정렬한다.
5. `leadingDays + monthDayCount`를 7로 올림 나눗셈하고 결과를 최소 5, 최대 6으로 제한해 row count를 결정한다.
6. 그리드 날짜 수는 `rowCount × 7`로 만들고 각 주를 7일 단위로 나눈다.
7. 이벤트를 각 주와 겹치는 segment로 자른다.
8. 이미 사용 중인 lane과 날짜 구간이 겹치지 않으면 lane을 재사용한다.
9. `maximumLanes`를 넘는 segment는 렌더링하지 않는다.
10. 날짜별 hidden count는 segment 개수가 아니라 `전체 고유 이벤트 수 - 표시된 고유 이벤트 수`로 계산한다.
11. 여러 주로 잘린 같은 이벤트와 snapshot cap 밖 이벤트를 중복 계산하지 않는다.
12. 모바일 앱은 결과의 ID를 SwiftData 모델에, 위젯은 snapshot 값에 매핑한다.

이 작업 후 iPhone 앱의 기존 `eventSegments` 구현도 공통 엔진을 사용하도록 교체해 양쪽 정렬과 overflow 의미를 맞춘다.

## 6. 스냅샷 이벤트 확보 정책

### 6.1 현재 문제

현재는 약 4개월 범위 이벤트를 시작일 순으로 정렬한 후 256개를 자른다. 이전 달에 이벤트가 많으면 현재 월 이벤트가 뒤에서 탈락할 수 있다. 위젯에 저장되지 않은 이벤트는 UI 개선만으로 표시할 수 없다.

### 6.2 우선순위 정책

단순 월 단위 정렬이 아니라 실제 위젯에서 표시 가능한 날짜별 후보를 먼저 보존한다.

1. 현재 월 5·6주 그리드의 각 날짜에서 표시 우선 이벤트 최대 3개를 선택한다.
2. 다음 월 5·6주 그리드도 같은 방식으로 날짜별 최대 3개를 선택한다.
3. 1~2에서 선택한 이벤트 ID의 합집합을 cap보다 먼저 필수 보존한다.
4. 남은 공간은 현재 월의 나머지 이벤트, 미래 이벤트, 이전 월 이벤트 순으로 채운다.
5. 각 단계 안에서는 공통 배치 엔진과 같은 안정 정렬을 사용한다.

필수 조건:

- 특정 날짜에 수백 개의 이벤트가 있어도 다른 날짜의 상위 3개 표시 후보를 밀어내지 않는다.
- 현재 월과 다음 월을 각각 최대 42일로 계산하면 `42일 × 3개 × 2개월 = 252개`이므로 기존 256개 안에서도 기본 표시 후보를 우선 보존할 수 있다.
- 여러 달에 걸친 이벤트는 포함 날짜마다 중복 저장하지 않고 이벤트 ID 합집합에 한 번만 들어간다.
- 앱을 한 달 이상 열지 않아도 다음 월의 기본 표시 후보가 snapshot에 남아 있어야 한다.
- cap 적용 후 위젯 표시용 배열은 다시 안정적인 캘린더 순서로 정렬한다.

### 6.3 개수 제한과 정확한 overflow

- 기본 상한은 256개로 유지하고 날짜별 필수 보존 정책을 먼저 적용한다.
- 512개 확대는 미래 월의 추가 제목까지 보존할 실익과 성능 예산을 모두 확인한 뒤에만 채택한다.
- 상한 밖 이벤트가 있더라도 날짜별 전체 개수를 알 수 있도록 snapshot에 count 정보를 추가한다.

제안 snapshot v3 필드:

```text
coveredStartDayKey
coveredEndDayKey
eventCountsByDayKey
```

통합 구현에서는 위 필드가 v3에 도입된 뒤 다른 팀의 잠금화면 요약이 추가되며 현재 schema가 v4로 올라갔다. 캘린더 v3 payload decode 호환성과 density 필드의 의미는 그대로 유지한다.

- event snapshot에는 논리 `eventID`와 별도로 물리 `instanceID` 기반 `renderID`를 포함한다.
- `eventCountsByDayKey`는 cap 적용 전 대표 활성 이벤트로 계산하고 coverage에 포함된 날짜만 키로 만든다.
- 여러 날 이벤트는 포함되는 각 날짜에서 한 번씩 세되 주간 segment 수와는 무관하게 계산한다.
- 기존 v1/v2 JSON은 custom `init(from:)`에서 coverage와 count의 안전한 기본값을 제공하고 누락된 `renderID`는 기존 `eventID`로 대체한다.
- v3 writer는 새 필드를 항상 기록하고 schema version을 명시적으로 검증한다.
- `hasSameContent`는 coverage와 count도 비교해 월이 바뀌면 새 파일이 발행되게 한다.
- 날짜별 overflow는 `eventCountsByDayKey[dayKey] - 표시된 고유 eventID 수`로 계산한다.
- count map을 통해 snapshot 배열에서 일부 이벤트가 빠져도 `+N`이 실제 개수를 반영하게 한다.

### 6.4 성능 예산

Release 빌드의 실제 기기와 시뮬레이터 측정으로 최종 상한을 결정한다.

- JSON 파일 목표 크기: 150KB 이하
- snapshot encode/decode: 동일 fixture를 20회 반복한 일반 데이터에서 20ms 이내 목표
- 위젯 body 계산은 SwiftData나 파일 추가 조회 없이 snapshot 값만 사용
- 이벤트 배치 계산은 최대 42일과 bounded snapshot 배열 안에서만 실행
- 최소 지원 iPhone 계열과 iPad에서 systemSmall/Medium/Large를 각각 측정
- 256개, 512개, 장기간 이벤트, 한 날짜 집중 이벤트 fixture를 분리 측정

기본 256개가 날짜별 표시 후보를 보존하므로 512개가 예산을 넘으면 배열은 256개로 유지하고 count map으로 overflow 정확성만 확보한다.

## 7. 발행과 복구 경로

### 7.1 bounded fetch

`CalendarWidgetSnapshotPublisher`의 제한 없는 `@Query`를 제거한다.

- `ModelContext`에서 위젯 coverage와 겹치는 이벤트만 `BoundedQueryService.eventsDescriptor`로 조회한다.
- snapshot 발행은 다음 신호에서 실행한다.
  - 앱 시작
  - 앱 active 전환
  - `PersistenceCommandService.dataChangedNotification`
  - CloudKit import 후 reconciliation 저장 완료
  - 선택 테마 변경
  - `NSCalendarDayChanged`
  - `NSSystemTimeZoneDidChange`
- 연속해서 들어오는 발행 신호는 짧게 coalescing하고 한 번에 하나의 발행만 실행한다.
- 실행 중 새 요청이 들어오면 현재 발행 완료 후 최신 상태를 한 번만 추가 발행한다.
- SwiftData fetch와 대표 이벤트 값 변환은 MainActor에서 수행하고, Sendable snapshot의 encode/write는 가능한 범위에서 메인 스레드 밖으로 분리한다.
- 동일 내용이면 기존처럼 WidgetKit timeline reload를 생략한다.
- 월 coverage가 바뀌면 이벤트 배열이 같아도 snapshot을 새로 쓰고 timeline을 갱신한다.

### 7.2 손상 snapshot 자동 복구

`writeIfChanged`에서 기존 파일 read가 실패했을 때 오류 종류를 구분한다.

- 전체 snapshot을 decode하기 전에 최소 envelope로 `schemaVersion`을 먼저 확인한다.
- malformed JSON 또는 현재보다 오래된 호환 schema: 유효한 새 snapshot으로 원자적 교체
- 현재 앱보다 높은 미래 schema: 이전 앱이 새 데이터를 덮어쓰지 않도록 교체하지 않고 명시적 오류 처리
- App Group container, 권한, 실제 파일 I/O 오류: 덮어써서 숨기지 않고 호출자에 전달
- 위젯 read 실패: 빈 상태로 안전하게 렌더링하되 앱의 다음 발행에서 복구
- 복구 성공 후 `WidgetCenter.reloadTimelines` 실행

### 7.3 snapshot 가용성 상태

위젯 entry는 유효한 빈 일정과 데이터를 읽지 못한 상태를 구분한다.

```text
available
missing
corrupt
staleCoverage
unsupportedNewerSchema
```

- `available`: coverage가 현재 표시 월을 포함하며 정상 decode됨
- `missing`: 앱이 아직 snapshot을 발행하지 않음
- `corrupt`: 파일은 있지만 decode할 수 없음
- `staleCoverage`: snapshot은 정상이지만 현재 표시 월이 coverage 밖임
- `unsupportedNewerSchema`: 현재 위젯보다 높은 schema라 안전하게 해석할 수 없음
- `missing`, `corrupt`, `staleCoverage`에서는 `등록된 이벤트 없음` 대신 `PlanBase를 열어 일정을 갱신하세요`를 표시한다.
- `unsupportedNewerSchema`에서는 파일을 덮어쓰지 않고 `PlanBase를 업데이트해 주세요`를 표시한다.
- 오류 상태에서도 날짜 deep link는 유지해 앱을 열어 복구할 수 있게 한다.

## 8. 정보 표시와 접근성

- 날짜 셀의 접근성 레이블은 해당 날짜의 전체 이벤트 수를 읽는다.
- 대형 위젯은 표시된 고유 이벤트 제목과 `+N`을 함께 읽는다.
- 이벤트 막대 자체는 날짜 셀과 중복 낭독되지 않도록 접근성 트리에서 정리한다.
- 소형 위젯은 최대 4개 제목과 헤더 `+N`을 그리되 전체 개수를 안내한다.
- 이벤트 제목을 포함하는 Text와 사용자 정의 접근성 문자열의 privacy 동작을 잠금·redaction 상태에서 검증한다.
- Light/Dark, 시스템 tinted/강조 렌더링에서 날짜와 이벤트 막대가 구분되는지 확인한다.
- 날짜와 이벤트 제목은 설정한 최소 글자 크기 아래로 축소하지 않고, 공간이 부족하면 표시 lane을 줄인다.

## 9. 변경 파일 계획

### 새 파일

- `shared/Core/Services/CalendarEventGridLayout.swift`
- `shared/Tests/CalendarEventGridLayoutTests.swift`

### 수정 파일

- `shared/Core/Services/CalendarWidgetSnapshot.swift`
  - 현재·다음 월 날짜별 표시 후보 우선 선택
  - coverage/count/renderID 필드와 custom decode
  - 손상 파일 복구와 미래 schema 비파괴 처리
- `shared/Core/Services/BoundedQueryService.swift`
  - 필요하면 위젯 coverage helper 추가
- `shared/Tests/CalendarWidgetSnapshotTests.swift`
  - cap, legacy, count, 복구 테스트
- `mobile/App/CalendarWidgetSnapshotPublisher.swift`
  - bounded fetch, 갱신 신호, coalescing 연결
- `mobile/App/MobileCalendarView.swift`
  - 기존 private lane 계산을 공통 엔진 호출로 교체
- `mobile/App/MobileCalendarGrid.swift`
  - 공통 segment 결과 타입에 맞춘 표시 연결
- `mobile/Widget/PlanBaseCalendarWidget.swift`
  - 소형 4개와 헤더 `+N`
  - 중형 5·6주 연속 표와 기간 막대
  - 대형 5·6주 연속 표와 제목 막대
  - missing/corrupt/staleCoverage/unsupportedNewerSchema 상태

SwiftData schema, migration, backup, CloudKit schema, entitlements, widget kind, App Group identifier는 수정하지 않는다.

## 10. 단계별 구현 순서

### Phase 0. 기준 화면과 데이터 세트 고정

- 기존 소형·중형·대형 위젯을 Light/Dark로 캡처한다.
- 다음 preview fixture를 만든다.
  - 이벤트 없음
  - 오늘 이벤트 1개, 4개, 8개
  - 한 날짜에 5개 겹침
  - 2~10일짜리 여러 날 이벤트
  - 주 경계와 월 경계를 동시에 넘는 이벤트
  - 긴 한글·영문·숫자 제목
  - 5주와 6주가 필요한 월
  - 한 날짜에 300개가 몰리고 다른 날짜에도 이벤트가 있는 경우
  - 현재 월과 다음 월을 합쳐 cap에 도달하는 경우
  - 같은 논리 ID를 가진 임시 CloudKit 중복 레코드
  - missing, corrupt, staleCoverage, unsupportedNewerSchema snapshot
  - snapshot cap을 넘는 이벤트

완료 조건:

- 개선 전후를 같은 데이터와 widget family로 비교할 수 있다.

### Phase 1. 공통 배치 엔진

- `CalendarEventGridLayout` 순수 규칙과 단위 테스트를 추가한다.
- 모바일 앱을 공통 엔진으로 전환해 기존 화면 결과가 유지되는지 확인한다.

완료 조건:

- 5·6주 계산, 주 경계, lane 재사용, 고유 이벤트 overflow, 결정적 정렬 테스트 통과
- 같은 논리 ID가 있어도 renderID 충돌이나 중복 count가 없음
- 모바일 캘린더 회귀 없음

### Phase 2. 스냅샷 완전성과 복구

- 현재·다음 월 날짜별 3개 우선 보존, coverage, count map을 구현한다.
- cap 256/512 성능을 측정하고 최종 상한을 결정한다.
- 손상 JSON 자동 복구와 미래 schema 비파괴 처리를 구현한다.
- bounded fetch와 발행 coalescing을 적용한다.
- missing/corrupt/staleCoverage/unsupportedNewerSchema 상태를 entry에 전달한다.

완료 조건:

- 한 날짜의 300개 이벤트가 다른 날짜의 상위 3개 표시 후보를 밀어내지 않음
- 앱을 35일 이상 열지 않은 월 전환에서도 다음 월 표시 후보가 snapshot에 포함됨
- cap 밖 이벤트도 날짜별 전체 count가 정확함
- malformed JSON을 다음 발행이 정상 파일로 교체함
- 미래 schema snapshot을 이전 writer가 덮어쓰지 않음
- 앱 루트에 제한 없는 CalendarEvent `@Query`가 남지 않음

### Phase 3. 대형 위젯 재설계

- 독립 카드 그리드를 연속 표로 교체한다.
- 월에 따라 5주 또는 6주를 계산한다.
- 날짜 영역을 축소하고 이벤트 segment overlay를 추가한다.
- 최대 3개 lane과 날짜별 `+N`을 적용한다.
- 날짜 deep link와 privacy 처리를 유지한다.

완료 조건:

- 동일한 여러 날 이벤트 제목이 날짜마다 반복되지 않음
- 5주 systemLarge에서 3개 lane을 확보하고 6주·작은 높이에서는 최소 크기를 지키며 2~3개로 조정
- 이벤트가 많은 날에 정확한 overflow 표시
- 모든 날짜 Link 정상 동작

### Phase 4. 중형·소형 밀도 조정

- 중형에 5·6주 연속 표와 모바일 캘린더 방식의 얇은 기간 막대를 적용한다.
- 소형에 최대 4개 이벤트와 헤더 `+N`을 적용한다.
- 글자 크기와 lane 수를 실제 widget family 크기에서 조정한다.

완료 조건:

- 중형에서 날짜와 이벤트 기간을 한눈에 구분할 수 있음
- 일반 systemSmall에서 4개 이벤트가 잘리지 않고 표시되며 작은 크기는 3개와 헤더 `+N`으로 안전하게 감소함
- 작은 화면에서는 글자를 더 줄이지 않고 lane/표시 개수가 안전하게 감소함

### Phase 5. 접근성·렌더링·성능 검증

- VoiceOver, privacy redaction, Light/Dark, tinted 모드를 확인한다.
- snapshot 크기와 encode/decode 시간을 기록한다.
- 월 변경과 시간대 변경 시나리오를 확인한다.
- 최소 지원 iPhone 계열과 iPad의 각 widget family를 Release 빌드로 확인한다.

완료 조건:

- 접근성 레이블의 이벤트 개수와 `+N`이 실제 데이터와 일치
- 주요 테마에서 날짜·막대 대비가 유지됨
- 성능 예산 충족

## 11. 테스트 계획

### 공통 단위 테스트

- 단일 날짜 이벤트 segment
- 여러 날짜와 여러 주를 넘는 이벤트 segment
- 월 바깥에서 시작해 현재 월로 들어오는 이벤트
- lane 충돌과 종료 후 lane 재사용
- 최대 lane 초과 시 날짜별 hidden count
- hidden count가 `전체 고유 이벤트 - 표시된 고유 이벤트`와 일치
- 5주 월과 6주 월의 grid range
- 동일 논리 ID와 서로 다른 renderID 처리
- 입력 순서가 바뀌어도 같은 결과가 나오는 결정적 정렬
- 잘못된 day key와 역전 범위 제외

### snapshot 테스트

- 현재·다음 월 날짜별 상위 3개 보존
- 한 날짜에 300개가 있어도 다른 날짜 표시 후보 보존
- 이전·현재·미래 이벤트의 안정 정렬
- 256/512 cap 경계
- cap 적용 전 전체 count 보존
- v1/v2 JSON 읽기 호환
- v3 round trip
- 미래 schema 비파괴 거부
- 같은 내용 write 생략
- coverage 변경 시 write 수행
- malformed JSON 자동 교체
- missing/corrupt/staleCoverage/unsupportedNewerSchema 상태 판별
- App Group container unavailable 오류 유지

### 위젯 시각 검증

- systemSmall, systemMedium, systemLarge
- Light/Dark와 모든 AppTheme preset
- 이벤트 0/1/3/4/8개
- 긴 제목과 다양한 이벤트 색상
- 현재 월 5주·6주 가변 배치
- 월 첫날이 일요일/토요일인 경우
- 인접 월 이벤트와 오늘 표시
- 개인정보 redaction 상태
- 작은 iPhone 계열과 iPad의 widget family별 clipping
- tinted 모드에서 이벤트 막대 간 구분 유지

### 통합 검증

- 이벤트 추가·수정·삭제 후 WidgetKit reload
- 테마 변경 후 위젯 팔레트 갱신
- CloudKit import/reconciliation 후 갱신
- 앱 active 전환 후 갱신
- 자정·월 변경 후 현재 날짜와 coverage 갱신
- 앱을 35일 이상 열지 않은 상태를 모사한 다음 월 snapshot 표시
- 시간대 변경 후 오늘 표시와 deep link 확인
- 손상 파일이 있는 상태에서 앱 실행 후 자동 복구
- 연속 갱신 신호가 하나의 발행으로 coalescing되는지 확인

## 12. 회귀 게이트

각 phase마다 다음을 실행한다.

```bash
git diff --check
swift test
xcodebuild -project PlanBase.xcodeproj \
  -scheme PlanBase-iOS \
  -configuration Debug \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO \
  build
```

공통 API와 위젯 타겟 변경이 모두 끝난 뒤에는 전체 회귀 게이트를 실행한다.

```bash
./scripts/verify-platform-builds.sh
```

## 13. 수동 인수 기준

- [ ] 대형 위젯이 날짜별 카드가 아닌 하나의 연속 표로 보인다.
- [ ] 중형·대형 위젯이 월에 따라 5주 또는 6주로 표시된다.
- [ ] 대형 위젯의 날짜 숫자가 이벤트 막대보다 시각적으로 과도하게 크지 않다.
- [ ] 여러 날 이벤트 제목이 날짜마다 반복되지 않는다.
- [ ] 대형 위젯은 일반 크기에서 최대 3개 lane을 보여준다.
- [ ] 중형 위젯에서 모바일 캘린더와 같은 막대로 여러 날 이벤트 기간을 식별할 수 있다.
- [ ] 소형 위젯에서 오늘 이벤트를 최대 4개 확인하고 초과 개수는 헤더 `+N`으로 확인할 수 있다.
- [ ] 숨겨진 이벤트는 고유 이벤트 기준의 정확한 `+N`으로 안내된다.
- [ ] 특정 날짜의 이벤트가 많아도 현재·다음 월의 다른 날짜 표시 후보가 누락되지 않는다.
- [ ] 날짜 탭이 해당 날짜의 모바일 캘린더 상세를 연다.
- [ ] 앱을 재실행하지 않아도 정상 timeline 정책으로 날짜가 바뀐다.
- [ ] 앱이 활성화되면 월 coverage와 최신 이벤트가 다시 발행된다.
- [ ] 손상된 snapshot이 다음 발행에서 자동 복구된다.
- [ ] 미래 schema snapshot은 이전 writer가 덮어쓰지 않는다.
- [ ] snapshot 누락·손상·coverage 만료·미래 schema가 실제 빈 일정과 구분된다.
- [ ] Light/Dark와 선택 테마에서 텍스트와 이벤트 색상이 구분된다.
- [ ] VoiceOver가 전체 이벤트 수와 overflow를 정확히 읽는다.

## 14. 제외 범위와 후속 후보

이번 작업에서 제외:

- SwiftData/CloudKit 모델 변경
- 위젯에서 이벤트 생성·수정
- 스크롤 가능한 월간 위젯
- 캘린더 월 수동 이동
- 템플릿 배치와 공휴일 정보를 snapshot에 새로 추가
- 사용자별 위젯 설정 App Intent

후속 후보:

- `오늘`, `월간`, `다가오는 일정`을 선택하는 configurable widget
- 특정 캘린더 색상만 표시하는 필터
- systemExtraLarge 계열 지원 여부 검토
- 이벤트 시작 시각과 위치를 포함한 별도 오늘 일정 위젯

## 15. 권장 커밋 순서

```text
1. test(calendar): add shared event grid layout coverage
2. refactor(calendar): share event segment layout with mobile and widget
3. fix(widget): prioritize current coverage and recover corrupt snapshots
4. perf(widget): replace unbounded event query with bounded publishing
5. feat(widget): rebuild large calendar as a continuous event grid
6. feat(widget): densify medium and small calendar families
7. test(widget): add accessibility, overflow, and visual fixtures
8. docs(widget): record final density limits and verification results
```

## 16. 구현 및 검증 결과 (2026-07-23)

- 공통 5·6주 이벤트 배치 엔진과 결정적 lane 재사용 규칙을 구현하고 모바일 캘린더와 위젯이 함께 사용하도록 연결했다.
- 소형은 오늘 이벤트 최대 4개와 헤더 `+N`, 중형은 제목 없는 얇은 기간 막대, 대형은 제목이 있는 기간 막대를 사용한다.
- 중형·대형은 날짜별 카드 대신 하나의 연속 표를 사용하고 실제 높이에 맞춰 2~3개 lane을 선택한다.
- snapshot의 캘린더 v3 필드에 coverage, cap 적용 전 일별 count, 물리 레코드 기반 `renderID`를 추가하고 현재·다음 월의 날짜별 표시 후보를 먼저 보존했다. 통합 작업 트리의 현재 schema v4 잠금화면 요약과도 함께 동작한다.
- malformed snapshot은 다음 발행에서 교체하고 미래 schema는 덮어쓰지 않으며, 위젯은 누락·손상·coverage 만료·미래 schema 상태를 빈 일정과 구분한다.
- 발행 쿼리와 변경 관찰 범위를 coverage로 제한하고 앱 시작·active·데이터·CloudKit 관찰값·테마·자정·시간대 신호를 150ms 단위로 병합한다.
- `CalendarEventGridLayout` 및 `CalendarWidgetSnapshot` 자동 테스트, 전체 Swift package 테스트, iOS 앱과 Widget Extension 빌드를 회귀 게이트로 사용했다.
- 실제 홈 화면에서의 기기별 clipping, VoiceOver, privacy redaction, tinted 모드는 배포 전 수동 인수 기준으로 유지한다.
