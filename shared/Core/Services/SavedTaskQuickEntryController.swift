import Foundation
import Observation
import SwiftData

@MainActor @Observable
public final class SavedTaskQuickEntryController {
    public private(set) var entries: [SavedTaskEntry] = []
    public private(set) var input = ""
    public private(set) var isPresented = false
    public private(set) var highlightedID: UUID?
    public private(set) var failure: String?

    public init() {}

    public var suggestions: [SavedTaskEntry] { SavedTaskShortcutRules.suggestions(entries, input: input) }

    public func update(_ text: String, in context: ModelContext) {
        let wasCommand = SavedTaskShortcutRules.query(in: input) != nil
        let changed = input != text
        input = text
        guard SavedTaskShortcutRules.query(in: text) != nil else {
            isPresented = false; highlightedID = nil; failure = nil; entries = []
            return
        }
        if changed { highlightedID = nil; failure = nil; isPresented = true }
        if !wasCommand { refresh(in: context) }
    }

    public func refresh(in context: ModelContext) {
        guard SavedTaskShortcutRules.query(in: input) != nil else { return }
        do {
            entries = try SavedTaskLibraryService.load(in: context)
            if !suggestions.contains(where: { $0.id == highlightedID }) { highlightedID = nil }
        } catch { failure = error.localizedDescription }
    }

    public func moveSelection(by offset: Int) -> Bool {
        guard isPresented else { return false }
        let values = suggestions
        guard !values.isEmpty else { return true }
        let current = values.firstIndex { $0.id == highlightedID }
        let next = current.map { min(max($0 + offset, 0), values.count - 1) }
            ?? (offset > 0 ? 0 : values.count - 1)
        highlightedID = values[next].id
        return true
    }

    public func dismiss() -> Bool {
        guard isPresented else { return false }
        isPresented = false; highlightedID = nil
        return true
    }

    /// Resolve again at submission so changed/deleted aliases never create a stale or unrelated task.
    public func add(input text: String, selectedID: UUID? = nil, on date: Date, in context: ModelContext) -> Task? {
        update(text, in: context)
        do {
            entries = try SavedTaskLibraryService.load(in: context)
            let id: UUID
            if let selected = selectedID ?? highlightedID {
                guard suggestions.contains(where: { $0.id == selected }) else { throw SavedTaskLibraryService.Failure.unavailable }
                id = selected
            } else {
                id = try SavedTaskShortcutRules.exactMatch(in: entries, input: text)
            }
            let task = try SavedTaskLibraryService.add(id: id, on: date, in: context)
            update("", in: context)
            return task
        } catch {
            failure = error.localizedDescription
            isPresented = true
            return nil
        }
    }
}
