import PlanBaseCore
import SwiftUI

struct CloudKitSyncStatusButton: View {
    let monitor: CloudKitSyncMonitor
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: monitor.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 54, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(monitor.lastErrorDescription == nil ? AppTheme.primaryText : Color.red)
        .padding(8)
        .background(AppTheme.floatingBar, in: Capsule())
        .overlay {
            Capsule().stroke(AppTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 8)
        .help(monitor.title)
        .accessibilityLabel(monitor.title)
        .sheet(isPresented: $isPresented) {
            CloudKitSyncStatusSheet(monitor: monitor)
        }
    }
}

private struct CloudKitSyncStatusSheet: View {
    let monitor: CloudKitSyncMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("iCloud 동기화")
                    .font(.title2.weight(.bold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("닫기")
            }

            Label(monitor.title, systemImage: monitor.systemImage)
                .font(.headline)

            LabeledContent("계정", value: monitor.accountAvailability.title)
            if let lastSuccessfulSyncAt = monitor.lastSuccessfulSyncAt {
                LabeledContent(
                    "마지막 성공",
                    value: lastSuccessfulSyncAt.formatted(date: .abbreviated, time: .shortened)
                )
            } else {
                LabeledContent("마지막 성공", value: "확인 전")
            }

            if let advisoryDescription = monitor.syncAdvisoryDescription {
                Text(advisoryDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
            }

            if let errorDescription = monitor.lastErrorDescription {
                Text(errorDescription)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button {
                    Swift.Task { await monitor.refreshAccountStatus() }
                } label: {
                    Label("계정 상태 다시 확인", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(AppTheme.panel)
        .foregroundStyle(AppTheme.primaryText)
    }
}
