import SwiftData
import SwiftUI

private struct PlanBaseContentIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    var planBaseContentIsActive: Bool {
        get { self[PlanBaseContentIsActiveKey.self] }
        set { self[PlanBaseContentIsActiveKey.self] = newValue }
    }
}

public extension View {
    /// Retains the view and its editor/scroll state; only data refresh is deferred.
    func refreshVisibleData(
        key: String,
        domains: PersistenceChangeDomains,
        refresh: @escaping @MainActor () throws -> Void
    ) -> some View {
        modifier(VisibleDataRefresh(key: key, domains: domains, refresh: refresh))
    }
}

private struct VisibleDataRefresh: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.planBaseContentIsActive) private var isActive
    @State private var revision: PersistenceViewRevision?
    @State private var lastRequest: Request?
    @State private var refreshError: String?
    @State private var foregroundRevision = 0
    let key: String
    let domains: PersistenceChangeDomains
    let refresh: @MainActor () throws -> Void

    private struct Request: Equatable {
        let key: String
        let revision: Int
        let foreground: Int
    }

    func body(content: Content) -> some View {
        // Do not observe revisions from hidden content. Its observer still records
        // changes, and the latest token is read when it becomes visible again.
        let request: Request? = isActive && scenePhase == .active && revision != nil
            ? Request(key: key, revision: revision!.value, foreground: foregroundRevision) : nil
        content
            .onAppear {
                if revision == nil { revision = PersistenceViewRevision(context: context, domains: domains) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { foregroundRevision &+= 1 }
            }
            .task(id: request) {
                guard let request, request != lastRequest else { return }
                await Swift.Task.yield()
                guard !Swift.Task.isCancelled else { return }
                do {
                    try refresh()
                    lastRequest = request
                } catch {
                    refreshError = error.localizedDescription
                }
            }
            .alert("내용을 불러오지 못했습니다", isPresented: Binding(
                get: { refreshError != nil }, set: { if !$0 { refreshError = nil } }
            )) {
                Button("다시 시도") { refreshError = nil; foregroundRevision &+= 1 }
                Button("닫기", role: .cancel) {}
            } message: { Text(refreshError ?? "") }
    }
}
