# 저장한 작업 빠른 입력어

작성일: 2026-09-04

- 저장한 작업에 선택적으로 입력어를 지정한다. `/운동`처럼 입력하고 Enter 또는 추가 버튼으로 현재 보드 날짜에 새 할 일을 만든다.
- `/`는 저장한 작업 후보를 표시하고, 일부 입력은 입력어·제목으로 검색한다. 후보를 누르거나 방향키로 명시적으로 선택할 수 있다.
- 일치하지 않는 입력어와 동기화로 생긴 중복 입력어는 임의의 작업을 추가하지 않고 안내한다. 일반 제목 입력은 기존 방식이다.
- 입력어는 한글·영문 등 문자, 숫자, 밑줄, 하이픈 1~24자다. 대소문자와 Unicode 조합을 정규화한다. 입력어 없이도 보관함 사용은 가능하다.
- 새 작업은 제목·메모·예상 시간·우선순위·태그·체크리스트를 복사하며 이전 진행·완료·알림 상태를 복사하지 않는다.
- V1~V10을 동결하고 V11 TaskTemplate에 optional quickEntryAlias를 추가한다. 기기 간 중복을 unique 제약이나 자동 삭제로 처리하지 않는다.
- 백업 package V10과 DTO에 입력어를 포함한다. 옛 백업의 필드 부재는 기존 입력어를 보존하고 새 백업의 빈 문자열은 명시적 해제를 뜻한다.
- V10 → V11 파일 migration·재개방, 중복/검색/생성/rollback, 백업 왕복·구버전 병합, iPhone·iPad·Mac 입력 흐름과 전체 플랫폼 게이트를 검증한다.
- 실제 CloudKit Development 필드 초기화·수렴 및 Production `CD_TaskTemplate.CD_quickEntryAlias` 배포를 마친 뒤 V11 TestFlight를 업로드한다.

## 구현 결과

- 입력어는 저장한 작업 편집 화면에서 선택적으로 지정·변경·해제한다.
- iPhone·iPad는 보드 전체를 스크롤하며 후보를 선택한다. 큰 글자에서는 후보 제목과 관리 버튼을 세로로 배치한다.
- Mac은 후보 내부 스크롤과 방향키 선택·Enter 추가·Escape 닫기를 지원한다.
- 저장 실패 안내는 편집 화면 위쪽에 표시하고 키보드를 닫아 읽을 수 있게 한다.
- 일반 입력창을 비울 때는 키보드를 유지하고, 작업 추가가 성공하면 입력 내용을 비운다.

## 검증

- 공통 Debug 392개·Release 391개 테스트 통과. V11의 Core Data 모델은 기존 entity와 다른 모델 hash를 유지하며 TaskTemplate에 optional String 필드 하나만 추가하는 것을 확인했다.
- V10 파일 이전·재개방, 기존 템플릿·체크리스트·논리/물리 ID 보존, 중복 거부와 rollback, 같은 날짜에 독립 작업 생성, 동기화 충돌 모사와 삭제된 후보 재확인, 백업 왕복·입력어 해제·구버전 병합 통과.
- iPhone 17e: `/운` 후보 선택, `/운동` 정확한 추가, 선택 날짜 유지, 반복 추가, 없는 입력어 안내와 입력 보존, 지운 뒤 일반 입력, Midnight Blue·최대 글자 크기, 중복 저장 거부 통과.
- Mac: 메모리 저장소에서 입력어 지정·편집, `/` → 방향키 → Enter, `/workout` → Enter와 예상 40분 복사 확인.
- iPad A16: iPhone과 같은 두 시나리오 통과. 키보드를 연 최대 글자 크기 후보 목록과 편집·오류 화면을 확인했다.
- 전체 플랫폼 게이트 통과: iOS·macOS Debug/Release, 내장 watchOS 앱·위젯, 번들 ID·실행 파일·privacy manifest 검사. `platform-gate.log` 종료 코드 0.

상태: 구현·로컬 검증 및 V11 Production 스키마 배포 완료. 화면 검증 자료는
`.local/saved-task-shortcuts/`, 출시 자료는 `.local/releases/build-69/`에 보관한다.

## 출시 검증

- 서명된 macOS Debug 앱에서 Development 초기화 완료. 첫 요청의 시간 초과 후 재시도에 성공했다.
- 같은 Mac의 독립 SwiftData 저장소 두 개에서 실제 Development 서버를 통한 입력어 생성·변경·해제·삭제 8단계 통과. export 성공 후 반대 저장소 import와 보관함 값, 예상 시간·체크리스트를 확인했다.
- 진단 레코드만 UUID와 표식을 함께 확인해 정리했고, 반대 저장소에서도 삭제 전파를 확인했다.
- Production에 입력어 String과 Core Data 대응 asset 필드, String 인덱스 3개 배포 완료. 기존 필드 삭제와 권한 변경 없음.
- iOS·iPadOS·Watch 및 Mac universal 앱·위젯 6개 번들의 1.0 (69), 서명, App Group·CloudKit 권한과 포함 구조를 확인했다.
- App Store Connect 자동 배포 서명의 Production 권한을 확인하고 iOS 18:13:30, macOS 18:13:20 KST에 업로드 성공 및 패키지 처리 시작을 확인했다. 설치 가능 상태는 아직 확인하지 않았다.
- 기존 iPhone TestFlight 68 설치본을 유지했다. 실제 기기 쌍의 실시간 전파·오프라인 중복 입력어 인수는 후속 확인으로 남는다.
