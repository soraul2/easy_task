#if os(iOS)
import PlanBaseCore
import SwiftUI

struct MobileCloudKitSyncStatusButton: View {
    @Environment(CloudKitSyncMonitor.self) private var monitor
    @State private var isPresented = false

    private var hasRequiredRuntimeEntitlements: Bool {
        PlanBaseContainerFactory.runtimeAppStoreMode.usesCloudKit
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: hasRequiredRuntimeEntitlements
                ? monitor.systemImage
                : "exclamationmark.icloud")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(hasRequiredRuntimeEntitlements
            ? monitor.title
            : "iCloud 권한 확인 필요")
        .accessibilityIdentifier("cloud-sync-status-button")
        .sheet(isPresented: $isPresented) {
            MobileCloudKitSyncStatusSheet(
                monitor: monitor,
                configurationIssue: hasRequiredRuntimeEntitlements
                    ? nil
                    : "이 앱 빌드에 iCloud와 위젯 공유 권한이 없습니다. 새 빌드로 업데이트해 주세요."
            )
        }
    }
}

enum MobileCloudKitSyncUI {
    static let showsWarningBannerKey = "planbase.icloud.shows-warning-banner"
}

struct MobileCloudKitSyncStatusSheet: View {
    let monitor: CloudKitSyncMonitor
    var configurationIssue: String?
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MobileCloudKitSyncUI.showsWarningBannerKey)
    private var showsWarningBanner = true

    var body: some View {
        NavigationStack {
            Form {
                Section("상태") {
                    if configurationIssue == nil {
                        Label(monitor.title, systemImage: monitor.systemImage)
                    } else {
                        Label("iCloud 권한 확인 필요", systemImage: "exclamationmark.icloud")
                    }
                    if let lastSuccessfulSyncAt = monitor.lastSuccessfulSyncAt {
                        LabeledContent(
                            "마지막 성공",
                            value: lastSuccessfulSyncAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    } else {
                        LabeledContent("마지막 성공", value: "확인 전")
                    }
                }
                .listRowBackground(AppTheme.panel)

                if let configurationIssue {
                    Section("빌드 권한") {
                        Text(configurationIssue)
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(AppTheme.panel)
                }

                if let advisoryDescription = monitor.syncAdvisoryDescription {
                    Section("안내") {
                        Text(advisoryDescription)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .listRowBackground(AppTheme.panel)
                }

                if let errorDescription = monitor.lastErrorDescription {
                    Section("확인 필요") {
                        Text(errorDescription)
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(AppTheme.panel)
                }

                Section("화면 표시") {
                    Toggle(isOn: $showsWarningBanner) {
                        Label("상단 경고 배너", systemImage: "rectangle.topthird.inset.filled")
                    }
                    Text("배너를 숨겨도 이 기기 저장과 iCloud 자동 재시도는 계속됩니다.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .listRowBackground(AppTheme.panel)

                Section {
                    Button {
                        Swift.Task { await monitor.refreshAccountStatus() }
                    } label: {
                        Label("계정 상태 다시 확인", systemImage: "arrow.clockwise")
                    }
                }
                .listRowBackground(AppTheme.panel)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .foregroundStyle(AppTheme.primaryText)
            .tint(AppTheme.event)
            .navigationTitle("iCloud 동기화")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.background)
    }
}
#endif
