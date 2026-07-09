import AppKit
import SwiftData
import SwiftUI
import EasyTaskCore

struct DiaryView: View {
    private let postMaxWidth: CGFloat = 620
    private let showsHeader: Bool
    private let threadColumnWidth: CGFloat = 40

    @Environment(\.modelContext) private var modelContext
    @Query private var reviews: [DailyReview]
    @Query private var diaryBlocks: [DiaryBlock]

    @State private var selectedDate: Date
    @State private var reviewTitle = ""
    @State private var content = ""
    @State private var selectedImageIndex = 0
    @State private var message: String?

    init(initialDate: Date = DayKey.startOfDay(for: Date()), showsHeader: Bool = true) {
        self.showsHeader = showsHeader
        _selectedDate = State(initialValue: DayKey.startOfDay(for: initialDate))
    }

    private var selectedDayKey: String {
        DayKey.key(for: selectedDate)
    }

    private var selectedReview: DailyReview? {
        reviews
            .filter { $0.supersededAt == nil && $0.dayKey == selectedDayKey }
            .max {
                if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt < $1.updatedAt
                }
                return $0.instanceID.uuidString < $1.instanceID.uuidString
            }
    }

    private var imageFileNames: [String] {
        selectedReview?.imageFileNames ?? []
    }

    private var canSave: Bool {
        DailyReviewRules.hasContent(
            title: reviewTitle,
            content: content,
            imageFileNames: imageFileNames
        )
    }

    private var contentMaxWidth: CGFloat {
        showsHeader ? postMaxWidth : .infinity
    }

    private var contentHorizontalPadding: CGFloat {
        showsHeader ? 28 : 12
    }

    private var contentTopPadding: CGFloat {
        showsHeader ? 0 : 12
    }

    private var contentBottomPadding: CGFloat {
        showsHeader ? 112 : 12
    }

    private var captionMinHeight: CGFloat {
        showsHeader ? 96 : (imageFileNames.isEmpty ? 44 : 26)
    }

    private var captionMaxHeight: CGFloat {
        showsHeader ? .infinity : (imageFileNames.isEmpty ? 56 : 34)
    }

    private var imagePreviewHeight: CGFloat {
        guard !showsHeader else { return 340 }
        let captionGrowth = max(captionEditorHeight - 34, 0)
        return max(260, 348 - captionGrowth)
    }

    private var selectedDayNumber: String {
        "\(Calendar.current.component(.day, from: selectedDate))"
    }

    private var reviewTitleFieldWidth: CGFloat {
        let displayTitle = reviewTitle.isEmpty ? "하루 회고" : reviewTitle
        let font = NSFont.systemFont(ofSize: 14, weight: .bold)
        let measuredWidth = (displayTitle as NSString).size(withAttributes: [.font: font]).width
        return min(max(ceil(measuredWidth) + 8, 58), 220)
    }

    private var captionEditorHeight: CGFloat {
        guard !showsHeader else { return captionMinHeight }

        let lineHeight: CGFloat = 20
        let verticalPadding: CGFloat = 12
        let estimatedHeight = CGFloat(estimatedCaptionLineCount) * lineHeight + verticalPadding
        let minHeight: CGFloat = imageFileNames.isEmpty ? 44 : 34
        let maxHeight: CGFloat = imageFileNames.isEmpty ? 110 : 140
        return min(max(ceil(estimatedHeight), minHeight), maxHeight)
    }

    private var estimatedCaptionLineCount: Int {
        guard !content.isEmpty else { return 1 }

        let charactersPerLine = imageFileNames.isEmpty ? 38 : 34
        return content
            .components(separatedBy: .newlines)
            .reduce(0) { total, line in
                total + max(1, Int(ceil(Double(line.count) / Double(charactersPerLine))))
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
            }

            if showsHeader {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        postComposer

                        if let message {
                            Text(message)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .frame(maxWidth: contentMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, contentHorizontalPadding)
                    .padding(.top, contentTopPadding)
                    .padding(.bottom, contentBottomPadding)
                }
            } else {
                postComposer
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 26)
                    .padding(.top, 18)
                    .padding(.bottom, 14)
            }
        }
        .background(AppTheme.panel)
        .onAppear(perform: loadSelectedReview)
        .onChange(of: selectedDayKey) {
            loadSelectedReview()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                selectedDate = DayKey.addingDays(-1, to: selectedDate)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)

            Text(DayKey.display(selectedDate))
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)
                .frame(minWidth: 210, alignment: .leading)

            Button("오늘") {
                selectedDate = DayKey.startOfDay(for: Date())
            }
            .buttonStyle(.bordered)

            Button {
                selectedDate = DayKey.addingDays(1, to: selectedDate)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                addImages()
            } label: {
                Label("이미지", systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .calendarToolbarButtonBackground()
            }
            .buttonStyle(.plain)

            Button {
                save()
            } label: {
                Label("저장", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .calendarToolbarButtonBackground(isPrimary: true)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
    }

    private var postComposer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                timelineColumn

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            TextField("하루 회고", text: $reviewTitle)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppTheme.primaryText)
                                .frame(width: reviewTitleFieldWidth, alignment: .leading)
                                .help("회고 제목")

                            Text("›")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.secondaryText)

                            Text(DayKey.display(selectedDate))
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.secondaryText)
                        }

                    }

                    if showsHeader {
                        HStack(spacing: 5) {
                            Text("회고")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppTheme.primaryText)

                            Text("›")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.secondaryText)

                            Text(DayKey.display(selectedDate))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }

                    captionEditor

                    if !imageFileNames.isEmpty {
                        inlineImagePreview
                    }

                    composerToolbar

                    if !showsHeader {
                        Text("이 날짜에 기록 추가")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.78))
                            .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, showsHeader ? 16 : 0)
            .padding(.top, showsHeader ? 14 : 0)
            .padding(.bottom, showsHeader ? 12 : 10)

            if showsHeader || !imageFileNames.isEmpty {
                Spacer(minLength: 0)
            }

            Divider()
                .overlay(AppTheme.border)

            HStack(spacing: 12) {
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.done)
                        .transition(.opacity)
                } else if showsHeader {
                    Label("회고 옵션", systemImage: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                Button {
                    save()
                } label: {
                    Text(showsHeader ? "작성하기" : "저장")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(canSave ? AppTheme.primaryText : AppTheme.secondaryText)
                        .padding(.horizontal, 18)
                        .frame(height: 36)
                        .background(canSave ? AppTheme.selectedTab : AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .help("회고 저장")
            }
            .padding(.horizontal, showsHeader ? 16 : 0)
            .padding(.top, 14)
            .animation(.snappy(duration: 0.18), value: message)
        }
    }

    private var timelineColumn: some View {
        VStack(spacing: 8) {
            reviewTimelineIcon

            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 2)
                .frame(height: showsHeader ? 120 : (imageFileNames.isEmpty ? 74 : 430))

            if !showsHeader {
                reviewTimelineIcon(size: 18, fontSize: 10)
            }
        }
        .frame(width: threadColumnWidth)
    }

    private var reviewTimelineIcon: some View {
        reviewTimelineIcon(size: 36, fontSize: 18)
    }

    private func reviewTimelineIcon(size: CGFloat, fontSize: CGFloat) -> some View {
        Image(systemName: "book.closed")
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(AppTheme.event)
            .frame(width: size, height: size)
    }

    private var composerToolbar: some View {
        HStack(spacing: 8) {
            Button {
                addImages()
            } label: {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.secondaryText)
            .help("이미지 추가")

            if showsHeader {
                composerIcon("face.smiling")
                composerIcon("line.3.horizontal.decrease")
                composerIcon("list.bullet.rectangle")
                composerIcon("mappin")
                composerIcon("music.note")
            }

            if !imageFileNames.isEmpty {
                Text("\(selectedImageIndex + 1)/\(imageFileNames.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private func composerIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(AppTheme.secondaryText.opacity(0.7))
            .frame(width: 30, height: 30)
    }

    private var inlineImagePreview: some View {
        ZStack {
            if let fileName = imageFileNames[safe: selectedImageIndex] {
                DiaryImageView(fileName: fileName)
            }

            VStack {
                HStack {
                    Spacer()

                    Button(role: .destructive) {
                        removeSelectedImage()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.48), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .help("현재 이미지 삭제")
                }

                Spacer()
            }
            .padding(10)

            HStack {
                if selectedImageIndex > 0 {
                    carouselButton(systemName: "chevron.left") {
                        moveImageSelection(-1)
                    }
                }

                Spacer()

                if selectedImageIndex < imageFileNames.count - 1 {
                    carouselButton(systemName: "chevron.right") {
                        moveImageSelection(1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity, alignment: .center)

            if imageFileNames.count > 1 {
                VStack {
                    Spacer()
                    carouselDots
                }
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: imagePreviewHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var carouselDots: some View {
        HStack(spacing: 6) {
            ForEach(imageFileNames.indices, id: \.self) { index in
                Circle()
                    .fill(index == selectedImageIndex ? AppTheme.primaryText : AppTheme.secondaryText.opacity(0.45))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.floatingBar.opacity(0.86), in: Capsule())
    }

    private var captionEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $content)
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.primaryText)
                .scrollContentBackground(.hidden)
                .frame(
                    minHeight: showsHeader ? captionMinHeight : captionEditorHeight,
                    maxHeight: showsHeader ? captionMaxHeight : captionEditorHeight
                )
                .padding(0)

            if content.isEmpty {
                Text(showsHeader ? "새로운 기록이 있나요?" : "오늘 하루는 어땠나요?")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.secondaryText)
                    .allowsHitTesting(false)
            }
        }
    }

    private func carouselButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.44), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func moveImageSelection(_ offset: Int) {
        guard !imageFileNames.isEmpty else { return }
        let nextIndex = selectedImageIndex + offset
        selectedImageIndex = min(max(nextIndex, 0), imageFileNames.count - 1)
    }

    private func loadSelectedReview() {
        if let review = selectedReview {
            DailyReviewService.migrateBlockSummaryIfNeeded(
                for: review,
                blocks: diaryBlocks
            )
        }

        let review = selectedReview
        reviewTitle = review?.title ?? ""
        content = review?.content ?? ""
        selectedImageIndex = 0
        message = nil
    }

    @discardableResult
    private func save(forceCreate: Bool = false) -> DailyReview? {
        let review = DailyReviewService.save(
            review: selectedReview,
            dayKey: selectedDayKey,
            title: reviewTitle,
            content: content,
            imageFileNames: imageFileNames,
            in: modelContext,
            forceCreate: forceCreate
        )
        guard let review else { return nil }
        message = "회고가 저장됐어요"
        return review
    }

    private func addImages() {
        do {
            let fileNames = try DiaryImageStore.chooseAndCopyImages()
            guard !fileNames.isEmpty else { return }
            let nextImageFileNames = imageFileNames + fileNames
            guard let review = DailyReviewService.save(
                review: selectedReview,
                dayKey: selectedDayKey,
                title: reviewTitle,
                content: content,
                imageFileNames: nextImageFileNames,
                in: modelContext,
                forceCreate: true
            ) else { return }

            selectedImageIndex = max(review.imageFileNames.count - fileNames.count, 0)
            message = fileNames.count == 1 ? "이미지 추가됨" : "이미지 \(fileNames.count)개 추가됨"
        } catch {
            message = "이미지 추가 실패: \(error.localizedDescription)"
        }
    }

    private func removeSelectedImage() {
        guard let review = selectedReview,
              review.imageFileNames.indices.contains(selectedImageIndex) else { return }

        let fileName = review.imageFileNames.remove(at: selectedImageIndex)
        let nextImageFileNames = review.imageFileNames
        DiaryImageStore.removeImage(fileName: fileName)
        selectedImageIndex = min(selectedImageIndex, max(review.imageFileNames.count - 1, 0))
        DailyReviewService.save(
            review: review,
            dayKey: selectedDayKey,
            title: reviewTitle,
            content: content,
            imageFileNames: nextImageFileNames,
            in: modelContext,
            forceCreate: true
        )
        message = "이미지 삭제됨"
    }
}

struct DailyReviewSheet: View {
    var selectedDate: Date
    @Environment(\.dismiss) private var dismiss
    @Query private var reviews: [DailyReview]

    private var selectedDayKey: String {
        DayKey.key(for: selectedDate)
    }

    private var hasReviewImages: Bool {
        guard let review = reviews.first(where: {
            $0.supersededAt == nil && $0.dayKey == selectedDayKey
        }) else { return false }
        return !review.imageFileNames.isEmpty
    }

    private var sheetWidth: CGFloat {
        620
    }

    private var sheetHeight: CGFloat {
        hasReviewImages ? 636 : 310
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("취소") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .frame(width: 120, alignment: .leading)

                Text("오늘 회고")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 14) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 22, weight: .semibold))
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 23, weight: .semibold))
                }
                .foregroundStyle(AppTheme.primaryText)
                .frame(width: 120, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()
                .overlay(AppTheme.border)

            DiaryView(initialDate: selectedDate, showsHeader: false)
        }
        .frame(width: sheetWidth, height: sheetHeight)
        .background(AppTheme.panel)
        .animation(.snappy(duration: 0.18), value: hasReviewImages)
    }
}

private struct DiaryImageView: View {
    var fileName: String?

    var body: some View {
        if let fileName,
           let image = NSImage(contentsOf: DiaryImageStore.imageURL(for: fileName)) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .semibold))
                Text("이미지를 불러올 수 없습니다.")
                    .font(.callout)
            }
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.input)
        }
    }
}

private extension View {
    func diaryTextFieldStyle() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppTheme.primaryText)
            .padding(12)
            .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
