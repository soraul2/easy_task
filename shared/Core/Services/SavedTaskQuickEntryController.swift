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

    @ObservationIgnored private(set) var preparedAliasKeys: [UUID: String] = [:]
    @ObservationIgnored private let loadLibrary: @MainActor (ModelContext) throws -> [SavedTaskEntry]
    @ObservationIgnored private var localeObserver: SavedTaskLocaleObserver?

    public init() {
        loadLibrary = { try SavedTaskLibraryService.load(in: $0) }
        observeLocaleChanges()
    }

    init(loadLibrary: @escaping @MainActor (ModelContext) throws -> [SavedTaskEntry]) {
        self.loadLibrary = loadLibrary
        observeLocaleChanges()
    }

    public private(set) var suggestions: [SavedTaskEntry] = []

    public func update(_ text: String, in context: ModelContext) {
        let wasCommand = SavedTaskShortcutRules.query(in: input) != nil
        let changed = input != text
        input = text
        guard SavedTaskShortcutRules.query(in: text) != nil else {
            isPresented = false; highlightedID = nil; failure = nil; entries = []; suggestions = []
            preparedAliasKeys = [:]
            return
        }
        if changed { highlightedID = nil; failure = nil; isPresented = true }
        if !wasCommand { refresh(in: context) }
        else if changed { updateSuggestions() }
    }

    public func refresh(in context: ModelContext) {
        guard SavedTaskShortcutRules.query(in: input) != nil else { return }
        do {
            try reloadLibrary(in: context)
            if !suggestions.contains(where: { $0.id == highlightedID }) { highlightedID = nil }
        } catch { failure = error.localizedDescription }
    }

    /// Only a completed import can introduce remote library changes. Local
    /// template notifications and submission still resolve the latest contents.
    public func refresh(after summary: CloudKitSyncEventSummary, in context: ModelContext) {
        guard CloudKitSyncService.shouldReconcile(after: summary) else { return }
        refresh(in: context)
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
            try reloadLibrary(in: context)
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

    private func updateSuggestions() {
        suggestions = SavedTaskShortcutRules.suggestions(entries, input: input, preparedAliasKeys: preparedAliasKeys)
    }

    private func reloadLibrary(in context: ModelContext) throws {
        let values = try loadLibrary(context)
        let keys = SavedTaskShortcutRules.aliasKeys(in: values)
        entries = values
        preparedAliasKeys = keys
        updateSuggestions()
    }

    private func observeLocaleChanges() {
        localeObserver = SavedTaskLocaleObserver(NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Swift.Task { @MainActor [weak self] in
                guard let self else { return }
                updateSuggestions()
                if !suggestions.contains(where: { $0.id == highlightedID }) { highlightedID = nil }
            }
        })
    }
}

private final class SavedTaskLocaleObserver: @unchecked Sendable {
    private let token: any NSObjectProtocol
    init(_ token: any NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}
