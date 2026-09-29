# CloudKit·배포 이력 — build 78까지

이 문서는 2026-07-11~2026-09-14의 서버 스키마·실기기 수렴·TestFlight 배포 기록이다.
2026-09-28 문서 정리 때 `CLOUDKIT_SYNC.md`의 기존 이력 본문을 그대로 옮겼다.
당시 버전·테스트 수·성공 및 미확인 범위는 과거 증거이며 최신 빌드의 결과가 아니다.

현재 운영 절차는 [CloudKit 동기화](../CLOUDKIT_SYNC.md), 최신 배포·후속 기록은
[문서 지도](../README.md)를 따른다. 이력에 등장하는 `.local/` 경로는 저장소 루트 기준이다.

## 보존한 원문

2026-07-11 개발 환경에서 macOS의 기존 87개 레코드 브리지와 CloudKit
setup/import/export, iPhone 서명 빌드 및 설치를 확인했다. 2026-07-12에는 양방향
create/delete 전파를 실기기에서 확인했다. 2026-07-21에는 Production V6 record type과
Development 대비 미배포 스키마 변경 0건을 CloudKit Console에서 확인했다.
2026-08-14에는 Development에서 `TaskCompletionActivity` create/delete 양방향 probe와
진단 레코드 정리를 통과한 뒤 V7 record type, 28개 index와 security role 변경을
Production에 배포했다. 이어 macOS TestFlight build 30을 재시작해 이전에 실패했던
활동 72건이 모두 export되어 upload 대기가 0건이 되고, 앱의 iCloud 상태가 같은 시각의
성공으로 갱신되는 것을 확인했다. iPhone 14 Pro에는 같은 build 30 코드의 Development
서명본을 Production CloudKit entitlement로 검증 설치해 setup/import/export 성공과
upload 대기 0건을 확인했다. macOS와 iPhone 저장소의 11개 엔터티별 행 수가 모두 같고,
활동은 양쪽 모두 전체 177건·활성 논리 레코드 73건으로 수렴했다. 기록 화면도 양쪽에서
2일 연속·최근 1년 최고 4일·오늘 완료 4건을 동일하게 표시했다. 진단 뒤에는 앱 삭제 없이
TestFlight에서 iOS build 30을 다시 설치했다. beta 설치본의 setup/import/export가 22:35에
다시 성공했고 upload 대기 0건과 같은 활동 수·기록 화면이 유지되는 것을 확인했다.
2026-08-15에는 V8 Development schema를 초기화하고 `TaskProgressEvent`의 macOS → iPhone,
iPhone → macOS 생성·삭제와 양쪽 export/import 성공, 진단 레코드 정리를 확인했다.
같은 날 CloudKit Console에서 `CD_TaskProgressEvent` record type과 관련 인덱스 28개를
Production에 배포하고, Production record type 목록에서 반영을 다시 확인했다. 이어
iOS TestFlight build 33 archive의 App Group·CloudKit entitlement를 검증한 뒤 App Store
Connect 업로드에 성공했다. 이어 기존 3상태 보드를 복원하고 진행 시간 기록을 유지한
iOS TestFlight build 34도 같은 entitlement 검증을 통과해 App Store Connect에 업로드했다.
2026-08-31에는 월간 일정과 오늘 Task를 결합한 planner widget을 포함한 iOS TestFlight
build 40의 앱·위젯 App Group과 앱 CloudKit entitlement, archive 내 planner widget kind를
검증한 뒤 App Store Connect 업로드에 성공했다. Apple 처리 완료와 실제 iPhone/iPad 위젯
gallery 인수는 별도로 확인한다. 같은 날 참고 이미지형 `systemMedium` 플래너를 추가한
iOS TestFlight build 41도 앱·위젯 build number, App Group·CloudKit entitlement와 archive
내 planner widget kind를 검증한 뒤 App Store Connect 업로드에 성공했다. Apple 처리 완료와
실제 기기 gallery 노출은 별도로 확인한다.
같은 날 Task 중심 잠금 화면 위젯과 진행 중 Task 전용 Live Activity를 포함한 iOS
TestFlight build 42도 앱·위젯 build number, 기존 App Group·CloudKit entitlement와
`NSSupportsLiveActivities` 선언을 서명 archive에서 검증한 뒤 App Store Connect 업로드에
성공했다. Apple 처리 완료 후 iPhone 잠금 인증·Always On·Dynamic Island를 우선 확인하고,
iPad와 macOS 시스템 표현을 순서대로 인수한다.
이어 Live Activity의 진행 막대를 제거하고 완료·다음 조작 영역을 58×48pt 버튼으로 확대한
iOS TestFlight build 43도 공통 테스트 328개와 iOS Release 빌드를 통과했다. 앱·위젯 build
number, App Group·CloudKit entitlement와 `NSSupportsLiveActivities`를 서명 archive에서 다시
검증한 뒤 App Store Connect 업로드에 성공했다.
이어 Dynamic Island 최소형·축소형·확장형에 RunCat 기본 Cat 애니메이션과 현재 Task 제목을
적응형으로 추가한 iOS TestFlight build 44도 Release 테스트 327개와 iOS Release 빌드를
통과했다. 앱·위젯 build number, App Group·CloudKit entitlement,
`NSSupportsLiveActivities=true`, RunCat 5프레임과 Apache 2.0 라이선스 포함 여부를 서명
archive에서 검증한 뒤 App Store Connect 업로드에 성공했다.
build 44 실기기 확인 후에는 Live Activity가 timeline 기반 지속 애니메이션을 지원하지 않고
콘텐츠 변경 애니메이션도 최대 2초로 제한되는 점을 확인했다. 따라서 후속 소스에서는 RunCat
코드·자산·라이선스를 제거하고 Dynamic Island 진행 상태를 시스템 아이콘과 텍스트로
표현한다.
이어 RunCat을 제거하고 시스템 timer text로 누적 진행 시간을 표시하는 iOS TestFlight
build 45도 Release 패키지 테스트와 서명 archive 생성을 통과했다. 앱·위젯 build number,
App Group·CloudKit entitlement, `NSSupportsLiveActivities=true`, 캘린더·플래너·잠금 화면
widget kind와 Activity 타입 포함 여부를 검증한 뒤 App Store Connect 업로드에 성공했고
패키지 처리가 시작됐다.
이어 Dynamic Island 축소형의 긴 Task 제목을 제거하고 leading에 파란 활성 점과 누적 진행
시간만 배치한 iOS TestFlight build 46도 Release 패키지 테스트 327개와 서명 archive 생성을
통과했다. 앱·위젯 build number, App Group·CloudKit entitlement와
`NSSupportsLiveActivities=true`를 검증한 뒤 App Store Connect 업로드에 성공했고 패키지
처리가 시작됐다.
build 46 실기기 확인 뒤에는 Dynamic Island compact의 leading에 누적 진행 시간, trailing에
파란 활성 점을 분리 배치하고, 날짜 상대 표현 대신 숫자형 count-up interval을 사용해 잠금
화면의 `hours`, `minutes` 문구를 제거했다. 이를 포함한 iOS TestFlight build 47은 Release
패키지 테스트 327개, Debug 빌드, 서명 archive와 앱·위젯 build number, App Group·CloudKit
entitlement, `NSSupportsLiveActivities=true` 검증을 통과한 뒤 App Store Connect 업로드에
성공했고 패키지 처리가 시작됐다.
build 47의 iPhone·macOS 실기기 표시 확인 후 Live Activity UI를 신규 구조로 다시 작성했다.
Dynamic Island compact는 leading 숫자 stopwatch와 trailing 6pt 활성 점만 사용하고 제목,
Spacer, 고정 너비, 수동 여백과 그림자를 제거했다. 이 변경을 포함한 iOS TestFlight build
48은 Release 패키지 테스트 327개와 서명 archive 생성을 통과했다. 앱·위젯 build number,
App Group·CloudKit entitlement와 `NSSupportsLiveActivities=true`를 검증한 뒤 App Store
Connect 업로드에 성공했고 패키지 처리가 시작됐다.
build 48 실기기 확인 후 compact 시간을 숫자 전용 2개 필드로 추가 축소했다. 1시간 미만에는
`mm:ss`, 1시간 이상에는 `h:mm`으로 전환하며 잠금 화면과 Dynamic Island 확장형은 기존
3개 필드 표시를 유지한다. 시스템의 2필드 stopwatch는 1시간부터 `시간`, `분` 단위 문구를
붙이므로 사용하지 않고, 초·분 경계를 제공하는 discrete format으로 숫자만 갱신한다.
이를 포함한 iOS TestFlight build 49는 Release 패키지 테스트 327개와 서명 archive 생성을
통과했다. 앱·위젯 build number, App Group·CloudKit entitlement와
`NSSupportsLiveActivities=true`를 검증한 뒤 App Store Connect 업로드에 성공했고 패키지
처리가 시작됐다.
build 49 실기기 확인에서 사용자 정의 discrete format이 Live Activity 제한 갱신 상태에서
회색 대시로 redaction됐다. 후속 소스는 사용자 정의 format을 제거하고 시스템 stopwatch를
그대로 사용한다. compact와 minimal에서만 `00:00` 다섯 글자 너비로 clipping해 1시간
미만에는 `mm:ss`, 1시간 이상에는 `hh:mm`만 보이게 한다.
이를 포함한 iOS TestFlight build 50은 Release 패키지 테스트 327개와 서명 archive 생성을
통과했다. 앱·위젯 build number, App Group·CloudKit entitlement와
`NSSupportsLiveActivities=true`를 검증한 뒤 App Store Connect 업로드에 성공했고 패키지
처리가 시작됐다.
build 50 실기기에서는 숨은 기준 문자열의 overlay 안에 둔 시스템 시간도 표시되지 않았다.
후속 소스는 overlay와 clipping을 제거하고 compact·minimal에 시스템
`durationOffset + hourMinute` Text를 직접 배치한다. 두 표현은 항상 `h:mm`을 사용하고,
잠금 화면과 Dynamic Island 확장형만 기존 `h:mm:ss`를 유지한다.
이를 포함한 iOS TestFlight build 51은 Release 패키지 테스트 327개와 서명 archive 생성을
통과했다. 앱·위젯 build number, App Group·CloudKit entitlement와
`NSSupportsLiveActivities=true`를 검증한 뒤 App Store Connect 업로드에 성공했고 패키지
처리가 시작됐다.
build 51 실기기 확인 후 후속 소스에서는 Dynamic Island compact의 trailing 활성 점을
제거했다. compact에는 leading의 시스템 `h:mm` 시간 하나만 남기고, 잠금 화면과 확장형의
활성 상태 표시는 유지한다. 이를 포함한 iOS TestFlight build 52는 Release 패키지 테스트
327개와 서명 archive 생성을 통과했다. 앱·위젯 build number, App Group·CloudKit
entitlement와 `NSSupportsLiveActivities=true`를 검증한 뒤 App Store Connect 업로드에
성공했고 패키지 처리가 시작됐다.
build 52 실기기에서 compact의 시간 외 콘텐츠를 모두 제거해도 시스템 캡슐 폭은 유지됐다.
Apple HIG의 고정 compact 규격과 leading·trailing 결합 구조를 반영해 후속 소스는 leading에
시스템 `h:mm`, trailing에 `완료/전체` 수치를 배치하고 별도 padding은 사용하지 않는다.
minimal은 시스템이 다중 Live Activity 상황에서 선택하므로 시간 단독 표현을 유지한다.
이를 포함한 iOS TestFlight build 53은 Release 패키지 테스트 327개와 서명 archive 생성을
통과했다. 앱·위젯 build number, App Group·CloudKit entitlement와
`NSSupportsLiveActivities=true`를 검증한 뒤 App Store Connect 업로드에 성공했고 패키지
처리가 시작됐다.
build 53 실기기 확인 후 후속 소스는 Apple 공식 Live Activities 예제의 `leading 심볼 +
trailing 동적 값` 패턴을 따라 compactLeading에 주황색 `stopwatch.fill`, compactTrailing에
주황색 시스템 `h:mm`을 배치한다. 별도 padding·배경은 추가하지 않고 진행률은 확장형과 잠금
화면에만 유지한다. 이를 포함한 iOS TestFlight build 54는 Release 패키지 테스트 327개와
서명 archive 생성을 통과했다. 앱·위젯 build number, App Group·CloudKit entitlement와
`NSSupportsLiveActivities=true`를 검증한 뒤 App Store Connect 업로드에 성공했고 패키지
처리가 시작됐다.
build 54 실기기 확인 후 후속 소스는 Dynamic Island expanded의 제목·진행률·버튼을 제거하고
점과 시간만 유지한다. compactLeading의 6pt 점과 compactTrailing의 시스템 `h:mm`에는
`.fixedSize()`를 적용하고 센서 쪽 content margin을 0으로 줄여 공개 API 내 최소 폭을
검증한다. 잠금 화면 Live Activity 구성은 유지한다. 이를 포함한 iOS TestFlight build 55는
Release 패키지 테스트 327개와 서명 archive 생성을 통과했다. 앱·위젯 build number,
App Group·CloudKit entitlement와 `NSSupportsLiveActivities=true`를 검증한 뒤 App Store
Connect 업로드에 성공했고 패키지 처리가 시작됐다.
build 55 실기기에서 compact 시간 누락과 expanded 시간 대시를 확인했다. 두 표현의 공통 신규
제약인 `.fixedSize()`가 실시간 `TimeDataSource`를 제한 영역 밖으로 밀어내는 회귀로 판단해
후속 소스에서는 Dynamic Island의 모든 `.fixedSize()`와 compact 강제 content margin을
제거한다. 점과 시간만 남기는 콘텐츠 범위는 유지한다.
후속 iPhone 17 Pro(iOS 26.5) simulator 교차검증에서 시스템 stopwatch의 큰 이상 너비가
compact 폭의 직접 원인임을 확인했다. 동적 갱신은 그대로 두고 시간에만 32pt 슬롯을 부여해
긴 Task 제목과 무관하게 compact가 약 189pt로 줄었고 `MM:SS`가 초 단위로 증가했다. expanded는
점·시간만, 잠금 화면은 제목·진행 수치·58×48pt 완료/다음 버튼을 유지한다. 잠금 화면에서
`다음`의 Task/타이머 교체와 `완료`의 Activity 종료도 확인했다. 저휘도 Always On에서 초가
`--`로 축약되고 화면을 깨우면 숫자 초가 복원되는 것은 시스템 stopwatch 정책으로 수용한다.
Debug·Release iOS simulator 빌드, 공통 테스트 328개와 iPhone launch smoke test도 통과했다.
이 변경을 포함한 iOS TestFlight build 56은 Release 패키지 테스트 327개와 서명 archive
생성을 통과했다. 앱·위젯 build number, App Group·CloudKit entitlement와
`NSSupportsLiveActivities=true`를 검증한 뒤 App Store Connect 업로드에 성공했고 패키지
처리가 시작됐다. 다음 단계는 iPhone 실기기 인수다.
build 56 실기기에서 1시간 이상 경과 시간이 `7h…`로 잘리고 system stopwatch의 초가 저휘도에서
`--`로 바뀌는 것을 확인했다. 후속 소스는 1초 주기의 직접 숫자 포맷을 사용해 1시간 미만
`MM:SS`, 1시간 이상 `H:MM:SS`를 렌더링한다. Dynamic Island compact는 46pt 이내 Task 제목과
50pt 시간을, 잠금 화면과 expanded는 72pt 시간을 사용한다. iPhone 17 Pro(iOS 26.5)
simulator의 7시간 fixture에서 compact 초 단위 증가와 잠금 화면 `7:21:39`를 확인해 단위 문구와
`--`를 모두 제거했다. 잠금 화면에는 테마 색상의 48×48pt `→`·`✓` 버튼을 적용했고, 선택형
`themeID`를 Live Activity state에 추가해 기존 in-flight state와의 decode 호환성을 유지했다.
모든 앱·위젯 테마 preset은 시스템 라이트/다크 모드와 무관하게 고정 팔레트와 다크 표현 모드를
사용한다. 시스템 라이트 모드의 iPhone 17 Pro simulator에서 8개 preset을 모두 순회하고 다크
모드 대표 화면과 비교해 배경·카드·상태·강조색·텍스트 대비와 팔레트 고정을 확인했다. Debug
328개·Release 327개 테스트와 iOS/macOS Debug·Release 전체 빌드를 통과했다. 앱·위젯 build
57, App Group·CloudKit entitlement와 `NSSupportsLiveActivities=true`를 서명 archive에서
검증한 뒤 App Store Connect 업로드에 성공했고 패키지 처리가 시작됐다.

밝은 파스텔 8종과 Apple 2020 테마, 잠금 화면 단일 완료 입력 보호 및 계획 Task 진행 버튼을
포함한 iOS TestFlight build 58은 Release 패키지 테스트 329개와 iOS Release 빌드를 통과했다.
앱·위젯 build 58, App Group·CloudKit entitlement, `NSSupportsLiveActivities=true`와 Activity
타입을 서명 archive에서 검증한 뒤 App Store Connect 업로드에 성공했고 패키지 처리가 시작됐다.

고정 다크 테마 Midnight Blue와 Charcoal Rose를 추가한 iOS TestFlight build 59는 Release
패키지 테스트 330개와 iOS Release 빌드를 통과했다. 두 테마는 시스템 모드와 무관하게 다크
표현을 유지하며 iPhone 17 Pro simulator에서 상태바·카드·탭 대비를 확인했다. 앱·위젯 build
59, App Group·CloudKit entitlement, `NSSupportsLiveActivities=true`와 Activity 타입을 서명
archive에서 검증한 뒤 App Store Connect 업로드에 성공했고 패키지 처리가 시작됐다.

같은 고정 테마를 적용한 macOS TestFlight build 59는 공통 테스트 331개와 macOS
Debug·Release 빌드를 통과했다. 서명 archive에서 앱 `com.soraul2.easytask`와 위젯
`com.soraul2.easytask.widget`의 build 59, 앱의 CloudKit·App Group 권한과 위젯의 App Group
권한을 확인한 뒤 App Store Connect 업로드에 성공했고 패키지 처리가 시작됐다.

iPhone 접근성 글자 크기 레이아웃, 기록 카드의 `보드 열기` 문구와 날짜별 고유 접근성
identifier, V8 작업 지도 및 대형 파일 책임 분리를 포함한 iOS TestFlight build 60은 Debug
331개·Release 330개 공통 테스트, 모바일 테스트 16개와 접근성·기록 이동·기본 글자 크기 UI
test를 통과했다. 서명 archive에서 앱·위젯 build 60, App Group·CloudKit entitlement,
`NSSupportsLiveActivities=true`를 확인한 뒤 App Store Connect 업로드에 성공했고 패키지
처리가 시작됐다.

같은 공통 코어·테마·구조 분리를 적용한 macOS TestFlight build 60도 iOS·macOS
Debug·Release 전체 회귀 빌드를 통과했다. 서명 archive에서 앱·위젯 build 60, Production
bundle ID, 앱의 CloudKit·App Group·key-value store와 위젯 App Group 권한을 확인한 뒤
App Store Connect 업로드에 성공했고 패키지 처리가 시작됐다.

독립 실행형 Watch 앱과 컴플리케이션을 포함한 iOS TestFlight build 61은 iOS 앱·위젯과
Watch 앱·위젯의 build 번호, bundle ID, companion 관계, `WKApplication`, 코드 서명을
검증했다. iOS와 Watch 앱의 CloudKit·App Group·key-value store, 두 위젯의 App Group
권한을 확인한 뒤 App Store Connect 업로드에 성공했고 패키지 처리가 시작됐다.

V9 복합 메모와 백업 package V8을 포함한 iOS·macOS TestFlight build 62는 Debug SwiftPM
337개와 Release SwiftPM 336개 및 양 플랫폼 Debug·Release 전체 회귀를 통과했다. CloudKit
Development 스키마 초기화와 V9 Production 배포 후, iOS·iPadOS·Watch 앱·위젯 및 macOS
앱·위젯의 build 번호, 서명, CloudKit·App Group·key-value store 권한을 확인했다. 두
아카이브 모두 App Store Connect 업로드에 성공했고 패키지 처리가 시작됐다.

2026-09-03에는 서명된 macOS Debug 앱의 `--initialize-cloudkit-schema` 실행으로 V10
Development 스키마 초기화를 완료하고 `CD_FocusSession` 21개 필드를 확인했다. CloudKit
Console의 배포 diff가 record type 1개 생성, 해당 타입 index 31개 생성, 기본 security role
3개 수정만 포함하고 삭제·이름 변경이 없음을 검토한 뒤 Production에 배포했다. Production
record type 목록에서도 `CD_FocusSession` 21개 필드를 다시 확인했다. 실제 기기의
FocusSession 양방향 생성·삭제 수렴 검증은 후속 운영 인수 게이트로 유지한다. 이어 V10과
backup package V9을 포함한 iOS·iPadOS·Watch 앱·위젯 및 macOS 앱·위젯의 build 63,
bundle ID, CloudKit·App Group·key-value store 권한과 포함 구조를 서명 archive에서
확인했다. iOS와 macOS 아카이브 모두 App Store Connect 업로드에 성공했고 패키지 처리가
시작됐다.

같은 날 비활성 전역 Focus 버튼을 제거하고 보드의 `doing` 영역에 시작 진입점을 옮긴
build 64도 iOS 앱·위젯, Watch 앱·위젯과 macOS universal 앱·위젯의 Release archive를
생성했다. 네 iOS/Watch 번들과 두 macOS 번들의 build 번호, bundle ID, 코드 서명,
CloudKit·App Group·key-value store 권한과 포함 구조를 다시 확인했다. iOS와 macOS
아카이브 모두 App Store Connect 업로드에 성공했고 패키지 처리가 시작됐다.

같은 날 Focus와 휴식 종료 알림의 빠른 동작, 60분 action token, stale·중복 실행 방지와
foreground 중복 banner 억제를 iOS·macOS·Watch에 연결한 build 65를 배포했다. Debug 356개와
Release 355개 공통 테스트, iOS·macOS·watchOS Debug/Release 전체 회귀 게이트를 통과했고,
네 iOS/Watch 번들과 두 macOS 번들의 버전, bundle ID, 코드 서명과 공유 권한을 확인했다.
iOS와 macOS 아카이브 모두 App Store Connect 업로드에 성공해 패키지 처리가 시작됐다.

2026-09-04에는 회고 없는 날짜별 활동, 통계 제거 및 읽기 전용 작업 기록을 포함한 build 66을
업로드했다. V10 스키마와 백업 V9은 변경하지 않았다. Debug 374개·Release 373개 테스트와
전체 플랫폼 회귀 게이트, 여섯 앱·위젯 번들의 서명·버전·공유 권한 확인을 통과했다.
자동 배포 서명 과정의 CloudKit Production 권한과 iOS·macOS 업로드 성공 및 패키지 처리
시작을 확인했다. 로그와 서명 검증 결과는 `.local/releases/build-66/`에 보관한다.

같은 날 저장한 작업 재사용, 칸반 버튼·테마·큰 글자 화면 개선과 테마 변경 중 초안 유지,
작업 삭제 안정성 수정을 포함한 build 67도 iOS·macOS 모두 업로드했다. V10 스키마와 백업
V9은 유지했다. 기능 변경 후 Debug 382개·Release 381개 공통 테스트와 전체 플랫폼 회귀를
통과했고, build 67의 여섯 앱·위젯 번들 버전·서명·App Group·CloudKit 권한을 재검증했다.
자동 배포 서명의 CloudKit Production 권한, 두 플랫폼 업로드 성공과 패키지 처리 시작을
확인했다. TestFlight 설치 가능 상태는 아직 확인하지 않았으며 배포 자료는
`.local/releases/build-67/`에 보관한다.

같은 날 집중모드 화면과 예상 시간 반영을 포함한 build 68도 두 플랫폼에서 업로드했다.
V10 스키마와 백업 V9은 유지했다. Debug 385개·Release 384개 공통 테스트와 전체 플랫폼
회귀를 통과했고, 최종 집중 UI 시나리오를 iPhone·iPad에서 각각 3개씩 재검증했다.
build 68의 앱·위젯 6개 서명·버전·공유 권한, 자동 배포 서명의 CloudKit Production 권한을
확인했다. iOS 15:49:03, macOS 15:49:29 KST 업로드 성공 및 패키지 처리 시작을 확인했다.
TestFlight 설치 가능 상태는 별도 확인 대상이며 자료는 `.local/releases/build-68/`에 보관한다.

같은 날 저장한 작업의 빠른 입력어를 포함한 build 69를 업로드했다. V11 Development 초기화,
독립 저장소 두 개의 실제 서버 왕복 8단계와 진단 레코드 정리 후 Production 필드·인덱스를
배포했다. Production `CD_TaskTemplate`의 21개 필드와 새 입력어 String·대응 asset 필드를
확인했다. Debug 392개·Release 391개 테스트, 전체 플랫폼 회귀와 iPhone·iPad UI 각 2개 및
Mac 입력 흐름을 통과했다. 앱·위젯 6개 번들의 build 69·서명·공유 권한과 자동 배포 서명의
Production 권한을 확인했고, iOS 18:13:30, macOS 18:13:20 KST 업로드 성공 및 패키지 처리
시작을 확인했다. 설치 가능 상태와 실기기 쌍 인수는 남아 있으며 자료는
`.local/releases/build-69/`에 보관한다.

같은 날 앱 재실행·입력어 후보·탭 이동의 불필요한 쓰기와 갱신을 줄인 build 70을 업로드했다.
V11 스키마와 백업 V10은 유지하므로 추가 CloudKit schema 배포는 하지 않았다. Xcode 26.6의
전체 플랫폼 Debug/Release 회귀 게이트와 여섯 앱·위젯의 서명·build 70·공유 권한 검증을
통과했다. 최종 컴파일 소스 해시와 배포용 Release의 테스트 fixture 제외도 확인했다.
자동 배포 서명의 CloudKit Production 권한, iOS 22:16:34 및 macOS 22:18:08 KST 업로드 성공과
패키지 처리 완료를 확인했다. 두 플랫폼의 기존 내부 그룹 `지인`(2명) 연결과 한국어 테스트
안내 저장도 확인했다. 실제 TestFlight 설치·실기기 쌍 수렴은 별도 인수 대상이다.
배포 자료와 로그는 `.local/releases/build-70/`에 보관한다.

2026-09-05에는 버튼·모달·안내·접근성 표현과 플랫폼별 화면 흐름을 정리한 build 71을
iOS·iPadOS·watchOS와 macOS에 업로드했다. V11 스키마와 백업 V10을 유지해 추가 CloudKit
schema 배포는 하지 않았다. iteration424 전체 플랫폼 회귀와 iOS/Watch 네 번들·macOS 두
번들의 앱 버전 1.0, build 71, bundle ID, 코드 서명, App Group·CloudKit 권한을 확인했다.
archive가 사용한 컴파일 소스 iOS 190개·macOS 182개의 배포 snapshot 일치와 일반 Release의
검사 fixture 제외도 확인했다. iOS 18:20:29, macOS 18:22:09 KST에 App Store Connect 업로드가
성공했고 Apple 패키지 처리가 시작됐다. 설치 가능 상태와 실제 기기 운영 인수는 별도 확인하며,
배포 자료와 로그는 `.local/releases/build-71/`에 보관한다.

2026-09-06에는 칸반 카드 디자인 개선을 포함한 build 72를 업로드했다. 전체 플랫폼
Debug/Release 회귀와 공통 테스트 Debug 407개·Release 405개, 여섯 앱·위젯의 서명·build 72·
App Group·CloudKit 권한을 확인했다. 컴파일 소스 iOS 190개·macOS 182개가 배포 snapshot과
일치한다. Xcode Organizer에서 앱과 Watch의 운영용 CloudKit Production 권한을 확인하고
iOS 04:00:39, macOS 04:04:12 KST에 업로드 성공 및 Apple 패키지 처리 시작을 확인했다.
V11 스키마와 백업 V10은 유지한다. 실제 TestFlight 설치 가능 상태는 별도 확인 대상이며,
배포 자료는 `.local/releases/build-72/`에 보관한다.

2026-09-07에는 테마 정리와 대표색 개선을 포함한 build 74를 업로드했다. 기존 선택과
위젯 snapshot ID의 호환성을 유지하면서 사용자 선택 테마를 밝은 테마 6개와 다크 테마 2개로
정리했다. 전체 플랫폼 회귀와 공통 테스트 Debug 415개·Release 413개를 통과했고, iOS 앱·위젯·
Watch 앱·컴플리케이션과 macOS 앱·위젯의 버전 1.0·build 74·서명·App Group·CloudKit 권한을
확인했다. Xcode Organizer에서 iOS와 macOS 모두 `Uploaded to Apple` 상태를 확인했다.
V11 스키마와 백업 V10은 유지하며, Apple 처리 후 TestFlight 설치 가능 상태는 별도 확인 대상이다.
배포 자료와 로그는 `.local/releases/build-74/`에 보관한다.

같은 날 저장한 루틴을 먼저 보여주는 템플릿 목록, 별도 생성·편집·복제, 작업 순서 변경,
`이번에만 조정`, 보드·캘린더의 명시적 중복 추가 선택을 포함한 build 75를 업로드했다.
전체 플랫폼 회귀에서 공통 테스트 Debug 419개·Release 417개와 iOS·macOS·watchOS
Debug/Release 빌드를 통과했고, iPhone·iPad UI 흐름과 Mac 실제 화면 조작을 확인했다.
iOS 앱·위젯·Watch 앱·컴플리케이션과 macOS 앱·위젯의 버전 1.0·build 75, 서명,
App Group·CloudKit 권한을 검증했다. iOS는 20:23:54, macOS는 20:25:44 KST에
App Store Connect 업로드가 성공했고 Apple 패키지 처리가 시작됐다. V11 스키마와 백업 V10은
유지하며 실제 TestFlight 설치 가능 상태는 별도 확인 대상이다. 자료는
`.local/releases/build-75/`에 보관한다.

2026-09-08에는 칸반의 작업 입력→진행→완료→기록 흐름, 단일 완료 실행 취소, 진행 시간과
완료 이력 표시 및 지연 import 무결성 보완을 포함한 build 76을 업로드했다. 최종 전체 플랫폼
게이트에서 공통 테스트 Debug 428개·Release 426개와 iOS·macOS·watchOS Debug/Release 빌드를
통과했다. iOS 앱·위젯·Watch 앱·컴플리케이션과 macOS 앱·위젯의 버전 1.0·build 76, 서명,
App Group·CloudKit Production 권한을 검증했다. iOS는 17:15:31, macOS는 17:17:32 KST에
App Store Connect 업로드가 성공했고 Apple 패키지 처리가 시작됐다. V11 스키마와 백업 V10은
유지하며 실제 TestFlight 설치 가능 상태는 별도 확인 대상이다. 자료는
`.local/releases/build-76/`에 보관한다.

2026-09-08에는 build 76을 기준으로 수행한 전반 최적화 결과를 iOS·iPadOS·watchOS와
macOS TestFlight build 77로 업로드했다. iOS 앱·위젯·Watch 앱·컴플리케이션과 macOS
앱·위젯의 버전 `1.0`·build `77`을 archive에서 확인했고, iOS archive entitlement 검증과
macOS App Store 배포 재서명의 CloudKit Production, App Group, key-value store 권한을
확인했다. 두 플랫폼 모두 App Store Connect 업로드가 성공해 Apple 패키지 처리가 시작됐다.
V11 스키마와 백업 V10은 유지하며 추가 schema 배포는 필요하지 않다. 실제 TestFlight 설치
가능 상태와 실기기 데이터 수렴은 별도 인수 대상이며 자료는 `.local/releases/build-77/`에
보관한다.

2026-09-14에는 루틴 목록·항목 검색, 빠른 입력 후보, 여러 날짜 루틴 적용의 반복 계산을
줄인 build 78을 업로드했다. 빌드 78 기준 전체 플랫폼 게이트와 Debug 일반 검사 443개,
Release 일반 검사 442개가 통과했다. iOS 앱·위젯·Watch 앱·컴플리케이션 및 macOS universal
앱·위젯의 버전 `1.0`·build `78`과 서명을 확인했으며, App Store 배포 패키지의 CloudKit
Production·App Group·key-value store 권한도 검증했다. 컴파일 소스 iOS 196개·macOS 188개가
배포 snapshot과 일치한다. macOS 14:07:15, iOS 14:24:36 KST 업로드 성공과 Apple 패키지
처리 시작을 확인했다. V11 스키마와 백업 V10은 유지하며 추가 schema 배포는 하지 않았다.
TestFlight 설치 가능 상태와 실기기 인수는 별도 확인 대상이다. 배포 자료는
`.local/releases/build-78/`, 성능 비교는
`docs/plans/active/OPTIMIZATION_2026_09_14_RESULTS.md`에 보존한다.
