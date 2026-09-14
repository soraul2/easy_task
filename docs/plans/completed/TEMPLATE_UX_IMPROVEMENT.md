# 템플릿을 저장한 루틴 중심으로 개선

완료: 2026-09-07

## 목적

템플릿 첫 화면에서 저장한 루틴을 즉시 찾아 추가한다. 보드 저장과 루틴 편집은
별도 화면으로 옮겨 적용 흐름을 가리지 않는다. iPhone·iPad·Mac과 캘린더가
같은 목록·상세·편집 UI와 중복 처리 방식을 사용한다.

## 변경

- 공통 TemplateLibraryView가 전체 목록을 기본으로 표시하고 즐겨찾기를 위에 정렬한다.
  검색어가 있으면 즐겨찾기 필터와 관계없이 전체 루틴을 검색한다.
- 보드 진입에서는 적용 날짜를 표시하고 각 루틴에 작업 수·예상 시간·미리보기와 추가 버튼을 제공한다.
  루틴 이름은 상세 화면을 연다.
- 만들기 메뉴에서 직접 만들기와 현재 보드에서 만들기를 선택한다. 저장된 루틴이
  없을 때만 첫 루틴 만들기를 본문에 안내한다.
- TemplateRoutineEditor에서 이름·즐겨찾기·작업 순서·메모·체크리스트·예상 시간·
  우선순위·태그를 편집한다. 복제와 이번에만 조정을 지원한다.
- 편집은 기존 루틴과 유지된 작업의 논리 ID를 보존하고, 보드 작업과 과거 배치 기록은 변경하지 않는다.
  다른 곳에서 내용이 바뀌거나 삭제되었으면 덮어쓰지 않고 초안을 유지한다.
- 평소에는 한 번에 추가한다. 같은 제목이 겹칠 때만 새 작업만 추가하거나 전체를 다시
  추가하도록 선택한다. 보드·캘린더 모두 같은 기본 정책을 사용한다.
- 모바일 보드 적용 후 할 일 목록으로 이동하고, 날짜와 실제 추가 개수를 안내한다.
  시트가 닫힌 후 상태를 전환하고 상태별 작업 목록의 뷰 정체성을 분리해, 완료 탭에서
  루틴을 추가할 때 발생하던 SwiftUI 목록 배치 반복과 응답 정지를 방지한다.
- 캘린더에서는 루틴 선택 후 바로 날짜를 고른다. 실제 추가 개수를 표시하고,
  중복이 없으면 반복 확인창을 생략한다. 날짜 선택 단계의 루틴 삭제 버튼을 제거했다.
- 작업 한 개인 루틴과 저장한 작업은 동일 항목이라는 설명을 제공하고 삭제 시 영향 범위를 안내한다.
- 큰 글자에서는 관리·추가 버튼을 세로로 배치해 글자가 압축되지 않도록 한다.
- 연결된 저장한 작업 화면의 즐겨찾기·메뉴 버튼에 명시적인 터치 영역을 적용한다.

## 경계

영속 스키마 V11, CloudKit·App Group·백업 식별자와 빠른 입력어는 유지한다.
저장·편집·삭제는 기존 저장 명령의 save/rollback 경계를 따른다.
삭제할 항목의 물리 복사본은 동일 논리 ID 범위 안에서 처리하며, 편집할 대표는 기존 무결성 규칙으로 선택한다.

## 검증

- [x] 루틴 저장·편집·복제·삭제·충돌 및 중복 개수 관련 공통 테스트
- [x] iOS·Watch 테스트용 Debug 빌드
- [x] macOS Debug 빌드
- [x] iPhone 주요 사용자 흐름
- [x] iPad 주요 사용자 흐름
- [x] 전체 플랫폼 Debug/Release 회귀 게이트
- [x] 최종 화면·차이 검토

### 확인한 결과

- 공통 테스트: Debug 419개, Release 417개 통과. 템플릿 관련 17개 테스트에
  편집 시 기존 작업·배치 기록·입력어 보존, 편집 충돌, 복제, 입력 검증, 중복 개수 검증을 포함한다.
- 전체 플랫폼 게이트: iOS·macOS·watchOS Debug/Release 빌드와 내장 번들 검증 통과.
- iPhone: 첫 진입·상세·생성/편집/순서 변경·미저장 확인·저장 실패 복구·중복 선택·
  이번에만 조정·캘린더 적용·배치 해제 후 작업 유지·큰 글자 흐름 확인.
  최종 추가 검증에서 완료 탭 → 루틴 추가 → 할 일 탭 전환, 편집 적용, 큰 글자 버튼 배치를 통과했다.
- Mac: 격리된 검증용 앱에서 목록 → 상세 → 작업 추가, 중복 추가 안내, 루틴 편집·저장 확인.
  최초 자동화 도구의 접근성 조회 실패는 다른 연결 방식으로 해결해 실제 화면과 동작을 확인했다.
- iPad: 첫 진입, 생성·편집·순서 변경과 적용, 완료 탭에서 추가와 중복 선택,
  이번에만 조정과 날짜 선택, 큰 글자, 저장 실패 복구의 6개 UI 테스트 통과.
- 전체 게이트 이후 보완한 큰 글자 버튼과 보드 상태 전환은 iPhone/iPad UI 테스트 및
  iOS Release·macOS Debug 추가 빌드로 검증했다. 마지막 저장한 작업 터치 영역 보완도
  iOS UI 테스트와 macOS Debug 빌드를 통과했다.
- 보드 회귀: 테마 변경 시 입력 내용·날짜·필터 유지, 상태 버튼 위에서 세로 스크롤,
  저장한 작업의 저장·편집·검색·추가·삭제 후 보드 작업 유지의 3개 테스트 통과.
- 모든 UI 테스트는 격리된 메모리 저장소를 사용했다. 실제 사용자 CloudKit 데이터는 사용하지 않았다.

검증 로그: platform-verification.log, iPhone-UI-v2.log, iPhone-UI-v5.log,
iPad-UI.log, iPhone-board-regression.log, iPhone-saved-task-final.log,
iOS-release-final.log, macOS-debug-final.log, macOS-touch-target-final.log.
초기 테스트 실패는 수정 후 관련 시나리오를 다시 통과한 최종 로그와 함께 보존했다.

화면 자료:

- [iPhone 첫 진입](../../../.local/template-ux-improvement/template-library-iphone.png)
- [루틴 상세](../../../.local/template-ux-improvement/template-detail-iphone.png)
- [캘린더 날짜 선택](../../../.local/template-ux-improvement/template-calendar-iphone.png)
- [iPad 첫 진입](../../../.local/template-ux-improvement/template-library-ipad.png)
- [큰 글자에서 버튼 배치](../../../.local/template-ux-improvement/template-large-text-iphone.png)

검증 자료: .local/template-ux-improvement/.
작업 시작 시 기존 변경은 해당 폴더의 changes-at-start.patch에 보존했다.

## TestFlight 배포

사용자의 후속 요청에 따라 2026-09-07 버전 1.0(75)을 iOS·iPadOS·watchOS와 macOS에
업로드했다. iOS·Watch 네 번들과 macOS 두 번들의 build 75, 코드 서명, App Group과
CloudKit Production 권한을 확인했다. iOS는 20:23:54, macOS는 20:25:44 KST에 업로드가
성공했고 Apple 패키지 처리가 시작됐다. CloudKit 스키마는 기존 Production V11을 유지한다.
배포 자료는 `.local/releases/build-75/`에 보관하며 TestFlight 설치 가능 상태는 Apple 처리
완료 후 별도로 확인한다.
