import Foundation
import Testing
@testable import EasyTaskCore

/// Explicit build-76 algorithms allow paired measurements on the same machine.
/// This measures text projection CPU time, not rendered frames or launch latency.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_OPTIMIZATION_PERFORMANCE"] == "1"))
func optimizationMemoTextProjection() {
    let content = "긴 메모 제목\n" + String(repeating: "본문 내용을 확인합니다.\n", count: 10_000)
    let cases: [(String, () -> String)] = [
        ("build76-memo-title", {
            content.split(whereSeparator: \Character.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? MemoRules.emptyTitle
        }),
        ("current-memo-title", { MemoRules.displayTitle(for: content) }),
        ("build76-memo-preview", {
            let lines = content.split(whereSeparator: \Character.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let remaining = lines.dropFirst()
            return (remaining.isEmpty ? lines : Array(remaining)).joined(separator: " ")
        }),
        ("current-memo-preview", { MemoRules.preview(for: content) }),
    ]
    for (name, operation) in cases {
        _ = operation()
        var samples: [Double] = []
        var outputBytes = 0
        for _ in 0..<30 {
            let start = DispatchTime.now().uptimeNanoseconds
            let output = operation()
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            outputBytes = output.utf8.count
        }
        let sorted = samples.sorted()
        print("OPTIMIZATION_BENCHMARK name=\(name) unit=ms inputBytes=\(content.utf8.count) outputBytes=\(outputBytes) n=30 p50=\(sorted[15]) p95=\(sorted[28]) samples=\(samples)")
        #expect(outputBytes > 0)
    }
}
