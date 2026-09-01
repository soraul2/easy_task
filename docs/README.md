# PlanBase 문서 지도

문서는 현재 운영 기준과 작업 기록을 분리한다. 구현을 변경할 때는 먼저 운영 문서를
확인하고, 과거 설계 의도가 필요할 때만 `plans/` 아래 기록을 참고한다.

## 운영 기준

- [빠른 시작](../README.md): 현재 배포 기준, scheme과 기본 검증 명령
- [에이전트 작업 지도](../AGENTS.md): 변경 경계, 디렉터리 지도, 기능별 수정 위치
- [프로젝트 구조](../PROJECT_STRUCTURE.md): 주요 진입점과 파일 추가 규칙
- [아키텍처](ARCHITECTURE.md): 모듈 경계, 데이터 흐름, 무결성, 백업, 플랫폼 책임
- [CloudKit 동기화](CLOUDKIT_SYNC.md): entitlement, schema 배포, 실기기 수렴 검증
- [Apple Watch](WATCHOS.md): 독립 실행형 앱, 컴플리케이션 데이터 흐름과 출시 검증
- [데이터 기반 계획](DATA_FOUNDATION_PLAN.md): 최초 데이터 안전 전환 순서, 현재 V8 상태와 남은 실기기 인수
- [구조 정리 체크리스트](STRUCTURE_CLEANUP_CHECKLIST.md): 2026-07 완료 당시 디렉터리·파일 정리 스냅샷

## 진행 중이거나 출시 전 확인이 남은 계획

- [활동 스트릭·히트맵 및 통계 보기](plans/active/ACTIVITY_STREAK_HEATMAP_PLAN.md)
- [macOS·iPhone 기능 정합성](plans/active/CROSS_PLATFORM_PARITY_PLAN.md)
- [캘린더 위젯 밀도](plans/active/CALENDAR_WIDGET_DENSITY_PLAN.md)
- [일정 재사용과 계획일·완료일 기록](plans/active/EVENT_REUSE_AND_TASK_DATE_HISTORY_PLAN.md)
- [macOS 바탕화면 네이티브 위젯](plans/active/MACOS_DESKTOP_WIDGET_PLAN.md)
- [월간 일정·오늘 작업 결합 플래너 위젯](plans/active/PLANNER_WIDGET_PLAN.md)
- [잠금 화면 위젯](plans/active/LOCK_SCREEN_WIDGET_PLAN.md)
- [Task 중심 잠금 화면·Live Activity 확장](plans/active/LOCK_SCREEN_TASK_LIVE_ACTIVITY_PLAN.md)
- [Task 완료 전환 알림 보존](plans/active/TASK_REMINDER_COMPLETION_RETENTION_PLAN.md)

이 문서들은 구현이 진행 중이거나 코드 완료 후 실기기·출시 승인 확인이 남은 작업을
보존한다. 모든 구현과 검증 항목이 끝나면 `plans/completed/`로 옮긴다.

## 완료된 설계·구현 기록

- [접근성·문구·문서·파일 구조 개선](plans/completed/ACCESSIBILITY_AND_MAINTAINABILITY_PLAN.md)
- [기록·회고 UI/UX](plans/completed/ARCHIVE_REVIEW_UI_UX_PLAN.md)
- [캘린더 경험 디자인](plans/completed/CALENDAR_EXPERIENCE_DESIGN_PLAN.md)
- [iPad 네이티브 지원](plans/completed/IPAD_SUPPORT_PLAN.md)
- [칸반 상태 UI/UX](plans/completed/KANBAN_STATUS_UI_UX_PLAN.md)
- [UI 리팩터링](plans/completed/REFACTORING_PLAN.md)
- [Task 알림](plans/completed/TASK_REMINDER_PLAN.md)

완료 기록의 파일 크기와 구현 스냅샷은 당시 완료 시점을 설명한다. 현재 구조 판단은
에이전트 작업 지도, 프로젝트 구조와 아키텍처 문서를 우선한다.
