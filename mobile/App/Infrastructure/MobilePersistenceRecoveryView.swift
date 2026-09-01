#if os(iOS)
import SwiftUI

struct PersistenceRecoveryView: View {
    let details: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("저장소를 열 수 없습니다")
                    .font(.title2.bold())

                Text("사용자 데이터를 삭제하거나 다른 저장소로 대체하지 않았습니다.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }

            Button(action: retry) {
                Label("다시 시도", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
