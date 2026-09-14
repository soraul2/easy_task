# 테마 정리와 대표색 개선

## 목표

밝은 테마 6개와 다크 테마 2개를 제공한다. 테마 대표색과 일정 분류색을 분리하고,
기존 테마 선택·활동 그래프 설정·위젯 snapshot ID를 호환한다. 영속 스키마는 바꾸지 않는다.

## 결정

- `appleSystem`(Clean White)에 `apple2020`, `navyBlush`를 연결한다.
- `maroonEmber`(Apricot)에 `solarBerry`를 연결한다.
- `plumNight`, `roseLilac`, `forestCream`, `tealPaper`, `midnightBlue`, `charcoalRose`를 유지한다.
- 기존 ID를 별칭으로 계속 인식하며, 사용자 선택 화면에는 정식 8개만 표시한다.
- 대표색은 버튼 채움, 그 위의 글자, 일반 표면의 강조 글자·아이콘, 옅은 선택 배경으로 나눈다.
- 일정의 6개 색상 ID와 색상 계열은 모든 테마에서 유지한다.
- 활동 그래프 설정 충돌은 필드별로 정식 테마에 이미 저장된 유효한 값 우선,
  현재 선택된 과거 테마의 값, 고정 순서의 다른 별칭 값 순으로 처리한다.
  과거 키는 삭제하지 않는다. 동기화의 유효한 정식 원격 값은 기존 원격 우선 규칙을 따른다.

## 검증 및 결과 (2026-09-07 완료)

- [x] 개선 전 화면 보존
- [x] 팔레트·색상 역할 및 실제 사용 표면 대비 검증
- [x] 설정 이전, 충돌, 구버전 값 수신, snapshot 별칭 테스트
- [x] 테마 선택 화면과 macOS/iOS 강조 요소 연결
- [x] 캘린더·활동 그래프·집중·위젯·Watch 영향 검증
- [x] iPhone/iPad/macOS 화면 비교 및 UI 흐름 검증
- [x] `./scripts/verify-platform-builds.sh`
- [x] 최종 요구사항별 완료 감사

작업 전 사용자 변경은 `.local/theme-improvement/user-changes-at-start.patch`에 별도로 보존했다.
검증 자료와 비교 화면은 `.local/theme-improvement/`에 둔다.

결과는 `.local/theme-improvement/REVIEW.md`에 요구사항별 근거와 원본 이미지 링크로 정리했다.
전체 회귀 스크립트는 종료 코드 0으로 통과했으며, 공통 테스트는 Debug 415개·Release 413개다.
iPhone/iPad 테마·설정 호환·입력 보존, 큰 글자·가로 집중 화면, 캘린더 편집과
위젯 날짜 이동·잠금 화면 집중/휴식 조작을 확인했다. macOS는 메모리 데이터로 직접 화면을 확인했다.

최종 화면 검증에서 Live Activity의 투명 배경이 강조색을 흐리는 문제를 발견해
밝기별 불투명 표면으로 보완했다. 이 마지막 위젯 변경도 추가 Debug/Release 빌드와
시뮬레이터 조작·화면 확인을 통과했다. 실제 CloudKit 진단과 schema 배포는 필요하지 않았다.

## TestFlight 배포 (2026-09-07)

- [x] 전체 앱·확장 build number를 74로 갱신
- [x] iOS universal 앱과 포함된 Watch 앱·컴플리케이션 archive 및 권한 검증
- [x] macOS universal 앱과 위젯 archive 및 권한 검증
- [x] iOS build 74 App Store Connect 업로드 확인
- [x] macOS build 74 App Store Connect 업로드 확인

두 플랫폼 모두 Xcode Organizer에서 `Uploaded to Apple` 상태를 확인했다. Apple 처리 후
TestFlight 설치 가능 상태와 실제 기기 동작은 별도 운영 인수 항목으로 유지한다.
