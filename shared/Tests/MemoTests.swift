import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

@Test @MainActor
func memoQueryDistinguishesInitialLoadFailureAndRetries() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let memo = try #require(try MemoService.save(memo: nil, content: "재시도 후 돌아온 메모", in: context))
    var attempts = 0
    let session = MemoQuerySession(context: context) { context, query, cursor in
        attempts += 1
        if attempts == 1 { throw CocoaError(.fileReadUnknown) }
        return try MemoService.page(in: context, query: query, cursor: cursor)
    }
    session.apply(query: "", debounce: false)
    #expect(session.memos.isEmpty)
    #expect(session.errorMessage != nil)
    #expect(!session.isLoading)
    session.retry()
    #expect(session.errorMessage == nil)
    #expect(session.memos.map(\.instanceID) == [memo.instanceID])
    #expect(attempts == 2)
}

@Test @MainActor
func memoQueryKeepsLoadedRowsOnNextPageFailure() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    for index in 0...MemoService.pageSize {
        context.insert(Memo(content: "메모 \(index)"))
    }
    try context.save()
    var attempts = 0
    let session = MemoQuerySession(context: context) { context, query, cursor in
        attempts += 1
        if attempts == 2 || attempts == 3 { throw CocoaError(.fileReadUnknown) }
        return try MemoService.page(in: context, query: query, cursor: cursor)
    }
    session.apply(query: "", debounce: false)
    let firstIDs = session.memos.map(\.instanceID)
    #expect(session.hasMore)
    session.loadNextPage()
    #expect(session.errorMessage != nil)
    #expect(session.memos.map(\.instanceID) == firstIDs)
    session.retry()
    #expect(session.errorMessage != nil)
    #expect(session.memos.map(\.instanceID) == firstIDs)
    session.retry()
    #expect(session.errorMessage == nil)
    #expect(session.memos.count == MemoService.pageSize + 1)
    #expect(Set(session.memos.map(\.instanceID)).count == session.memos.count)
}

@Test
func memoRulesDeriveTitlePreviewAndNormalizedSearch() {
    let memo = Memo(content: "\n  Café 준비  \n원두 주문\n필터 교체")

    #expect(MemoRules.displayTitle(for: memo.content) == "Café 준비")
    #expect(MemoRules.preview(for: memo.content) == "원두 주문 필터 교체")
    #expect(MemoRules.displayTitle(for: " \n\t") == "빈 메모")
    #expect(MemoRules.matches(memo, query: "CAFE"))
    #expect(MemoRules.matches(memo, query: "원두"))
    #expect(!MemoRules.matches(memo, query: "장보기"))
}

@Test @MainActor
func memoPinDoesNotHideFailedContentSave() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let memo = try #require(try MemoService.save(memo: nil, content: "원본", in: context))
    let session = MemoEditorSession(memo: memo, context: context, saveComposite: { _, _, _, _, _, _ in
        throw CocoaError(.fileWriteUnknown)
    })
    session.updateContent("보존할 초안")
    session.setPinned(true)
    #expect(!memo.isPinned)
    #expect(memo.content == "원본")
    #expect(session.content == "보존할 초안")
    if case .failed = session.saveState {} else { Issue.record("저장 오류가 고정 성공으로 가려짐") }
}

@Test
func memoPreviewBoundsLongContentWithoutChangingSearchOrUnicode() {
    let body = String(repeating: "가족 👨‍👩‍👧‍👦 준비 사항\n", count: 1_000) + "끝의 검색어"
    let memo = Memo(content: "\r\n \t\u{000B}제목\u{2028}" + body)
    #expect(MemoRules.displayTitle(for: memo.content) == "제목")
    let preview = MemoRules.preview(for: memo.content)
    #expect(preview.count <= 241)
    #expect(preview.hasSuffix("…"))
    #expect(MemoRules.matches(memo, query: "끝의 검색어"))
    #expect(MemoRules.preview(for: "제목\n👨‍👩‍👧‍👦abc", maximumLength: 1) == "👨‍👩‍👧‍👦…")
    #expect(MemoRules.preview(for: "제목\nabc", maximumLength: 3) == "abc")
    #expect(MemoRules.preview(for: "제목\nabc\nd", maximumLength: 3) == "abc…")
    #expect(MemoRules.preview(for: "한 줄") == "한 줄")
    #expect(MemoRules.preview(for: "제목", maximumLength: 0).isEmpty)
}

@Test
func memoDrawingPreviewBoundsRasterSizeWithoutChangingSource() throws {
    #expect(MemoDrawingPreviewRules.scale(width: 400, height: 300) == 2)
    for (width, height) in [(10_000.0, 10_000.0), (50_000.0, 500.0), (120.0, 100_000.0)] {
        let scale = try #require(MemoDrawingPreviewRules.scale(width: width, height: height))
        #expect(width * scale <= 1_800)
        #expect(height * scale <= 1_800)
        #expect(width * height * scale * scale <= 3_240_000.01)
    }
    #expect(MemoDrawingPreviewRules.scale(width: .infinity, height: 1) == nil)
    #expect(MemoDrawingPreviewRules.scale(width: 1, height: .nan) == nil)
    #expect(MemoDrawingPreviewRules.scale(width: 0, height: 1) == nil)
}

@Test @MainActor
func memoRefreshPreservesLoadedPagesAndRowsAfterFailure() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    for index in 0...MemoService.pageSize { context.insert(Memo(content: "메모 \(index)")) }
    try context.save()
    var attempts = 0
    let session = MemoQuerySession(context: context) { context, query, cursor in
        attempts += 1
        if attempts == 6 { throw CocoaError(.fileReadUnknown) }
        return try MemoService.page(in: context, query: query, cursor: cursor)
    }
    session.apply(query: "", debounce: false)
    session.loadNextPage()
    let ids = session.memos.map(\.instanceID)
    session.refresh()
    #expect(session.memos.map(\.instanceID) == ids)
    session.refresh()
    #expect(session.errorMessage != nil)
    #expect(session.memos.map(\.instanceID) == ids)
    session.retry()
    #expect(session.errorMessage == nil)
    #expect(session.memos.map(\.instanceID) == ids)
}

@Test @MainActor
func memoRefreshUsesPendingSearch() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    var queries: [String] = []
    let session = MemoQuerySession(context: context) { context, query, cursor in
        queries.append(query)
        return try MemoService.page(in: context, query: query, cursor: cursor)
    }
    session.apply(query: "이전", debounce: false)
    session.apply(query: "새 검색", debounce: true)
    session.refresh()
    #expect(queries == ["이전", "새 검색"])
}

@Test @MainActor
func memoUnreadChildrenCannotBeOverwrittenAndRetryRestoresThem() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let drawing = Data([1, 2, 3])
    let checklist = [MemoChecklistDraft(title: "보존할 항목", order: 100)]
    let memo = try #require(try MemoService.saveComposite(
        memo: nil, content: "원본", preferredMode: .text,
        drawingData: drawing, checklistDrafts: checklist, in: context
    ))
    var loads = 0
    let session = MemoEditorSession(memo: memo, context: context, loadContent: { id, context in
        let drawing = try MemoDrawingService.data(for: id, in: context)
        loads += 1
        if loads == 1 { throw CocoaError(.fileReadUnknown) }
        return (drawing, try MemoChecklistService.drafts(for: id, in: context))
    })
    #expect(session.loadErrorMessage != nil)
    session.updateContent("읽지 못한 상태에서 쓰기")
    session.updateDrawingData(Data())
    session.appendChecklistItem()
    session.setPinned(true)
    #expect(!session.flush())
    #expect(!session.hasUnsavedChanges)
    #expect(memo.content == "원본")
    #expect(!memo.isPinned)
    session.retryLoad()
    #expect(session.loadErrorMessage == nil)
    #expect(session.drawingData == drawing)
    #expect(session.checklistDrafts == checklist)
    session.updateContent("안전한 편집")
    #expect(session.flush())
    #expect(try MemoDrawingService.data(for: memo.id, in: context) == drawing)
    #expect(try MemoChecklistService.drafts(for: memo.id, in: context) == checklist)
}

@Test @MainActor
func memoFailedFlushKeepsUnsavedDraftUntilSuccessfulRetry() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    var attempts = 0
    let session = MemoEditorSession(memo: nil, context: container.mainContext, saveComposite: { memo, content, mode, drawing, checklist, context in
        attempts += 1
        if attempts == 1 { throw CocoaError(.fileWriteUnknown) }
        return try MemoService.saveComposite(memo: memo, content: content, preferredMode: mode,
            drawingData: drawing, checklistDrafts: checklist, in: context)
    })
    session.updateContent("떠나기 전에 저장할 초안")
    #expect(!session.flush())
    #expect(session.hasUnsavedChanges)
    #expect(session.content == "떠나기 전에 저장할 초안")
    #expect(session.flush())
    #expect(!session.hasUnsavedChanges)
    #expect(session.memo?.content == "떠나기 전에 저장할 초안")
}

@Test @MainActor
func memoRetrySavesPendingPinAfterContentFailure() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let memo = try #require(try MemoService.save(memo: nil, content: "원본", in: context))
    var attempts = 0
    let session = MemoEditorSession(memo: memo, context: context, saveComposite: { memo, content, mode, drawing, checklist, context in
        attempts += 1
        if attempts == 1 { throw CocoaError(.fileWriteUnknown) }
        return try MemoService.saveComposite(memo: memo, content: content, preferredMode: mode,
            drawingData: drawing, checklistDrafts: checklist, in: context)
    })
    session.updateContent("고정할 새 내용")
    session.setPinned(true)
    #expect(session.hasUnsavedChanges)
    #expect(!memo.isPinned)
    #expect(session.flush())
    #expect(memo.isPinned)
    #expect(memo.content == "고정할 새 내용")
    #expect(!session.hasUnsavedChanges)
    #expect(session.saveState == .saved)
}

@Test @MainActor
func memoUnchangedChecklistDoesNotDirtyPersistentModels() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let id = UUID()
    let drafts = [MemoChecklistDraft(title: "동일 항목", order: 100)]
    _ = try MemoChecklistService.replace(for: id, with: drafts, in: context, now: Date())
    try context.save()
    #expect(!context.hasChanges)
    #expect(try !MemoChecklistService.replace(for: id, with: drafts, in: context, now: Date()))
    #expect(!context.hasChanges)
}

@Test
func memoTimestampUsesKoreanDateOrder() throws {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)
    components.year = 2026
    components.month = 9
    components.day = 5
    components.hour = 16
    components.minute = 30
    let date = try #require(components.date)

    let text = MemoRules.updatedAtText(date)

    #expect(text.contains("2026"))
    #expect(text.contains("9"))
    #expect(text.contains("5"))
    #expect(!text.contains("Sep"))
    #expect(!text.contains("at"))
}

@Test
@MainActor
func memoServiceSkipsBlankDraftButKeepsExistingMemoWhenCleared() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext

    let blank = try MemoService.save(memo: nil, content: "  \n ", in: context)
    #expect(blank == nil)
    #expect(try context.fetchCount(FetchDescriptor<Memo>()) == 0)

    let createdAt = Date(timeIntervalSince1970: 100)
    let memo = try #require(try MemoService.save(
        memo: nil,
        content: "장보기\n우유",
        now: createdAt,
        in: context
    ))
    let clearedAt = Date(timeIntervalSince1970: 200)
    let cleared = try #require(try MemoService.save(
        memo: memo,
        content: "",
        now: clearedAt,
        in: context
    ))

    #expect(cleared.instanceID == memo.instanceID)
    #expect(cleared.content.isEmpty)
    #expect(cleared.updatedAt == clearedAt)
    #expect(MemoRules.displayTitle(for: cleared.content) == "빈 메모")
    #expect(try context.fetchCount(FetchDescriptor<Memo>()) == 1)
}

@Test
@MainActor
func memoQueryPinsFirstSearchesFullContentAndPaginates() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let base = Date(timeIntervalSince1970: 1_000)

    let pinned = Memo(
        content: "고정 메모\n중요한 내용",
        isPinned: true,
        createdAt: base,
        updatedAt: base
    )
    context.insert(pinned)
    for index in 0..<45 {
        context.insert(Memo(
            content: "일반 메모 \(index)\n검색 본문",
            createdAt: base.addingTimeInterval(Double(index + 1)),
            updatedAt: base.addingTimeInterval(Double(index + 1))
        ))
    }
    try context.save()

    let first = try MemoService.page(in: context, query: "")
    #expect(first.memos.count == MemoService.pageSize)
    #expect(first.memos.first?.instanceID == pinned.instanceID)
    #expect(first.hasMore)

    let second = try MemoService.page(
        in: context,
        query: "",
        cursor: first.nextCursor
    )
    #expect(second.memos.count == 6)
    #expect(!second.hasMore)

    let searched = try MemoService.page(in: context, query: "검색 본문")
    #expect(searched.memos.count == MemoService.pageSize)
    #expect(searched.memos.allSatisfy { $0.content.contains("검색 본문") })
}

@Test
@MainActor
func memoEditorDebouncesAndFlushesPendingChanges() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let session = MemoEditorSession(memo: nil, context: context)

    session.updateContent("자동 저장\n600ms 검증")
    #expect(session.saveState == .saving)
    for _ in 0..<50 {
        if try context.fetchCount(FetchDescriptor<Memo>()) > 0 { break }
        try await Swift.Task.sleep(for: .milliseconds(100))
    }

    let saved = try #require(context.fetch(FetchDescriptor<Memo>()).first)
    #expect(saved.content == "자동 저장\n600ms 검증")
    #expect(session.saveState == .saved)

    session.updateContent("화면 이탈 직전 저장")
    session.flush()
    #expect(saved.content == "화면 이탈 직전 저장")
    #expect(session.saveState == .saved)
}

@Test
@MainActor
func memoEditorPreservesTextDrawingAndChecklistTogether() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    // An older app could create all three kinds in one memo. Keep that
    // compatibility fixture explicit; new editors intentionally cannot do so.
    let memo = try #require(try MemoService.saveComposite(
        memo: nil, content: "회의 메모", preferredMode: .checklist,
        drawingData: Data([0x01, 0x02, 0x03]),
        checklistDrafts: [MemoChecklistDraft(title: "초기 항목", order: 100)], in: context
    ))
    let session = MemoEditorSession(memo: memo, context: context)
    #expect(session.isComposite)
    let itemID = try #require(session.checklistDrafts.first?.id)
    session.updateChecklistTitle(id: itemID, title: "자료 보내기")
    #expect(session.flush())

    #expect(memo.content == "회의 메모")
    #expect(MemoRules.mode(for: memo) == .checklist)
    #expect(try MemoDrawingService.data(for: memo.id, in: context) == Data([0x01, 0x02, 0x03]))
    let checklist = try context.fetch(MemoChecklistService.descriptor(memoID: memo.id))
    #expect(checklist.map(\.title) == ["자료 보내기"])

    let searched = try MemoService.page(in: context, query: "자료 보내기")
    #expect(searched.memos.map(\.id) == [memo.id])

    let reopened = MemoEditorSession(memo: memo, context: context)
    #expect(reopened.content == "회의 메모")
    #expect(reopened.drawingData == Data([0x01, 0x02, 0x03]))
    #expect(reopened.checklistDrafts.map(\.title) == ["자료 보내기"])

    try reopened.delete()
    #expect(try context.fetchCount(FetchDescriptor<MemoDrawing>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<MemoChecklistItem>()) == 0)
}

@Test
@MainActor
func memoPinDeleteAndIntegrityConvergeOnNewestUpdate() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let logicalID = UUID()
    let older = Memo(
        id: logicalID,
        instanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        content: "예전 내용",
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 20)
    )
    let newest = Memo(
        id: logicalID,
        instanceID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        content: "최신 내용",
        createdAt: Date(timeIntervalSince1970: 15),
        updatedAt: Date(timeIntervalSince1970: 30)
    )
    context.insert(older)
    context.insert(newest)
    try context.save()

    let report = try DataIntegrityService.reconcile(context: context)
    let active = try #require(context.fetch(FetchDescriptor<Memo>()).first {
        $0.supersededAt == nil
    })
    #expect(report.mergedRecords == 1)
    #expect(active.instanceID == newest.instanceID)
    #expect(active.content == "최신 내용")
    #expect(active.createdAt == older.createdAt)

    try MemoService.setPinned(true, for: active, in: context)
    #expect(active.isPinned)
    try MemoService.delete(active, in: context)
    #expect(try context.fetch(FetchDescriptor<Memo>()).allSatisfy { $0.supersededAt != nil })
}

@Test
@MainActor
func memoContentIntegrityConvergesChildrenAndSupersedesOrphans() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let memo = Memo(content: "복합 메모")
    context.insert(memo)

    let olderDrawing = MemoDrawing(
        memoId: memo.id,
        drawingData: Data([0x01]),
        createdAt: Date(timeIntervalSince1970: 10),
        updatedAt: Date(timeIntervalSince1970: 20)
    )
    let newerDrawing = MemoDrawing(
        memoId: memo.id,
        drawingData: Data([0x02]),
        createdAt: Date(timeIntervalSince1970: 15),
        updatedAt: Date(timeIntervalSince1970: 30)
    )
    let orphan = MemoChecklistItem(
        memoId: UUID(),
        title: "고아 항목",
        order: 100
    )
    let blank = MemoChecklistItem(
        memoId: memo.id,
        title: "   ",
        order: 200
    )
    let valid = MemoChecklistItem(
        memoId: memo.id,
        title: "  정상 항목  ",
        isCompleted: true,
        order: .infinity
    )
    context.insert(olderDrawing)
    context.insert(newerDrawing)
    context.insert(orphan)
    context.insert(blank)
    context.insert(valid)
    try context.save()

    let report = try DataIntegrityService.reconcile(context: context)
    let activeDrawings = try context.fetch(FetchDescriptor<MemoDrawing>())
        .filter { $0.supersededAt == nil }
    #expect(activeDrawings.count == 1)
    #expect(activeDrawings.first?.drawingData == Data([0x02]))
    #expect(orphan.supersededAt != nil)
    #expect(blank.supersededAt != nil)
    #expect(valid.title == "정상 항목")
    #expect(valid.order == 100)
    #expect(valid.completedAt != nil)
    #expect(report.hasChanges)
}

@Test
@MainActor
func backupV6RoundTripIncludesMemosAndV4TreatsThemAsEmpty() throws {
    let source = try PlanBaseContainerFactory.makeInMemory()
    let memo = Memo(
        content: "백업 메모\n본문",
        isPinned: true,
        createdAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    source.mainContext.insert(memo)
    memo.preferredModeRawValue = MemoEditorMode.drawing.rawValue
    let drawing = MemoDrawing(
        memoId: memo.id,
        drawingData: Data([0x10, 0x20]),
        createdAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    let checklistItem = MemoChecklistItem(
        memoId: memo.id,
        title: "백업 체크 항목",
        isCompleted: true,
        order: 100,
        completedAt: Date(timeIntervalSince1970: 180),
        createdAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    source.mainContext.insert(drawing)
    source.mainContext.insert(checklistItem)
    try source.mainContext.save()

    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    #expect(contents.manifest.formatVersion == BackupPackageCodec.currentVersion)
    #expect(contents.records.payload.memos?.count == 1)
    #expect(contents.records.payload.memoDrawings?.count == 1)
    #expect(contents.records.payload.memoChecklistItems?.count == 1)

    let destination = try PlanBaseContainerFactory.makeInMemory()
    let first = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    let second = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    let restored = try #require(destination.mainContext.fetch(FetchDescriptor<Memo>()).first)
    #expect(first.insertedRecords > 0)
    #expect(second.insertedRecords == 0)
    #expect(restored.instanceID == memo.instanceID)
    #expect(restored.content == memo.content)
    #expect(restored.isPinned)
    #expect(MemoRules.mode(for: restored) == .drawing)
    #expect(try MemoDrawingService.data(for: restored.id, in: destination.mainContext) == drawing.drawingData)
    #expect(try destination.mainContext.fetch(
        MemoChecklistService.descriptor(memoID: restored.id)
    ).map(\.title) == ["백업 체크 항목"])

    let legacySource = try PlanBaseContainerFactory.makeInMemory()
    var v4Contents = try BackupPackageCodec.makeContents(context: legacySource.mainContext)
    v4Contents.manifest.formatVersion = 4
    v4Contents.records.formatVersion = 4
    v4Contents.records.payload.memos = nil
    v4Contents.records.payload.memoDrawings = nil
    v4Contents.records.payload.memoChecklistItems = nil
    refreshMemoPackageRecordsMetadata(&v4Contents)
    try BackupPackageCodec.validate(v4Contents)

    let legacyDestination = try PlanBaseContainerFactory.makeInMemory()
    _ = try BackupPackageCodec.restoreMerging(
        v4Contents,
        into: legacyDestination.mainContext
    )
    #expect(try legacyDestination.mainContext.fetchCount(FetchDescriptor<Memo>()) == 0)
}

private func refreshMemoPackageRecordsMetadata(_ contents: inout BackupPackageContents) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try! encoder.encode(contents.records)
    contents.manifest.recordsByteCount = data.count
    contents.manifest.recordsSHA256 = SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

@Test @MainActor
func memoTypeSelectionDoesNotSaveEmptyDrafts() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    for mode in MemoEditorMode.creationOrder {
        let session = MemoEditorSession(memo: nil, context: container.mainContext, initialMode: mode)
        #expect(session.preferredMode == mode)
        #expect(session.canChooseType)
        session.updatePreferredMode(.checklist)
        session.appendChecklistItem()
        session.updatePreferredMode(.drawing)
        #expect(session.flush())
        #expect(session.memo == nil)
    }
    #expect(try container.mainContext.fetchCount(FetchDescriptor<Memo>()) == 0)
    #expect(try container.mainContext.fetchCount(FetchDescriptor<MemoChecklistItem>()) == 0)
}

@Test @MainActor
func memoSingleTypeRemainsLockedAfterSaveReopenAndClear() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    for mode in MemoEditorMode.creationOrder {
        let session = MemoEditorSession(memo: nil, context: context, initialMode: mode)
        switch mode {
        case .text: session.updateContent("글 메모 내용")
        case .drawing: session.updateDrawingData(Data([1, 2, 3]))
        case .checklist:
            session.appendChecklistItem()
            session.updateChecklistTitle(id: try #require(session.checklistDrafts.first?.id), title: "할 일")
        }
        #expect(!session.canChooseType)
        for other in MemoEditorMode.creationOrder { session.updatePreferredMode(other) }
        #expect(session.preferredMode == mode)
        #expect(session.flush())
        let memo = try #require(session.memo)
        let reopened = MemoEditorSession(memo: memo, context: context)
        #expect(reopened.preferredMode == mode)
        #expect(!reopened.isComposite)
        #expect(!reopened.canChooseType)
        switch mode {
        case .text: reopened.updateContent("")
        case .drawing: reopened.updateDrawingData(Data())
        case .checklist: reopened.removeChecklistItem(id: try #require(reopened.checklistDrafts.first?.id))
        }
        #expect(reopened.flush())
        let cleared = MemoEditorSession(memo: memo, context: context)
        #expect(cleared.preferredMode == mode)
        #expect(!cleared.canChooseType)
    }
    #expect(try context.fetchCount(FetchDescriptor<Memo>()) == 3)
}

@Test @MainActor
func memoSingleEditorCannotAccidentallyWriteAnotherType() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let session = MemoEditorSession(memo: nil, context: container.mainContext)
    session.updateContent("원문")
    session.updateDrawingData(Data([1]))
    session.appendChecklistItem()
    #expect(session.flush())
    #expect(session.drawingData.isEmpty)
    #expect(session.checklistDrafts.isEmpty)
    #expect(!session.isComposite)
}

@Test @MainActor
func memoContentOverridesStaleLegacyPreferenceWithoutHidingAnything() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let memo = try #require(try MemoService.saveComposite(
        memo: nil, content: "", preferredMode: .text, drawingData: Data(),
        checklistDrafts: [MemoChecklistDraft(title: "체크 내용", order: 100)], in: context
    ))
    let session = MemoEditorSession(memo: memo, context: context)
    #expect(session.preferredMode == .checklist)
    #expect(session.displayTitle == "체크 내용")
    #expect(!session.isComposite)
}

@Test @MainActor
func memoSavePreservesNewlySyncedOtherTypesWithoutNotification() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let memo = try #require(try MemoService.save(memo: nil, content: "원문", in: context))
    let session = MemoEditorSession(memo: memo, context: context)
    session.updateContent("로컬 초안")
    let remoteItems = [MemoChecklistDraft(title: "구버전 기기의 항목", order: 100)]
    _ = try MemoService.saveComposite(memo: memo, content: "원문", preferredMode: .drawing,
        drawingData: Data([4, 5]), checklistDrafts: remoteItems, in: context)
    #expect(session.flush())
    #expect(memo.content == "로컬 초안")
    #expect(try MemoDrawingService.data(for: memo.id, in: context) == Data([4, 5]))
    #expect(try MemoChecklistService.drafts(for: memo.id, in: context) == remoteItems)
    #expect(session.isComposite)
    session.updatePreferredMode(.drawing)
    #expect(session.drawingData == Data([4, 5]))
}

@Test @MainActor
func memoImportRefreshKeepsDraftAndMakesAddedTypesAccessible() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let memo = try #require(try MemoService.saveComposite(memo: nil, content: "",
        preferredMode: .drawing, drawingData: Data([1]), checklistDrafts: [], in: context))
    let session = MemoEditorSession(memo: memo, context: context)
    session.updateDrawingData(Data([9]))
    _ = try MemoService.saveComposite(memo: memo, content: "동기화된 글", preferredMode: .text,
        drawingData: Data([1]), checklistDrafts: [], in: context)
    session.refreshFromStore()
    #expect(session.drawingData == Data([9]))
    #expect(session.content == "동기화된 글")
    #expect(session.preferredMode == .drawing)
    #expect(session.isComposite)
    #expect(session.hasUnsavedChanges)
    #expect(session.flush())
    #expect(memo.content == "동기화된 글")
    #expect(try MemoDrawingService.data(for: memo.id, in: context) == Data([9]))
}

@Test(arguments: [false, true], [false, true]) @MainActor
func memoImportAdoptsNewRepresentativeWithoutLosingOtherTypes(
    refreshBeforeSave: Bool, reconcileBeforeSave: Bool
) throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let original = try #require(try MemoService.saveComposite(memo: nil, content: "",
        preferredMode: .drawing, drawingData: Data([1]), checklistDrafts: [], in: context))
    let session = MemoEditorSession(memo: original, context: context)
    session.updateDrawingData(Data([9]))
    let imported = Memo(id: original.id, content: "구버전 기기가 추가한 글",
        updatedAt: original.updatedAt.addingTimeInterval(1))
    context.insert(imported)
    try context.save()
    if reconcileBeforeSave {
        _ = try DataIntegrityService.reconcile(context: context)
        #expect(original.supersededAt != nil)
    }
    if refreshBeforeSave { session.refreshFromStore() }
    #expect(session.flush())
    #expect(session.memo?.instanceID == imported.instanceID)
    #expect(session.content == "구버전 기기가 추가한 글")
    #expect(session.isComposite)
    #expect(try MemoDrawingService.data(for: imported.id, in: context) == Data([9]))
    #expect(original.content.isEmpty)
    let reopened = MemoEditorSession(memo: imported, context: context)
    #expect(reopened.isComposite)
    #expect(reopened.content == session.content)
    #expect(reopened.drawingData == session.drawingData)
}

@Test @MainActor
func memoPinTargetsImportedRepresentativeAndDeletedMemoKeepsUnsavedDraft() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let original = try #require(try MemoService.save(memo: nil, content: "처음 글", in: context))
    let session = MemoEditorSession(memo: original, context: context)
    let imported = Memo(id: original.id, content: "동기화된 글",
        updatedAt: original.updatedAt.addingTimeInterval(1))
    context.insert(imported)
    try context.save()
    _ = try DataIntegrityService.reconcile(context: context)
    session.setPinned(true)
    #expect(session.memo?.instanceID == imported.instanceID)
    #expect(imported.isPinned)
    #expect(!original.isPinned)
    session.updateContent("아직 저장하지 않은 글")
    try MemoService.delete(imported, in: context)
    #expect(!session.flush())
    #expect(session.content == "아직 저장하지 않은 글")
    #expect(session.hasUnsavedChanges)
    #expect(try MemoService.page(in: context, query: "").memos.isEmpty)
}

@Test @MainActor
func memoPageSummariesIncludeChecklistCountsAndCompositeContent() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let items = [MemoChecklistDraft(title: "첫 항목", isCompleted: true, order: 100),
                 MemoChecklistDraft(title: "둘째 항목", order: 200)]
    let checklist = try #require(try MemoService.saveComposite(memo: nil, content: "",
        preferredMode: .text, drawingData: Data(), checklistDrafts: items, in: context))
    let mixed = try #require(try MemoService.saveComposite(memo: nil, content: "기존 복합 내용",
        preferredMode: .drawing, drawingData: Data([1]), checklistDrafts: items, in: context))
    let page = try MemoService.page(in: context, query: "")
    let summary = try #require(page.summaries[checklist.instanceID])
    #expect(summary.title == "첫 항목")
    #expect(summary.mode == .checklist)
    #expect(summary.preview.contains("1/2 완료"))
    #expect(summary.preview.contains("둘째 항목"))
    #expect(!summary.isComposite)
    let composite = try #require(page.summaries[mixed.instanceID])
    #expect(composite.isComposite)
    #expect(composite.drawingUpdatedAt != nil)
    #expect(composite.preview.contains("기존 복합 내용"))
    #expect(composite.preview.contains("1/2 완료"))
}

#if DEBUG
@Test @MainActor
func memoLegacyUITestFixtureDoesNotDuplicateOrResetEditedContent() throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    try MemoUITestSupport.seedLegacyMemo(in: context)
    let memo = try #require(try context.fetch(FetchDescriptor<Memo>()).first)
    let editor = MemoEditorSession(memo: memo, context: context)
    #expect(editor.isComposite)
    editor.updateContent("수정한 기존 메모")
    editor.toggleChecklistItem(id: try #require(editor.checklistDrafts.first?.id))
    #expect(editor.flush())
    try MemoUITestSupport.seedLegacyMemo(in: context)
    #expect(try context.fetchCount(FetchDescriptor<Memo>()) == 1)
    #expect(memo.content == "수정한 기존 메모")
    let items = try MemoChecklistService.drafts(for: memo.id, in: context)
    #expect(items.count == 1)
    #expect(items.first?.isCompleted == true)
}
#endif
