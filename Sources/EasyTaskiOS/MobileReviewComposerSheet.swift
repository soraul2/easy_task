#if os(iOS)
#if !XCODE_APP_BUNDLE
import EasyTaskCore
#endif
import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct MobileReviewComposerSheet: View {
    var selectedDate: Date
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var reviews: [DailyReview]
    @State private var title = ""
    @State private var content = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var imageFileNames: [String] = []
    @State private var selectedImageIndex = 0
    @State private var message: String?
    @State private var messageIsError = false

    private var dayKey: String { DayKey.key(for: selectedDate) }
    private var selectedReview: DailyReview? { reviews.first { $0.dayKey == dayKey } }

    private var canSave: Bool {
        DailyReviewRules.hasContent(
            title: title,
            content: content,
            imageFileNames: imageFileNames
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ReviewComposerHeader(title: $title, selectedDate: selectedDate)
                    ReviewComposerEditor(content: $content)
                    ReviewComposerImages(
                        imageFileNames: imageFileNames,
                        selectedImageIndex: $selectedImageIndex,
                        onDelete: removeImage
                    )
                    PhotosPicker(selection: $selectedItems, maxSelectionCount: 10, matching: .images) {
                        Label("이미지 추가", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                    if let message {
                        Label(
                            message,
                            systemImage: messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                        )
                            .foregroundStyle(messageIsError ? .red : AppTheme.done)
                            .font(.caption.weight(.bold))
                    }
                }
                .padding(16)
            }
            .navigationTitle("회고 작성")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        save()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
            .onChange(of: selectedItems) {
                importImages()
            }
        }
    }

    private func load() {
        title = selectedReview?.title ?? ""
        content = selectedReview?.content ?? ""
        imageFileNames = selectedReview?.imageFileNames ?? []
        selectedImageIndex = 0
        message = nil
        messageIsError = false
    }

    private func save() {
        guard DailyReviewService.save(
            review: selectedReview,
            dayKey: dayKey,
            title: title,
            content: content,
            imageFileNames: imageFileNames,
            in: modelContext
        ) != nil else {
            return
        }
        message = "회고가 저장됐어요"
        messageIsError = false
    }

    private func importImages() {
        let items = selectedItems
        selectedItems = []
        guard !items.isEmpty else { return }

        Swift.Task {
            var imported: [String] = []
            var failedCount = 0
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let fileName = try? DiaryImageFileStore.writeImageData(
                    data,
                    preferredExtension: "jpg",
                    appSupportFolder: MobileImageStorage.appSupportFolder
                   ) {
                    imported.append(fileName)
                } else {
                    failedCount += 1
                }
            }
            await MainActor.run {
                guard !imported.isEmpty else {
                    message = "이미지를 가져오지 못했어요"
                    messageIsError = true
                    return
                }
                imageFileNames.append(contentsOf: imported)
                selectedImageIndex = max(imageFileNames.count - imported.count, 0)
                save()
                if failedCount > 0 {
                    message = "이미지 \(imported.count)개 추가됨, \(failedCount)개 실패"
                    messageIsError = true
                } else {
                    message = imported.count == 1 ? "이미지 추가됨" : "이미지 \(imported.count)개 추가됨"
                    messageIsError = false
                }
            }
        }
    }

    private func removeImage(at index: Int) {
        guard imageFileNames.indices.contains(index) else { return }
        let fileName = imageFileNames.remove(at: index)
        DiaryImageFileStore.removeImage(
            fileName: fileName,
            appSupportFolder: MobileImageStorage.appSupportFolder
        )
        selectedImageIndex = min(selectedImageIndex, max(imageFileNames.count - 1, 0))
        save()
        message = "이미지 삭제됨"
        messageIsError = false
    }
}

private struct ReviewComposerHeader: View {
    @Binding var title: String
    var selectedDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(DayKey.display(selectedDate), systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("하루 회고", text: $title)
                .font(.headline)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct ReviewComposerEditor: View {
    @Binding var content: String

    var body: some View {
        TextEditor(text: $content)
            .frame(minHeight: 120)
            .padding(8)
            .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topLeading) {
                if content.isEmpty {
                    Text("오늘 하루는 어땠나요?")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct ReviewComposerImages: View {
    var imageFileNames: [String]
    @Binding var selectedImageIndex: Int
    var onDelete: (Int) -> Void

    var body: some View {
        if !imageFileNames.isEmpty {
            TabView(selection: $selectedImageIndex) {
                ForEach(Array(imageFileNames.enumerated()), id: \.offset) { index, fileName in
                    MobileReviewImagePreview(fileName: fileName) {
                        onDelete(index)
                    }
                    .tag(index)
                }
            }
            .frame(height: 260)
            .tabViewStyle(.page)
        }
    }
}

private struct MobileReviewImagePreview: View {
    var fileName: String
    var onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = UIImage(contentsOfFile: DiaryImageFileStore.imageURL(
                for: fileName,
                appSupportFolder: MobileImageStorage.appSupportFolder
            ).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.input)
            } else {
                MobileMissingImagePlaceholder(message: "이미지를 불러올 수 없음")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .padding(8)
                    .background(.black.opacity(0.5), in: Circle())
                    .foregroundStyle(.white)
            }
            .padding(10)
            .accessibilityLabel("이미지 삭제")
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
#endif
