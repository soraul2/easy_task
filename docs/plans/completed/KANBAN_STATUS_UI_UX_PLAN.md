# 칸반 상태 UI/UX 개선 계획

## 1. 목표와 범위

이 작업은 `할 일 → 진행 중 → 완료`의 상태를 더 빠르게 이해하고, 실수 없이 바꾸며,
변경 결과를 바로 확인할 수 있게 만드는 데 목적이 있다.

대상은 다음과 같다.

- iPhone 보드의 상태 필터, 작업 카드, 상태 변경 컨트롤, 결과 피드백
- macOS 보드의 컬럼 헤더, 작업 카드, 상태 변경 버튼과 메뉴, 드래그 앤 드롭 피드백
- 상태 UI의 VoiceOver, 큰 글자, 키보드/포인터, 동작 줄이기 대응
- 기존 완료 전환 알림 정책의 회귀 방지

다음은 범위에서 제외한다.

- iPhone 위젯과 위젯 snapshot 발행 경로
- `Task.status`, `Task.reminderAt`을 포함한 영속 모델과 CloudKit schema 변경
- 알림 예약·취소 정책 자체의 변경
- 토스의 그래픽 또는 TDS 자산 복제

## 2. 공식 가이드에서 가져온 원칙

### Apple Human Interface Guidelines

- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines):
  콘텐츠와 컨트롤의 위계를 분명히 하고, 플랫폼 관례와 일관성을 유지한다.
- [Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls):
  서로 밀접한 보기나 상태를 전환할 때 사용하고, 현재 선택을 한눈에 구분하며,
  iPhone에서는 선택지 수를 제한한다. 이 보드의 3개 상태 필터는 이 조건에 맞는다.
- [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons):
  모바일 버튼은 최소 44×44pt의 hit region과 명확한 눌림 상태를 제공한다.
- [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback):
  일상적인 상태 결과는 화면 안에서 가볍게 보여주고, 중요한 경고만 alert로 중단한다.
- [Drag and drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop):
  드롭 가능한 대상을 드래그 중에 강조하고, 드래그가 어려운 사용자를 위한 대체 조작을 제공한다.
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility):
  색만으로 상태를 전달하지 않고, 큰 글자·VoiceOver·동작 줄이기 환경에서도 핵심 흐름을 유지한다.

### Toss 공식 디자인 자료

- [토스 디자인 시스템](https://developers-apps-in-toss.toss.im/design/components.html):
  반복되는 상태 UI를 같은 규칙의 컴포넌트로 만들어 제품 경험을 일관되게 한다.
- [UI/UX 가이드](https://developers-apps-in-toss.toss.im/design/consumer-ux-guide.html):
  문구는 짧고 능동적이며 긍정적으로 쓰고, 그래픽은 장식보다 의미 전달에 사용한다.
- [토스 디자이너가 제품에만 집중할 수 있는 방법](https://toss.tech/article/toss-design-system):
  기본·긴 텍스트·다크 모드·큰 글자·VoiceOver를 컴포넌트 단계에서 함께 처리하고,
  터치 결과에는 절제된 시각·촉각 피드백을 제공한다.

이 프로젝트는 토스 앱 내부 서비스가 아니므로 TDS 자산이나 외형을 복제하지 않는다.
대신 명확한 위계, 간결한 문구, 일관된 컴포넌트, 접근성이라는 설계 원칙만 적용한다.

## 3. 현재 문제

### iPhone

- 상단 기본 세그먼트는 상태별 작업 수와 상태 의미를 보여주지 않는다.
- 카드의 상태는 배경색과 하단 선택 영역에 크게 의존해 색각 차이가 있으면 인지가 늦다.
- 카드 상태 컨트롤 높이가 40pt라 Apple의 44pt 권장 hit region보다 작다.
- 상태를 바꾼 뒤 문구가 `이동됨` 형태여서 사용자 행동의 결과가 덜 직접적으로 느껴진다.
- 모든 상태의 빈 화면이 같은 아이콘과 같은 설명을 사용한다.

### macOS

- 컬럼 전체 배경색이 강하지만 아이콘·설명에 의한 상태 위계는 약하다.
- 드래그 중 어느 컬럼이 드롭을 받을 수 있는지 별도 강조가 없다.
- 메뉴는 모든 상태로 이동할 수 있지만, 가장 자주 쓰는 다음 행동이 드러나지 않는다.
- 카드 hover의 scale/offset 애니메이션이 `동작 줄이기` 설정을 따르지 않는다.

## 4. 목표 경험

### 공통 상태 언어

| 상태 | 심볼 | 짧은 설명 | 주 행동 |
|---|---|---|---|
| 할 일 | `circle.dashed` | 시작을 기다려요 | 진행 시작 |
| 진행 중 | `play.circle.fill` | 지금 집중하고 있어요 | 완료 |
| 완료 | `checkmark.circle.fill` | 마무리했어요 | 다시 진행 |

색은 보조 신호로만 사용한다. 모든 위치에서 심볼, 상태명, 선택 표시 중 두 가지 이상을
같이 제공한다.

### iPhone

1. 상단 상태 필터를 3개의 동일한 status tile로 구성한다.
   - 심볼, 상태명, 작업 수를 표시한다.
   - 선택 상태는 배경·테두리·VoiceOver selected trait로 중복 표현한다.
   - 각 tile은 최소 56pt 높이를 확보한다.
2. 카드 상단에 현재 상태 badge를 추가하고 완료 제목은 취소선으로 보조 표현한다.
3. 카드 하단 상태 컨트롤을 48pt 이상의 3단 직접 선택 컨트롤로 개선한다.
   - 모든 상태를 한 번에 볼 수 있게 유지한다.
   - 현재 상태는 checkmark와 외곽선으로도 구분한다.
   - 상태가 실제로 저장된 뒤 한 번의 절제된 selection feedback을 제공한다.
4. 빈 화면은 상태별 다음 행동을 알려주는 긍정적인 문구를 사용한다.
5. 결과 toast는 `진행을 시작했어요`, `완료했어요`, `할 일로 옮겼어요`처럼 능동형으로 쓴다.

### macOS

1. 컬럼 헤더에 상태 심볼, 짧은 설명, 작업 수를 한 위계로 묶는다.
2. 카드에 현재 상태 badge와 가장 가능성이 높은 다음 행동 버튼을 제공한다.
3. 기존 상태 메뉴는 모든 상태로 이동하는 대체 경로로 유지하고 현재 항목에 checkmark를 표시한다.
4. 드래그 중 대상 컬럼의 테두리와 안내 문구를 강조하고, 벗어나면 즉시 원상 복귀한다.
5. `동작 줄이기`에서는 hover scale/offset과 이동 transition을 제거하고 opacity 중심으로 피드백한다.

## 5. 알림 완료 정책 불변 조건

UI를 바꾸더라도 상태 변경은 기존 `requestTaskStatusChange` 경계를 반드시 통과한다.

| 전환 | 미래 알림 | 결과 |
|---|---:|---|
| 미완료 → 완료 | 없음 또는 이미 지남 | 경고 없이 완료 |
| 미완료 → 완료 | 남아 있음 | 경고 후 사용자 확인 시 완료 |
| 완료 → 할 일/진행 중 | 기록 존재 여부 무관 | 경고 없이 이동 |

모든 경우 `Task.reminderAt` 기록은 유지한다. 완료할 때 pending notification만 취소하며,
다시 미완료 상태로 옮겼을 때 지난 알림을 자동 재예약하지 않는다.

## 6. 구현 순서

1. `TaskStatus`의 공통 표시 메타데이터를 한 곳에 정의한다.
2. iPhone 상태 필터와 카드 상태 컨트롤을 교체하고 상태별 빈 화면·toast를 연결한다.
3. macOS 컬럼 헤더·카드 주 행동·드롭 강조·동작 줄이기를 연결한다.
4. 상세 편집의 system segmented control은 밀접한 단일 선택이라는 용도에 맞으므로 유지한다.
5. UI 테스트를 안정적인 accessibility identifier로 전환하고 상태 선택/알림 회귀를 검증한다.
6. 라이트·다크 모드, 큰 글자, VoiceOver label/value, 작은 iPhone 폭, macOS hover/drop을 확인한다.

## 7. 완료 기준

- iPhone에서 각 상태 필터에 상태명·작업 수·선택 상태가 보이고 44pt 이상으로 조작된다.
- 카드에서 색을 보지 않아도 현재 상태와 이동 가능한 상태를 알 수 있다.
- macOS 드래그 중 유효한 대상 컬럼이 명확히 강조된다.
- macOS 카드에서 드래그 없이도 다음 상태와 임의 상태로 모두 이동할 수 있다.
- VoiceOver가 상태명, 작업 수, 선택 여부, 버튼 결과를 읽는다.
- `동작 줄이기`에서 불필요한 scale/offset 이동이 없다.
- 미래 알림 완료 경고, 지난 알림 무경고, 알림 기록 보존 UI 테스트가 모두 통과한다.
- Swift Package 테스트와 iOS/macOS Debug·Release 빌드가 통과한다.
- 이 칸반 작업 범위에서는 위젯 관련 파일을 변경하지 않는다.

## 8. 구현 및 마지막 점검 결과 (2026-07-24)

- [x] `TaskStatus` 공통 표시 메타데이터와 다음 행동 규칙 구현
- [x] iPhone 상태 필터, 카드 상태 표현, 직접 선택 컨트롤, 상태별 빈 화면과 결과 피드백 구현
- [x] macOS 컬럼 헤더, 카드 다음 행동, 상태 메뉴, 드롭 대상 피드백과 동작 줄이기 구현
- [x] 미래 알림 완료 경고, 지난/없는 알림 무경고, 완료 후 알림 기록 보존 UI 회귀 테스트 통과
- [x] 라이트·다크 모드와 접근성 큰 글자 시각 점검
- [x] Swift Package 전체 232개 테스트 및 iOS Release 빌드 통과
- [x] 변경 파일 공백 오류 검사 통과
- [x] 위젯은 다른 팀 작업 범위로 유지하고 칸반 구현에서 제외

macOS 칸반 변경은 별도 Debug 빌드에서 컴파일을 확인했다. 최종 전체 macOS Release 빌드는
칸반 파일이 아닌 `desktop/App/AppRootView.swift`의
`AppThemePreset.targetsWCAGTextContrast` 참조와 현재 테마 모델 간 불일치 때문에 중단된다.
동시 작업 중인 테마 범위를 침범하지 않기 위해 이 문서의 작업에서는 해당 파일을 수정하지 않았다.
