# PlanBase 문서 지도

문서는 현재 운영 기준과 작업 기록을 분리한다. 구현을 변경할 때는 먼저 운영 문서를
확인하고, 과거 설계 의도가 필요할 때만 `plans/` 아래 기록을 참고한다.

## 운영 기준

- [아키텍처](ARCHITECTURE.md): 모듈 경계, 데이터 흐름, 무결성, 백업, 플랫폼 책임
- [CloudKit 동기화](CLOUDKIT_SYNC.md): entitlement, schema 배포, 실기기 수렴 검증
- [데이터 기반 계획](DATA_FOUNDATION_PLAN.md): 데이터 안전 작업 순서와 Git 운영 규칙
- [구조 정리 체크리스트](STRUCTURE_CLEANUP_CHECKLIST.md): 현재 디렉터리·파일 정리 진행 상태

## 출시 전 확인이 남은 계획

- [캘린더 위젯 밀도](plans/active/CALENDAR_WIDGET_DENSITY_PLAN.md)
- [잠금 화면 위젯](plans/active/LOCK_SCREEN_WIDGET_PLAN.md)
- [Task 완료 전환 알림 보존](plans/active/TASK_REMINDER_COMPLETION_RETENTION_PLAN.md)

이 문서들은 코드와 자동 검증은 완료됐지만 실기기 또는 출시 승인 확인 항목을
보존한다. 남은 수동 항목이 끝나면 `plans/completed/`로 옮긴다.

## 완료된 설계·구현 기록

- [기록·회고 UI/UX](plans/completed/ARCHIVE_REVIEW_UI_UX_PLAN.md)
- [캘린더 경험 디자인](plans/completed/CALENDAR_EXPERIENCE_DESIGN_PLAN.md)
- [칸반 상태 UI/UX](plans/completed/KANBAN_STATUS_UI_UX_PLAN.md)
- [UI 리팩터링](plans/completed/REFACTORING_PLAN.md)
- [Task 알림](plans/completed/TASK_REMINDER_PLAN.md)

완료 기록의 파일 크기와 구현 스냅샷은 당시 완료 시점을 설명한다. 현재 구조 판단은
운영 문서와 구조 정리 체크리스트를 우선한다.
