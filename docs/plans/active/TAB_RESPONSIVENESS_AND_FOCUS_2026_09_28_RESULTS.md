# 탭 반응성·Focus 개선 결과 — 2026-09-28

상태: 구현·빌드·TestFlight build 83 업로드 완료. 테스트·UI 자동화·성능 계측은 사용자 요청으로
생략했으며, 체감 속도와 실제 기기 기능 검증은 남아 있다. 앱 소스·빌드 설정은 `c6e3d1d`에 기록했다.

## 요청과 원인 분석의 범위

사용자가 iPhone·iPad 칸반 상단에서 일반 제목 입력 중 끊김과 여러 탭의 전환 지연을 보고했다.
코드에서 반복 정렬, 화면 재계산에 따른 위젯 비교 문자열 생성, 메인 실행 영역의 통계 조회·집계,
숨겨진 화면의 갱신 경로를 확인하고 해당 작업을 줄였다.

이는 코드에서 확인한 지연 가능 경로의 개선이다. 실제 기기의 병목별 소요 시간을 측정하지 않았으므로
보고된 끊김의 단일 원인이나 개선율을 확정하지 않는다. 특히 iCloud 동기화 주기가 짧아서 발생했다는
가설은 입증되지 않았다. CloudKit import 후 수렴·병합·무결성 처리 변경은 이번 범위에서 제외했다.

## 적용한 변경

| 영역 | 변경과 관련 코드 |
|---|---|
| 캘린더 상세 | 날짜·데이터 갱신 시 작업 정렬을 한 번 계산해 여러 표시에서 재사용. [MobileCalendarDaySheet](../../../mobile/App/Features/Calendar/MobileCalendarDaySheet.swift) |
| 위젯 갱신 | 상시 `@Query`와 비교 문자열 생성을 없애고 저장·성공한 CloudKit import·테마·날짜·시간대·앱 활성화로 갱신. 150ms 요청 병합과 순차 쓰기 보호 유지. [CalendarWidgetSnapshotPublisher](../../../shared/WidgetSupport/CalendarWidgetSnapshotPublisher.swift) |
| 기록 통계 | 별도 `@ModelActor`의 ModelContext에서 조회·집계. UI 저장 대기 변경은 값과 식별자만 전달. 데이터 revision·날짜·달력·표시 범위·대기 변경이 같으면 결과 재사용. [ActivityOverviewSession](../../../shared/Core/Services/ActivityOverviewSession.swift), [ActivityOverviewReader](../../../shared/Core/Services/ActivityOverviewReader.swift) |
| 탭·상세 활성 상태 | 숨겨진 화면은 변경 revision만 기록하고 활성화 시 필요한 데이터를 조회. 화면 계층은 유지해 초안·날짜·검색·스크롤 상태를 보존하도록 구성. [VisibleDataRefresh](../../../shared/Core/Components/VisibleDataRefresh.swift), [PersistenceViewRevision](../../../shared/Core/Services/PersistenceViewRevision.swift) |
| 보드·캘린더 조회 | 날짜·월 범위 조회 결과를 보관하고 관련 변경 때 갱신. 캘린더의 전체 템플릿 관찰을 사용 시점 조회로 전환. [MobileBoardView](../../../mobile/App/Features/Board/MobileBoardView.swift), [MobileCalendarView](../../../mobile/App/Features/Calendar/MobileCalendarView.swift) |
| 기록·메모 재진입 | 기록은 변경이 없으면 기존 결과와 페이지 깊이를 재사용. 메모는 기존 편집 세션의 초안 보존·외부 변경 병합 경로를 유지. [ArchiveQuerySession](../../../shared/Core/Services/ArchiveQuerySession.swift), [MobileMemoView](../../../mobile/App/Features/Memo/MobileMemoView.swift) |
| Focus 타이머 | 고정 크기 대신 사용 가능한 폭·높이에 맞춰 조절. 지름 220pt 미만 또는 접근성 글꼴에서는 텍스트 표시. 초 단위 갱신을 타이머에 제한. [FocusModeView](../../../shared/Core/Components/FocusModeView.swift), [FocusModeControls](../../../shared/Core/Components/FocusModeControls.swift) |
| Focus 체크리스트 | iPhone·iPad·Mac 공용 Focus 준비·진행 화면에서 선택 작업의 항목과 완료 수를 표시하고 체크 저장. 저장 실패 시 rollback·오류 표시. [FocusTaskChecklistView](../../../shared/Core/Components/FocusTaskChecklistView.swift) |

화면 갱신 지연은 네트워크 동기화 간격 변경이 아니다. 위젯은 앱이 비활성일 때의 저장·import 알림도
처리하며, 숨겨진 탭의 조회 정책과 분리되어 있다. 체크리스트 전체 완료는 상위 작업을 자동 완료하지 않는다.
Watch는 기존 전용 Focus 화면을 사용하며 이번 공용 화면의 체크리스트 추가 대상이 아니다.

## 확인한 범위

- iOS·macOS·watchOS Debug 빌드 통과.
- iOS(내장 Watch 포함)·macOS Release archive, 서명·권한·배포 패키지 확인과 업로드 성공.
- 스키마 V11, 백업 package V10, 배포 식별자, CloudKit 수렴·무결성 처리 규칙 유지.
- 테스트 작성·실행, UI 자동화, 벤치마크, 실기기 계측, 전체 회귀 스크립트는 실행하지 않음.

빌드·패키지 확인은 기능 검증이나 성능 실측을 대신하지 않는다.
업로드 시각·소스 고정·패키지 확인 근거는 [build 83 배포 기록](../../releases/TESTFLIGHT_BUILD_83.md)을 따른다.
로컬 구현 기록은 `.local/tab-responsiveness-implementation-20260928/report.md`,
배포 증거는 `.local/releases/build-83/`에 보존했다.

## 남은 확인

- [ ] iPhone·iPad 일반 제목 입력과 네 탭 이동의 실제 응답, 데이터 양별 차이
- [ ] 비활성 탭 복귀 후 최신 내용과 메모 초안·검색·선택 날짜·스크롤·기록 페이지 보존
- [ ] 좁은 창·회전·큰 글자에서 Focus 타이머와 체크리스트 표시, 체크 저장·실패 처리
- [ ] 저장·원격 수신·날짜 변경 뒤 위젯 내용 갱신과 기기 간 데이터 수렴
- [ ] TestFlight 설치 가능 상태와 설치 후 기본 실행

이 목록은 미실행 범위 기록이며 검증을 새로 시작하는 지시가 아니다.
과거 수치는 [2026-09-04 반응성 기록](RESPONSIVENESS_OPTIMIZATION.md)과
[2026-09-22 최적화 결과](OPTIMIZATION_2026_09_22_RESULTS.md)에 별도로 보존한다.
