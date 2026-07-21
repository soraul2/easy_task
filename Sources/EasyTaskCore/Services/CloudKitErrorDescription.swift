import CloudKit
import Foundation

public enum CloudKitErrorDescription {
    public static let quotaExceeded =
        "iCloud 저장 공간이 부족합니다. 이 기기에는 계속 저장되지만 다른 기기와 동기화되지 않습니다. "
        + "공간을 확보한 뒤 앱을 다시 열어 주세요."

    public static func userFacingDescription(for error: any Error) -> String {
        let codes = cloudKitCodes(in: error as NSError)

        if codes.contains(.quotaExceeded) {
            return quotaExceeded
        }
        if codes.contains(.notAuthenticated) {
            return "iCloud에 로그인되어 있지 않습니다. 이 기기에는 계속 저장되지만 다른 기기와 동기화되지 않습니다."
        }
        if codes.contains(.networkUnavailable) || codes.contains(.networkFailure) {
            return "네트워크에 연결할 수 없어 iCloud 동기화를 완료하지 못했습니다. "
                + "이 기기에는 저장되며 연결이 복구되면 다시 시도합니다."
        }
        if codes.contains(.serviceUnavailable)
            || codes.contains(.requestRateLimited)
            || codes.contains(.zoneBusy) {
            return "iCloud가 일시적으로 응답하지 않습니다. 이 기기에는 저장되며 잠시 후 다시 시도합니다."
        }
        if codes.contains(.permissionFailure) {
            return "iCloud 접근 권한을 확인해 주세요. 이 기기에는 계속 저장되지만 다른 기기와 동기화되지 않습니다."
        }
        if codes.contains(.missingEntitlement) || codes.contains(.badContainer) {
            return "iCloud 설정에 문제가 있습니다. 앱을 업데이트하거나 개발자에게 문의해 주세요. "
                + "이 기기에는 계속 저장됩니다."
        }
        if codes.contains(.partialFailure) {
            return "일부 데이터를 iCloud와 동기화하지 못했습니다. 이 기기에는 저장되어 있으며 잠시 후 다시 시도합니다."
        }

        return error.localizedDescription
    }

    private static func cloudKitCodes(in rootError: NSError) -> Set<CKError.Code> {
        var pendingErrors = [rootError]
        var visitedErrors: Set<ObjectIdentifier> = []
        var codes: Set<CKError.Code> = []

        while let error = pendingErrors.popLast() {
            guard visitedErrors.insert(ObjectIdentifier(error)).inserted else { continue }

            if error.domain == CKErrorDomain,
               let code = CKError.Code(rawValue: error.code) {
                codes.insert(code)
            }

            if let partialErrors = error.userInfo[CKPartialErrorsByItemIDKey] as? NSDictionary {
                for value in partialErrors.allValues {
                    if let nestedError = value as? NSError {
                        pendingErrors.append(nestedError)
                    } else if let nestedError = value as? any Error {
                        pendingErrors.append(nestedError as NSError)
                    }
                }
            }

            if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                pendingErrors.append(underlyingError)
            }
        }

        return codes
    }
}
