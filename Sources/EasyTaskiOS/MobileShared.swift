#if os(iOS)
#if !XCODE_APP_BUNDLE
import EasyTaskCore
#endif
import SwiftUI

#if XCODE_APP_BUNDLE
typealias TodoTask = Task
#else
typealias TodoTask = EasyTaskCore.Task
#endif

enum MobileImageStorage {
    static let appSupportFolder = "EasyTask"
}
#endif
