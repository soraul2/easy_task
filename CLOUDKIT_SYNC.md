# EasyTask CloudKit Development Sync

## 범위

- CloudKit 컨테이너: `iCloud.com.soraul2.easytask`
- 데이터베이스: private database
- 앱 타겟: `com.soraul2.easytask`, `com.soraul2.easytask.macos`
- 스키마: `EasyTaskSchemaV3`
- 운영 스키마 승격: 금지

두 앱은 각각의 로컬 SwiftData 복제본을 유지하고 같은 private CloudKit
컨테이너를 통해 변경을 교환한다. 네트워크가 없어도 로컬 편집은 가능하다.

## 최초 연결

1. Xcode Settings > Accounts에서 Apple Developer 계정을 로그인하거나 다시 인증한다.
2. 두 타겟의 Signing & Capabilities에서 Team `8QCW4WP3SM`과 자동 서명을 확인한다.
3. iCloud 목록에 `iCloud.com.soraul2.easytask`를 생성하거나 선택하고 CloudKit을 활성화한다.
4. Push Notifications를 활성화하고 iOS Background Modes에서 Remote notifications를 확인한다.
5. 두 기기 모두 같은 iCloud 계정으로 로그인하고 iCloud Drive를 활성화한다.

컨테이너는 생성 후 삭제하거나 이름을 바꿀 수 없으므로 다른 식별자를 만들지 않는다.

## 개발 스키마 초기화

프로비저닝이 완료된 뒤 macOS Debug 앱을 다음 인자와 함께 한 번 실행한다.

```text
--initialize-cloudkit-schema
```

초기화 코드는 명시적인 인자가 있는 Debug 빌드에서만 실행된다. 완료 후 CloudKit
Console의 Development 환경에서 모든 V3 record type과 field가 생성됐는지 확인한다.

## 검증 순서

1. 기존 macOS 데이터의 `.easytaskbackup` 백업을 만든다.
2. macOS 앱만 실행해 최초 export가 성공하는지 확인한다.
3. iPhone 앱을 설치하고 최초 import가 끝날 때까지 기다린다.
4. 작업, 이벤트, 템플릿, 회고와 이미지를 양쪽에서 확인한다.
5. 양쪽을 오프라인으로 둔 상태에서 같은 작업과 같은 날짜 회고를 각각 수정한다.
6. 다시 연결해 중복, 누락, 고아 이미지 없이 수렴하는지 확인한다.
7. iPhone 앱을 삭제 후 재설치해 데이터와 이미지가 복구되는지 확인한다.

로그의 `EasyTask CloudKit setup/import/export completed`는 전송 단계 완료를 뜻한다.
성공한 import 뒤에는 무결성 정리가 자동으로 실행된다.

## 운영 전 조건

- 두 기기 오프라인 충돌 시나리오 통과
- 이미지 추가, 삭제, 재설치 통과
- iCloud 로그아웃과 재로그인 통과
- Debug/Release 서명 빌드 통과
- CloudKit Console의 Development 데이터 점검

모든 조건을 통과하기 전에는 Development 스키마를 Production으로 승격하지 않는다.
