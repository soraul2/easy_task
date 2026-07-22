import Foundation
import SwiftData

extension CloudKitConvergenceProbe {
    static let mediaMarkerTitle = "__PLANBASE_CLOUDKIT_MEDIA_PROBE__"
    static let mediaMarkerDayKey = "2099-12-30"

    @MainActor
    static func runMediaProbe(
        configuration: CloudKitProbeConfiguration,
        sourceBundleIdentifier: String,
        context: ModelContext
    ) async throws -> CloudKitProbeRunResult {
        let snapshot: CloudKitMediaProbeSnapshot
        switch configuration.role {
        case .writer:
            try await performMutationAwaitingExportIfRequested(
                configuration: configuration
            ) {
                try writeMediaMarker(
                    token: configuration.token,
                    sourceBundleIdentifier: sourceBundleIdentifier,
                    context: context
                )
            }
            snapshot = try mediaSnapshot(
                token: configuration.token,
                expectation: .present,
                context: context
            )
        case .reader:
            snapshot = try await waitForMediaExpectation(
                configuration.expectation,
                token: configuration.token,
                timeoutSeconds: configuration.timeoutSeconds,
                context: context
            )
        case .cleanup:
            try await performMutationAwaitingExportIfRequested(
                configuration: configuration
            ) {
                try cleanupMediaMarker(token: configuration.token, context: context)
            }
            snapshot = try mediaSnapshot(
                token: configuration.token,
                expectation: .absent,
                context: context
            )
        }

        return CloudKitProbeRunResult(
            kind: .media,
            role: configuration.role,
            token: configuration.token,
            passed: snapshot.passed,
            mediaSnapshot: snapshot,
            error: !snapshot.passed && configuration.role == .reader
                ? "CloudKit media probe timed out"
                : nil
        )
    }

    @MainActor
    static func writeMediaMarker(
        token: UUID,
        sourceBundleIdentifier: String,
        context: ModelContext
    ) throws {
        let existingReviews = try mediaReviews(token: token, context: context)
        let existingAttachments = try mediaAttachments(token: token, context: context)
        guard existingReviews.isEmpty, existingAttachments.isEmpty else {
            throw probeFileExistsError("Media probe token already exists")
        }

        let dayKey = mediaMarkerDayKey
        let occupiedDay = try context.fetch(FetchDescriptor<DailyReview>(
            predicate: #Predicate<DailyReview> { review in
                review.dayKey == dayKey && review.supersededAt == nil
            }
        ))
        guard occupiedDay.isEmpty else {
            throw probeFileExistsError("Media probe day is occupied")
        }

        let data = try mediaMarkerData()
        let metadata = try DiaryAttachmentService.inspect(data)
        let now = Date()
        let review = DailyReview(
            id: token,
            instanceID: UUID(),
            dayKey: dayKey,
            title: mediaMarkerTitle,
            content: "\(token.uuidString)|\(sourceBundleIdentifier)",
            createdAt: now,
            updatedAt: now
        )
        let attachment = DiaryAttachment(
            id: token,
            instanceID: UUID(),
            reviewId: token,
            order: 0,
            originalFileName: mediaMarkerFileName(token: token),
            mimeType: metadata.mediaType.rawValue,
            byteCount: metadata.byteCount,
            sha256: metadata.sha256,
            data: data,
            createdAt: now,
            updatedAt: now
        )

        try PersistenceCommandService.perform(in: context) {
            context.insert(review)
            context.insert(attachment)
        }
        log("LOCAL_MEDIA_SAVED token=\(token.uuidString) bytes=\(metadata.byteCount)")
    }

    @MainActor
    static func cleanupMediaMarker(
        token: UUID,
        context: ModelContext
    ) throws {
        let reviews = try mediaReviews(token: token, context: context)
        let attachments = try mediaAttachments(token: token, context: context)
        let markerReviews = reviews.filter { review in
            isMediaReviewMarker(review, token: token)
        }
        let expectedData = try mediaMarkerData()
        let markerAttachments = attachments.filter { attachment in
            (try? isMediaAttachmentMarker(
                attachment,
                token: token,
                expectedData: expectedData
            )) == true
        }

        guard markerReviews.count == reviews.count,
              markerAttachments.count == attachments.count else {
            log("LOCAL_MEDIA_DELETE_SKIPPED token=\(token.uuidString) collision=true")
            return
        }

        try PersistenceCommandService.perform(in: context) {
            for attachment in markerAttachments {
                context.delete(attachment)
            }
            for review in markerReviews {
                context.delete(review)
            }
        }
        log(
            "LOCAL_MEDIA_DELETED token=\(token.uuidString) " +
                "reviews=\(markerReviews.count) attachments=\(markerAttachments.count)"
        )
    }

    @MainActor
    static func mediaSnapshot(
        token: UUID,
        expectation: CloudKitProbeExpectation,
        context: ModelContext
    ) throws -> CloudKitMediaProbeSnapshot {
        let reviews = try mediaReviews(token: token, context: context)
        let attachments = try mediaAttachments(token: token, context: context)
        let dayReviews = try mediaDayReviews(context: context)
        let activeReviews = reviews.filter { $0.supersededAt == nil }
        let activeAttachments = attachments.filter { $0.supersededAt == nil }
        let conflictingDayReviews = dayReviews.filter { $0.id != token }
        let matchingReviews = activeReviews.filter { review in
            isMediaReviewMarker(review, token: token)
        }
        let expectedData = try mediaMarkerData()
        let expectedMetadata = try DiaryAttachmentService.inspect(expectedData)
        let markerAttachment = activeAttachments.first { attachment in
            attachment.id == token &&
                attachment.reviewId == token &&
                attachment.originalFileName == mediaMarkerFileName(token: token)
        }
        let matchingAttachments = activeAttachments.filter { attachment in
            (try? isMediaAttachmentMarker(
                attachment,
                token: token,
                expectedData: expectedData,
                expectedMetadata: expectedMetadata
            )) == true
        }
        let source = matchingReviews.first?.content
            .split(separator: "|", maxSplits: 1)
            .dropFirst()
            .first
            .map(String.init)
        let passed: Bool
        switch expectation {
        case .present:
            passed = activeReviews.count == 1 &&
                matchingReviews.count == 1 &&
                conflictingDayReviews.isEmpty &&
                activeAttachments.count == 1 &&
                matchingAttachments.count == 1
        case .absent:
            passed = reviews.isEmpty &&
                attachments.isEmpty &&
                conflictingDayReviews.isEmpty
        }

        return CloudKitMediaProbeSnapshot(
            token: token,
            totalReviewCount: reviews.count,
            activeReviewCount: activeReviews.count,
            matchingReviewCount: matchingReviews.count,
            conflictingDayReviewCount: conflictingDayReviews.count,
            totalAttachmentCount: attachments.count,
            activeAttachmentCount: activeAttachments.count,
            matchingAttachmentCount: matchingAttachments.count,
            sourceBundleIdentifier: source,
            attachmentSHA256: matchingAttachments.first?.sha256,
            attachmentByteCount: matchingAttachments.first?.byteCount,
            attachmentOrder: markerAttachment?.order,
            dataMatchesExpected: markerAttachment?.data == expectedData,
            expectation: expectation,
            passed: passed
        )
    }

    @MainActor
    static func waitForMediaExpectation(
        _ expectation: CloudKitProbeExpectation,
        token: UUID,
        timeoutSeconds: Int,
        context: ModelContext
    ) async throws -> CloudKitMediaProbeSnapshot {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeoutSeconds))
        var latest = try mediaSnapshot(
            token: token,
            expectation: expectation,
            context: context
        )

        while !latest.passed && clock.now < deadline {
            try await Swift.Task.sleep(for: .seconds(1))
            latest = try mediaSnapshot(
                token: token,
                expectation: expectation,
                context: context
            )
        }
        return latest
    }
}

private extension CloudKitConvergenceProbe {
    @MainActor
    static func mediaReviews(
        token: UUID,
        context: ModelContext
    ) throws -> [DailyReview] {
        try context.fetch(FetchDescriptor(
            predicate: #Predicate<DailyReview> { review in
                review.id == token
            }
        ))
    }

    @MainActor
    static func mediaAttachments(
        token: UUID,
        context: ModelContext
    ) throws -> [DiaryAttachment] {
        try context.fetch(FetchDescriptor(
            predicate: #Predicate<DiaryAttachment> { attachment in
                attachment.id == token || attachment.reviewId == token
            }
        ))
    }

    @MainActor
    static func mediaDayReviews(
        context: ModelContext
    ) throws -> [DailyReview] {
        let dayKey = mediaMarkerDayKey
        return try context.fetch(FetchDescriptor(
            predicate: #Predicate<DailyReview> { review in
                review.dayKey == dayKey && review.supersededAt == nil
            }
        ))
    }

    static func mediaMarkerFileName(token: UUID) -> String {
        "planbase-cloudkit-probe-\(token.uuidString.lowercased()).png"
    }

    static func mediaMarkerData() throws -> Data {
        guard let data = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return data
    }

    static func isMediaReviewMarker(
        _ review: DailyReview,
        token: UUID
    ) -> Bool {
        let components = review.content.split(
            separator: "|",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        return review.id == token &&
            review.title == mediaMarkerTitle &&
            review.dayKey == mediaMarkerDayKey &&
            components.count == 2 &&
            components[0] == Substring(token.uuidString) &&
            !components[1].isEmpty
    }

    static func isMediaAttachmentMarker(
        _ attachment: DiaryAttachment,
        token: UUID,
        expectedData: Data,
        expectedMetadata: DiaryAttachmentMetadata? = nil
    ) throws -> Bool {
        let metadata = try expectedMetadata ?? DiaryAttachmentService.inspect(expectedData)
        return attachment.id == token &&
            attachment.reviewId == token &&
            attachment.order == 0 &&
            attachment.originalFileName == mediaMarkerFileName(token: token) &&
            attachment.mimeType == metadata.mediaType.rawValue &&
            attachment.byteCount == metadata.byteCount &&
            attachment.sha256 == metadata.sha256 &&
            attachment.data == expectedData
    }

}
