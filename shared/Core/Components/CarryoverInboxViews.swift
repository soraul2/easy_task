import Combine
import SwiftData
import SwiftUI

public struct CarryoverCountBadge: View {
    public var session: CarryoverInboxSession?

    public init(session: CarryoverInboxSession?) { self.session = session }

    public var body: some View {
        HStack(spacing: 4) {
            if let session, session.count > 0 {
                Text(session.count > 99 ? "99+" : "\(session.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.input, in: Capsule())
                if session.newCount > 0 {
                    Circle().fill(AppTheme.accent).frame(width: 6, height: 6)
                }
            }
            if session?.errorMessage != nil {
                Image(systemName: "exclamationmark.circle").font(.caption)
            }
        }
        .foregroundStyle(AppTheme.primaryText)
        .accessibilityHidden(true)
    }
}

public struct CarryoverArrivalBanner: View {
    public var session: CarryoverInboxSession
    public var onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(session: CarryoverInboxSession, onOpen: @escaping () -> Void) {
        self.session = session
        self.onOpen = onOpen
    }

    public var body: some View {
        if !session.bannerKeys.isEmpty {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) { message; actions }
                } else {
                    HStack(spacing: 12) { message; Spacer(minLength: 0); actions }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1) }
            .accessibilityIdentifier("carryover-arrival-banner")
            .onAppear { session.didDisplayBanner() }
            .onChange(of: session.bannerKeys) { _, _ in session.didDisplayBanner() }
        }
    }

    private var message: some View {
        Text("이월함에 새 작업 \(session.bannerKeys.count)개가 있어요")
            .font(.callout)
            .foregroundStyle(AppTheme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("확인", action: onOpen)
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(minWidth: PlanBaseControlMetrics.minimumTargetSize,
                       minHeight: PlanBaseControlMetrics.minimumTargetSize)
            Button { session.dismissBanner() } label: {
                Image(systemName: "xmark")
                    .font(.callout)
                    .frame(minWidth: PlanBaseControlMetrics.minimumTargetSize,
                           minHeight: PlanBaseControlMetrics.minimumTargetSize)
            }
            .foregroundStyle(AppTheme.secondaryText)
            .accessibilityLabel("이월 안내 닫기")
        }
        .buttonStyle(.plain)
    }
}

public struct CarryoverInboxSummary: View {
    public var session: CarryoverInboxSession

    public init(session: CarryoverInboxSession) { self.session = session }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.hasLoaded {
                Text("전체 \(session.count)개 · 새 작업 \(session.displayedNewCount)개")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityIdentifier("carryover-summary")
            }
            if let message = session.errorMessage {
                Text(message).font(.callout).foregroundStyle(AppTheme.secondaryText)
                Button("다시 시도") { session.refresh() }
                    .frame(minHeight: PlanBaseControlMetrics.minimumTargetSize)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CarryoverInboxConnection: ViewModifier {
    @Binding var session: CarryoverInboxSession?
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.planBaseContentIsActive) private var isActive
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        content
            .refreshVisibleData(key: "carryover", domains: .tasks) {
                if session == nil { session = CarryoverInboxSession(context: context) }
                session?.refresh()
            }
            .onReceive(clock) { _ in
                if isActive, scenePhase == .active, session?.todayKey != DayKey.today { session?.refresh() }
            }
    }
}

public extension View {
    func carryoverInboxSession(_ session: Binding<CarryoverInboxSession?>) -> some View {
        modifier(CarryoverInboxConnection(session: session))
    }
}
