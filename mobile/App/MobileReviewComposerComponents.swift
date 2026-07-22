#if os(iOS)
import PlanBaseCore
import Foundation
import SwiftUI
import UIKit

enum MobileReviewComposerField: Hashable {
    case title
    case content
}

struct ReviewComposerHeader: View {
    @Binding var title: String
    var selectedDate: Date
    @FocusState.Binding var focusedField: MobileReviewComposerField?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(DayKey.display(selectedDate), systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            VStack(alignment: .leading, spacing: 7) {
                Text("제목 (선택)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)

                TextField("하루 회고", text: $title)
                    .font(.headline)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .content }
                    .accessibilityIdentifier("review-title-field")
            }
            .padding(14)
            .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
        }
    }
}

struct ReviewComposerTaskSummary: View {
    var summary: DailyReviewTaskSummary
    var selectedDate: Date
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Label(sectionTitle, systemImage: "checklist")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("작업 요약")
            .accessibilityValue(isExpanded ? "펼쳐짐" : "접힘")

            HStack(spacing: 8) {
                ReviewSummaryCount(
                    title: "완료",
                    count: summary.completed.count,
                    color: AppTheme.done
                )
                ReviewSummaryCount(
                    title: "진행 중",
                    count: summary.inProgress.count,
                    color: AppTheme.doing
                )
                ReviewSummaryCount(
                    title: "할 일",
                    count: summary.pending.count,
                    color: AppTheme.todo
                )
            }

            if isExpanded {
                if summary.isEmpty {
                    Text("이 날짜에 등록된 작업이 없습니다")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ReviewSummaryGroup(
                            title: "완료",
                            systemImage: "checkmark.circle.fill",
                            color: AppTheme.done,
                            items: summary.completed
                        )
                        ReviewSummaryGroup(
                            title: "진행 중",
                            systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                            color: AppTheme.doing,
                            items: summary.inProgress
                        )
                        ReviewSummaryGroup(
                            title: "할 일",
                            systemImage: "circle",
                            color: AppTheme.todo,
                            items: summary.pending
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .accessibilityIdentifier("review-task-summary")
    }

    private var sectionTitle: String {
        if DayKey.isToday(selectedDate) {
            return "오늘의 작업"
        }
        let components = DayKey.calendar.dateComponents([.month, .day], from: selectedDate)
        return "\(components.month ?? 0)월 \(components.day ?? 0)일 작업"
    }
}

private struct ReviewSummaryCount: View {
    var title: String
    var count: Int
    var color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(title) \(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 30)
        .background(color.opacity(0.13), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

private struct ReviewSummaryGroup: View {
    var title: String
    var systemImage: String
    var color: Color
    var items: [DailyReviewTaskSummaryItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)

                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(color.opacity(0.75))
                            .frame(width: 5, height: 5)

                        Text(item.title)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if item.isCarryover {
                            Text(carryoverLabel(item.plannedDayKey))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
            }
        }
    }

    private func carryoverLabel(_ dayKey: String) -> String {
        guard let date = DayKey.date(from: dayKey) else { return "이월" }
        let components = DayKey.calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)월 \(components.day ?? 0)일에서 이월"
    }
}

struct ReviewComposerEditor: View {
    @Binding var content: String
    @FocusState.Binding var focusedField: MobileReviewComposerField?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("자유 기록")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            TextField(
                "오늘 하루는 어땠나요?",
                text: $content,
                axis: .vertical
            )
            .font(.body)
            .textFieldStyle(.plain)
            .lineLimit(6...18)
            .focused($focusedField, equals: .content)
            .accessibilityIdentifier("review-content-field")
        }
        .padding(14)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

struct ReviewComposerImages: View {
    var attachmentDrafts: [MobileReviewAttachmentDraft]
    var legacyImageFileNames: [String]
    @Binding var selectedImageIndex: Int
    var allowsCanonicalDeletion: Bool
    var onDeleteCanonical: (Int) -> Void
    var onDeleteLegacy: ([Int]) -> Void
    @State private var legacyResolution = MobileLegacyImageResolution()
    @State private var imageAspectRatios: [String: CGFloat] = [:]

    var body: some View {
        let items = mixedImageItems
        let safeIndex = items.indices.contains(selectedImageIndex) ? selectedImageIndex : 0
        let selectedAspectRatio = items.indices.contains(safeIndex)
            ? imageAspectRatios[items[safeIndex].id] ?? 4.0 / 3.0
            : 4.0 / 3.0

        VStack(alignment: .leading, spacing: 8) {
            if isResolvingLegacyImages {
                MobileImageLoadingPlaceholder(minHeight: 160)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if !items.isEmpty {
                ZStack(alignment: .bottomTrailing) {
                    TabView(selection: $selectedImageIndex) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            MobileReviewImagePreview(
                                request: item.thumbnailRequest,
                                placeholderMessage: item.isLegacy
                                    ? "이전 이미지를 불러올 수 없음"
                                    : "이미지를 불러올 수 없음",
                                accessibilityLabel: "회고 이미지 \(index + 1)",
                                onAspectRatioChange: { aspectRatio in
                                    let ratio = min(max(aspectRatio, 0.82), 2.0)
                                    if imageAspectRatios[item.id] != ratio {
                                        imageAspectRatios[item.id] = ratio
                                    }
                                },
                                onDelete: deletionAction(for: item)
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .aspectRatio(selectedAspectRatio, contentMode: .fit)
                    .animation(.easeInOut(duration: 0.2), value: selectedAspectRatio)

                    if items.count > 1 {
                        Text("\(safeIndex + 1)/\(items.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.58), in: Capsule())
                            .padding(9)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
                .onChange(of: items.count) { _, count in
                    if selectedImageIndex >= count {
                        selectedImageIndex = 0
                    }
                }
            }

            if !allowsCanonicalDeletion, !legacyImageFileNames.isEmpty {
                Label("이전 이미지를 정리하면 새 이미지 추가와 삭제를 사용할 수 있어요.", systemImage: "lock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .task(id: legacyImageFileNames) {
            let resolution = await MobileLegacyImageResolver.resolve(
                fileNames: legacyImageFileNames
            )
            guard !Swift.Task<Never, Never>.isCancelled else { return }
            legacyResolution = resolution
        }
    }

    private var mixedImageItems: [ReviewComposerImageItem] {
        var items: [ReviewComposerImageItem] = []

        for (index, attachmentDraft) in attachmentDrafts.enumerated() {
            let draft = attachmentDraft.draft
            items.append(ReviewComposerImageItem(
                id: "canonical-\(attachmentDraft.id.uuidString)",
                data: draft.data,
                canonicalIndex: index,
                legacyIndexes: [],
                normalizedFileName: normalizedFileName(draft.originalFileName),
                sha256: attachmentDraft.attachmentHash,
                isLegacy: false
            ))
        }

        for legacyImage in resolvedLegacyImages {
            let normalizedFileName = legacyImage.normalizedFileName
            let hash = legacyImage.attachmentHash
            if let existingIndex = items.firstIndex(where: {
                $0.normalizedFileName == normalizedFileName ||
                    (hash != nil && $0.sha256 == hash)
            }) {
                items[existingIndex].legacyIndexes.append(legacyImage.sourceIndex)
                continue
            }

            items.append(ReviewComposerImageItem(
                id: "legacy-\(normalizedFileName)-\(legacyImage.sourceIndex)",
                data: legacyImage.data,
                canonicalIndex: nil,
                legacyIndexes: [legacyImage.sourceIndex],
                normalizedFileName: normalizedFileName,
                sha256: hash,
                isLegacy: true
            ))
        }
        return items
    }

    private var resolvedLegacyImages: [MobileResolvedLegacyImage] {
        guard legacyResolution.fileNames == legacyImageFileNames else { return [] }
        return legacyResolution.images
    }

    private var isResolvingLegacyImages: Bool {
        !legacyImageFileNames.isEmpty && legacyResolution.fileNames != legacyImageFileNames
    }

    private func deletionAction(for item: ReviewComposerImageItem) -> (() -> Void)? {
        if !item.legacyIndexes.isEmpty {
            return { onDeleteLegacy(item.legacyIndexes) }
        }
        guard allowsCanonicalDeletion, let index = item.canonicalIndex else { return nil }
        return { onDeleteCanonical(index) }
    }

    private func normalizedFileName(_ fileName: String?) -> String? {
        guard let value = fileName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }
}

struct MobileReviewDismissGuard: UIViewControllerRepresentable {
    var isBlocked: Bool
    var onAttempt: () -> Void

    func makeUIViewController(context: Context) -> DismissGuardViewController {
        let controller = DismissGuardViewController()
        controller.isBlocked = isBlocked
        controller.onAttempt = onAttempt
        return controller
    }

    func updateUIViewController(_ controller: DismissGuardViewController, context: Context) {
        controller.isBlocked = isBlocked
        controller.onAttempt = onAttempt
        controller.installDelegate()
    }
}

final class DismissGuardViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    var isBlocked = false
    var onAttempt: (() -> Void)?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installDelegate()
    }

    func installDelegate() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.parent?.presentationController?.delegate = self
        }
    }

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        !isBlocked
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        onAttempt?()
    }
}

private struct ReviewComposerImageItem: Identifiable {
    var id: String
    var data: Data?
    var canonicalIndex: Int?
    var legacyIndexes: [Int]
    var normalizedFileName: String?
    var sha256: String?
    var isLegacy: Bool

    var thumbnailRequest: MobileImageThumbnailRequest? {
        guard let data else { return nil }
        return MobileImageThumbnailRequest(
            data: data,
            attachmentHash: sha256,
            dataIdentity: id
        )
    }
}

private struct MobileReviewImagePreview: View {
    var request: MobileImageThumbnailRequest?
    var placeholderMessage: String
    var accessibilityLabel: String
    var onAspectRatioChange: ((CGFloat) -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MobileAsyncThumbnailImage(
                request: request,
                placeholderMessage: placeholderMessage,
                minHeight: 160,
                accessibilityLabel: accessibilityLabel,
                onAspectRatioChange: onAspectRatioChange
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.52), in: Circle())
                        .foregroundStyle(.white)
                }
                .padding(10)
                .accessibilityLabel("이미지 삭제")
            }
        }
    }
}
#endif
