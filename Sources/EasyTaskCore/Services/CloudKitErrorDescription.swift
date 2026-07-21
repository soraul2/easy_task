import CloudKit
import CoreData
import Foundation

public enum CloudKitErrorDescription {
    public static let systemDeferred =
        "iCloud 동기화가 시스템 상태에 따라 잠시 미뤄졌습니다. "
        + "이 기기에는 저장되며 자동으로 다시 시도합니다."

    public static let quotaExceeded =
        "iCloud 저장 공간이 부족합니다. 이 기기에는 계속 저장되지만 다른 기기와 동기화되지 않습니다. "
        + "공간을 확보한 뒤 앱을 다시 열어 주세요."

    public static func userFacingDescription(for error: any Error) -> String {
        let errors = flattenedErrors(from: error as NSError)
        if errors.contains(where: isSystemDeferredError) {
            return systemDeferred
        }

        let codes = cloudKitCodes(in: errors)

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

    public static func isSystemDeferred(_ error: any Error) -> Bool {
        flattenedErrors(from: error as NSError).contains(where: isSystemDeferredError)
    }

    public static func diagnosticDescription(for error: any Error) -> String {
        flattenedErrors(from: error as NSError).map { currentError in
            var components = ["\(currentError.domain)(\(currentError.code))"]
            if let reason = currentError.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
               !reason.isEmpty {
                components.append("reason=\(reason)")
            }
            if let suggestion = currentError.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String,
               !suggestion.isEmpty {
                components.append("recovery=\(suggestion)")
            }
            return components.joined(separator: " ")
        }.joined(separator: " <- ")
    }

    // Core Data uses this private code when the system defers a CloudKit mirroring request.
    private static let systemDeferredCocoaErrorCode = 134_419

    private static func isSystemDeferredError(_ error: NSError) -> Bool {
        error.domain == NSCocoaErrorDomain && error.code == systemDeferredCocoaErrorCode
    }

    private static func cloudKitCodes(in errors: [NSError]) -> Set<CKError.Code> {
        Set(errors.compactMap { error in
            guard error.domain == CKErrorDomain else { return nil }
            return CKError.Code(rawValue: error.code)
        })
    }

    private static func flattenedErrors(from rootError: NSError) -> [NSError] {
        var pendingErrors = [rootError]
        var visitedErrors: Set<ObjectIdentifier> = []
        var errors: [NSError] = []

        while let error = pendingErrors.popLast() {
            guard visitedErrors.insert(ObjectIdentifier(error)).inserted else { continue }
            errors.append(error)

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

            if let detailedErrors = error.userInfo[NSDetailedErrorsKey] as? [NSError] {
                pendingErrors.append(contentsOf: detailedErrors)
            }
        }

        return errors
    }
}
