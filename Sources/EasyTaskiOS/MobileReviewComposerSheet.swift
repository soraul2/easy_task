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

    private var dayKey: String { DayKey.key(for: selectedDate) }
    private var selectedReview: DailyReview? { reviews.first { $0.dayKey == dayKey } }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !imageFileNames.isEmpty
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
                    if let message {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.done)
                            .font(.caption.weight(.bold))
                    }
                }
                .padding(16)
            }
            .navigationTitle("오늘 회고")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        save()
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
    }

    private func save() {
        let review: DailyReview
        if let selectedReview {
            review = selectedReview
        } else {
            review = DailyReview(dayKey: dayKey, content: "")
            modelContext.insert(review)
        }
        review.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        review.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        review.imageFileNames = imageFileNames
        review.updatedAt = Date()
        message = "회고가 저장됐어요"
    }

    private func importImages() {
        let items = selectedItems
        selectedItems = []
        guard !items.isEmpty else { return }

        Swift.Task {
            var imported: [String] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let fileName = try? DiaryImageFileStore.writeImageData(
                    data,
                    preferredExtension: "jpg",
                    appSupportFolder: MobileImageStorage.appSupportFolder
                   ) {
                    imported.append(fileName)
                }
            }
            await MainActor.run {
                imageFileNames.append(contentsOf: imported)
                selectedImageIndex = max(imageFileNames.count - imported.count, 0)
                save()
                message = imported.count == 1 ? "이미지 추가됨" : "이미지 \(imported.count)개 추가됨"
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
    }
}

private struct ReviewComposerHeader: View {
    @Binding var title: String
    var selectedDate: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed")
                .foregroundStyle(AppTheme.event)
            TextField("하루 회고", text: $title)
                .font(.headline)
            Text("› \(DayKey.display(selectedDate))")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            .frame(height: 320)
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
            }
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .padding(8)
                    .background(.black.opacity(0.5), in: Circle())
                    .foregroundStyle(.white)
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
#endif
