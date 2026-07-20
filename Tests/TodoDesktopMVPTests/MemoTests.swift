import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

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

@Test
@MainActor
func memoServiceSkipsBlankDraftButKeepsExistingMemoWhenCleared() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
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
    let container = try EasyTaskContainerFactory.makeInMemory()
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
    let container = try EasyTaskContainerFactory.makeInMemory()
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
func memoPinDeleteAndIntegrityConvergeOnNewestUpdate() throws {
    let container = try EasyTaskContainerFactory.makeInMemory()
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
func backupV5RoundTripIncludesMemosAndV4TreatsThemAsEmpty() throws {
    let source = try EasyTaskContainerFactory.makeInMemory()
    let memo = Memo(
        content: "백업 메모\n본문",
        isPinned: true,
        createdAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    source.mainContext.insert(memo)
    try source.mainContext.save()

    let contents = try BackupPackageCodec.makeContents(context: source.mainContext)
    #expect(contents.manifest.formatVersion == 5)
    #expect(contents.records.payload.memos?.count == 1)

    let destination = try EasyTaskContainerFactory.makeInMemory()
    let first = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    let second = try BackupPackageCodec.restoreMerging(contents, into: destination.mainContext)
    let restored = try #require(destination.mainContext.fetch(FetchDescriptor<Memo>()).first)
    #expect(first.insertedRecords > 0)
    #expect(second.insertedRecords == 0)
    #expect(restored.instanceID == memo.instanceID)
    #expect(restored.content == memo.content)
    #expect(restored.isPinned)

    let legacySource = try EasyTaskContainerFactory.makeInMemory()
    var v4Contents = try BackupPackageCodec.makeContents(context: legacySource.mainContext)
    v4Contents.manifest.formatVersion = 4
    v4Contents.records.formatVersion = 4
    v4Contents.records.payload.memos = nil
    refreshMemoPackageRecordsMetadata(&v4Contents)
    try BackupPackageCodec.validate(v4Contents)

    let legacyDestination = try EasyTaskContainerFactory.makeInMemory()
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
