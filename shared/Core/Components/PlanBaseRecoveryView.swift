import SwiftUI

/// Keeps recovery actions reachable before optional technical details on every platform.
public struct PlanBaseRecoveryView: View {
    private let details: String
    private let retry: () -> Void
    #if os(watchOS)
    @State private var showsDetails = false
    #endif

    public init(details: String, retry: @escaping () -> Void) {
        self.details = details
        self.retry = retry
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("저장소를 열 수 없습니다")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("저장된 데이터는 그대로 유지됩니다. 다시 시도해 주세요.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: retry) {
                    Label("다시 시도", systemImage: "arrow.clockwise")
                }
                #if os(watchOS)
                .buttonStyle(.borderedProminent)
                #else
                .buttonStyle(PlanBaseButtonStyle(.primary))
                #endif
                .accessibilityIdentifier("persistence-recovery-retry")

                #if os(watchOS)
                Button(showsDetails ? "오류 상세 접기" : "오류 상세") {
                    showsDetails.toggle()
                }
                .accessibilityValue(showsDetails ? "펼침" : "접힘")
                .accessibilityIdentifier("persistence-recovery-details")
                if showsDetails { detailsText }
                #else
                DisclosureGroup("오류 상세") {
                    detailsText
                }
                .accessibilityIdentifier("persistence-recovery-details")
                #endif
            }
            #if os(watchOS)
            .padding(.horizontal, 8)
            #else
            .padding(24)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            #endif
        }
        #if !os(watchOS)
        .foregroundStyle(AppTheme.primaryText)
        .background(AppTheme.background)
        .tint(AppTheme.accent)
        .preferredColorScheme(AppTheme.current.preferredColorScheme)
        #endif
    }

    private var detailsText: some View {
        Text(details)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            #if !os(watchOS)
            .textSelection(.enabled)
            #endif
            .padding(.top, 8)
    }
}
