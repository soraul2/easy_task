#if DEBUG && canImport(PencilKit) && canImport(AppKit)
import AppKit
import CryptoKit
import Foundation
import PencilKit
import Testing
@testable import EasyTaskCore

/// Opt-in, synthetic macOS PencilKit function timings. No canvas, SwiftUI body,
/// visible-row count, persistence fetch, or user drawing is measured here.
/// Fixture construction, digests, validation, and bitmap inspection are untimed.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_MEMO_DRAWING_PERFORMANCE"] == "1"))
@MainActor
func goalMemoDrawingPerformance() throws {
    for (size, strokeCount, sampleCount) in [("small", 8, 30), ("medium", 128, 30), ("large", 1_024, 10)] {
        let drawing = goalMemoDrawingFixture(strokeCount: strokeCount)
        let sourceDigest = goalMemoDrawingValueDigest(drawing)
        let data = drawing.dataRepresentation()
        let sourceDataDigest = goalMemoDrawingDataDigest(data)
        let decoded = try PKDrawing(data: data)
        #expect(drawing.strokes.count == strokeCount)
        #expect(data.count <= MemoDrawingService.maximumDrawingSizeBytes)
        #expect(goalMemoDrawingValueDigest(decoded) == sourceDigest)
        #expect(drawing == decoded)
        goalMemoDrawingValidateBounds(drawing.bounds)

        let bounds = decoded.bounds.insetBy(dx: -8, dy: -8)
        let baseScale = try #require(MemoDrawingPreviewRules.scale(width: bounds.width, height: bounds.height))
        let scale = min(baseScale, 240 / max(bounds.width, bounds.height))
        let referencePreview = goalMemoDrawingRenderRow(decoded, bounds: bounds, scale: scale)
        let previewDigest = try goalMemoDrawingPreviewDigest(referencePreview, bounds: bounds, scale: scale)
        let details = "fixture=\(size) strokes=\(strokeCount) pointsPerStroke=24 bytes=\(data.count) sourceValueDigest=\(sourceDigest) sourceDataDigest=\(sourceDataDigest) actualCanvasCallbacks=unmeasured actualVisibleRows=unmeasured"

        var serializedDataDigests: Set<String> = []
        try goalMemoDrawingSamples(
            name: "data-representation", details: details, count: sampleCount,
            expectedDigest: sourceDigest,
            operation: { drawing.dataRepresentation() },
            validate: { result in
                // Bytes are diagnostic: PencilKit does not promise a canonical,
                // cross-process archive. Compare the decoded drawing's values.
                serializedDataDigests.insert(goalMemoDrawingDataDigest(result))
                let resultDrawing = try PKDrawing(data: result)
                #expect(resultDrawing.strokes.count == strokeCount)
                return goalMemoDrawingValueDigest(resultDrawing)
            })
        print("GOAL_MEMO_DRAWING_SERIALIZATION fixture=\(size) encodedDataDigests=\(serializedDataDigests.sorted()) canonicalBytesAssumed=false")

        try goalMemoDrawingSamples(
            name: "decode", details: details, count: sampleCount, expectedDigest: sourceDigest,
            operation: { try PKDrawing(data: data) },
            validate: { result in
                #expect(result.strokes.count == strokeCount)
                goalMemoDrawingValidateBounds(result.bounds)
                return goalMemoDrawingValueDigest(result)
            })

        try goalMemoDrawingSamples(
            name: "row-preview-render-bitmap", details: "\(details) targetMaxPixels=240 decodeTimed=false fetchTimed=false",
            count: sampleCount, expectedDigest: previewDigest,
            operation: { goalMemoDrawingRenderRow(decoded, bounds: bounds, scale: scale) },
            validate: { try goalMemoDrawingPreviewDigest($0, bounds: bounds, scale: scale) })

        // The same-value echo proposal must compare equality's cost with encoding.
        // A restored value and a direct copy may exercise different equality paths.
        for (identity, copy) in [("direct-copy", drawing), ("decoded-copy", decoded)] {
            try goalMemoDrawingSamples(
                name: "drawing-equality-\(identity)", details: details, count: sampleCount,
                expectedDigest: "equal",
                operation: { drawing == copy },
                validate: { $0 ? "equal" : "different" })
        }

        // Same stroke count alone cannot establish equality (move/erase/undo).
        var alteredStrokes = drawing.strokes
        alteredStrokes[0].transform = CGAffineTransform(translationX: 1, y: 0)
        let altered = PKDrawing(strokes: alteredStrokes)
        #expect(altered.strokes.count == drawing.strokes.count)
        #expect(altered != drawing)
        #expect(goalMemoDrawingValueDigest(altered) != sourceDigest)
        #expect(PKDrawing() != drawing)
        #expect(goalMemoDrawingNormalizedData(PKDrawing()).isEmpty)

        // Serialization and previews must leave the original value and bytes alone.
        #expect(drawing.strokes.count == strokeCount)
        #expect(goalMemoDrawingValueDigest(drawing) == sourceDigest)
        #expect(goalMemoDrawingDataDigest(data) == sourceDataDigest)
    }
}

@MainActor
private func goalMemoDrawingFixture(strokeCount: Int) -> PKDrawing {
    let ink = PKInk(.pen, color: NSColor(srgbRed: 0.25, green: 0.5, blue: 0.75, alpha: 1))
    let date = Date(timeIntervalSince1970: 1_788_400_000)
    let strokes = (0..<strokeCount).map { index in
        let column = index % 32
        let row = index / 32
        var points: [PKStrokePoint] = []
        points.reserveCapacity(24)
        for point in 0..<24 {
            let x = CGFloat(column * 48 + point + 8)
            let y = CGFloat(row * 60 + (point % 6) * 3 + index % 3 + 8)
            let width = CGFloat(3 + index % 3)
            let force: CGFloat = 0.5 + CGFloat(point % 3) / 4
            let value = PKStrokePoint(
                location: CGPoint(x: x, y: y), timeOffset: Double(point) / 8,
                size: CGSize(width: width, height: width),
                opacity: 1, force: force, azimuth: .pi / 4, altitude: .pi / 2)
            points.append(value)
        }
        return PKStroke(
            ink: ink, path: PKStrokePath(controlPoints: points, creationDate: date.addingTimeInterval(Double(index))),
            transform: .identity, mask: nil, randomSeed: UInt32(1_000 + index))
    }
    return PKDrawing(strokes: strokes)
}

private func goalMemoDrawingNormalizedData(_ drawing: PKDrawing) -> Data {
    drawing.strokes.isEmpty ? Data() : drawing.dataRepresentation()
}

private struct GoalMemoDrawingPreview {
    var image: NSImage
    var raster: CGImage?
}

@MainActor
private func goalMemoDrawingRenderRow(_ drawing: PKDrawing, bounds: CGRect, scale: CGFloat) -> GoalMemoDrawingPreview {
    // Match DesktopMemoThumbnail: image(from:) followed by a stable bitmap.
    // UIKit's thumbnail stops at UIImage; its device timing requires an iOS run.
    let rendered = drawing.image(from: bounds, scale: scale)
    if let raster = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        return GoalMemoDrawingPreview(image: NSImage(cgImage: raster, size: rendered.size), raster: raster)
    }
    return GoalMemoDrawingPreview(image: rendered, raster: nil)
}

@MainActor
private func goalMemoDrawingPreviewDigest(_ result: GoalMemoDrawingPreview, bounds: CGRect, scale: CGFloat) throws -> String {
    goalMemoDrawingValidateBounds(CGRect(origin: .zero, size: result.image.size))
    let raster = try #require(result.raster) // A valid synthetic row should resolve its bitmap.
    #expect(raster.width > 0 && raster.height > 0)
    // Fractional bounds can round at the raster edge; this is a 240px target,
    // with two pixels of tolerance, not a claim of exactly 240px on each axis.
    #expect(max(raster.width, raster.height) <= 242)
    #expect(abs(Double(raster.width) - Double(bounds.width * scale)) <= 2)
    #expect(abs(Double(raster.height) - Double(bounds.height * scale)) <= 2)
    let bitmap = try #require(CGContext(
        data: nil, width: raster.width, height: raster.height,
        bitsPerComponent: 8, bytesPerRow: raster.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    bitmap.draw(raster, in: CGRect(x: 0, y: 0, width: CGFloat(raster.width), height: CGFloat(raster.height)))
    let bytes = try #require(bitmap.data)
    let data = Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.height)
    #expect(data.contains { $0 != 0 }) // The fixture must produce visible pixels.
    return "\(raster.width)x\(raster.height):\(goalMemoDrawingDataDigest(data))"
}

private func goalMemoDrawingValidateBounds(_ bounds: CGRect) {
    #expect(bounds.origin.x.isFinite && bounds.origin.y.isFinite)
    #expect(bounds.width.isFinite && bounds.height.isFinite)
    #expect(bounds.width > 0 && bounds.height > 0)
}

/// Quantized SDK value digest: fixed seeds/dates/points remain comparable when
/// an archive restores floating-point components at framework precision.
/// This is a geometry/ink correctness check, not a cryptographic archive ID.
@MainActor
private func goalMemoDrawingValueDigest(_ drawing: PKDrawing) -> String {
    func number(_ value: Double) -> String { String(Int64((value * 1_000).rounded())) }
    let strokes = drawing.strokes.map { stroke in
        let color = stroke.ink.color.usingColorSpace(.sRGB) ?? stroke.ink.color
        let transform = stroke.transform
        let header = [
            stroke.ink.inkType.rawValue, String(stroke.randomSeed),
            number(Double(color.redComponent)), number(Double(color.greenComponent)), number(Double(color.blueComponent)), number(Double(color.alphaComponent)),
            number(Double(transform.a)), number(Double(transform.b)), number(Double(transform.c)), number(Double(transform.d)), number(Double(transform.tx)), number(Double(transform.ty)),
            number(stroke.path.creationDate.timeIntervalSince1970)
        ].joined(separator: ",")
        let points = stroke.path.map { point in
            [Double(point.location.x), Double(point.location.y), point.timeOffset, Double(point.size.width), Double(point.size.height),
             Double(point.opacity), Double(point.force), Double(point.azimuth), Double(point.altitude)].map { number($0) }.joined(separator: ",")
        }.joined(separator: ";")
        return "\(header)|\(points)"
    }.joined(separator: "\n")
    return goalMemoDrawingDataDigest(Data(strokes.utf8))
}

@MainActor
private func goalMemoDrawingSamples<Output>(
    name: String, details: String, count: Int, expectedDigest: String,
    operation: () throws -> Output, validate: (Output) throws -> String
) throws {
    #expect(try validate(operation()) == expectedDigest) // One untimed warm-up.
    var samples: [Double] = []
    for _ in 0..<count {
        // Drain framework temporaries between samples without timing pool teardown.
        try autoreleasepool {
            let start = DispatchTime.now().uptimeNanoseconds
            let output = try operation()
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            #expect(try validate(output) == expectedDigest)
        }
    }
    let sorted = samples.sorted()
    let median = count.isMultiple(of: 2) ? (sorted[count / 2 - 1] + sorted[count / 2]) / 2 : sorted[count / 2]
    let p95Index = min(count - 1, Int(ceil(Double(count) * 0.95)) - 1)
    print("GOAL_MEMO_DRAWING_BENCHMARK name=\(name) \(details) unit=ms n=\(count) warmup=1 operationsPerSample=1 p50=\(median) p95=\(sorted[p95Index]) max=\(sorted[count - 1]) outputDigest=\(expectedDigest) samples=\(samples)")
}

private func goalMemoDrawingDataDigest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
#endif
