#if os(iOS)
import EasyTaskCore
import SwiftUI

typealias TodoTask = EasyTaskCore.Task

enum MobileImageStorage {
    static let appSupportFolder = "EasyTask"
}

enum MobileLayout {
    static let bottomTabClearance: CGFloat = 96
}

struct MobileMissingImagePlaceholder: View {
    var message: String
    var minHeight: CGFloat = 140

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.title2)
            Text(message)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding()
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
#endif
