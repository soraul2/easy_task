import Foundation
import Observation
import SwiftData

@MainActor @Observable
@available(watchOS 11, *)
public final class SavedTaskQuickEntryController {
    public private(set) var entries: [SavedTaskEntry] = []
    public private(set) var input = ""
    public private(set) var isPresented = false
    public private(set) var highlightedID: UUID?
    public private(set) var failure: String?

    @ObservationIgnored private(set) var preparedAliasKeys: [UUID: String] = [:]
    @ObservationIgnored private let loadLibrary: @MainActor (ModelContext) throws -> [SavedTaskEntry]
    @ObservationIgnored private var localeObserver: SavedTaskLocaleObserver?
    @ObservationIgnored private weak var libraryContext: ModelContext?
    @ObservationIgnored private var libraryRevision: PersistenceViewRevision?
    @ObservationIgnored private var cachedLibrary: LibrarySnapshot?

    private struct LibrarySnapshot {
        var entries: [SavedTaskEntry]
        var aliasKeys: [UUID: String]
        var revision: Int
    }

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
        let changed = updateInput(text)
        guard SavedTaskShortcutRules.query(in: text) != nil else { return }
        let changedContext = bindLibraryContext(context)
        if !wasCommand || changedContext { prepareLibraryForEntry(in: context) }
        else if changed { updateSuggestions() }
    }

    public func refresh(in context: ModelContext) {
        // An invalidation received while typing an ordinary title must also make
        // the next command entry read the latest library.
        cachedLibrary = nil
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
        // Submission resolves the current matching records independently of the
        // display cache. Successful submission does not rebuild the full list.
        _ = updateInput(text)
        do {
            guard SavedTaskShortcutRules.query(in: text) != nil else {
                throw SavedTaskShortcutRules.Failure.selectionRequired
            }
            let task = try SavedTaskLibraryService.add(input: text,
                selectedID: selectedID ?? highlightedID, on: date, in: context)
            update("", in: context)
            return task
        } catch {
            // Keep the current choices visible on failure, but retain the
            // original submission error if refreshing the display also fails.
            if SavedTaskShortcutRules.query(in: text) != nil {
                try? reloadLibrary(in: context)
            }
            failure = error.localizedDescription
            isPresented = true
            return nil
        }
    }

    private func updateSuggestions() {
        suggestions = SavedTaskShortcutRules.suggestions(entries, input: input, preparedAliasKeys: preparedAliasKeys)
    }

    private func updateInput(_ text: String) -> Bool {
        let changed = input != text
        input = text
        guard SavedTaskShortcutRules.query(in: text) != nil else {
            isPresented = false; highlightedID = nil; failure = nil; entries = []; suggestions = []
            preparedAliasKeys = [:]
            return changed
        }
        if changed { highlightedID = nil; failure = nil; isPresented = true }
        return changed
    }

    @discardableResult
    private func bindLibraryContext(_ context: ModelContext) -> Bool {
        guard libraryContext !== context else { return false }
        libraryContext = context
        // This observes direct saves/autosaves, template commands and completed
        // successful imports even while the board or command picker is hidden.
        libraryRevision = PersistenceViewRevision(context: context, domains: .templates)
        cachedLibrary = nil
        return true
    }

    private func prepareLibraryForEntry(in context: ModelContext) {
        if let cachedLibrary, cachedLibrary.revision == libraryRevision?.value, !context.hasChanges {
            entries = cachedLibrary.entries
            preparedAliasKeys = cachedLibrary.aliasKeys
            // Localized title ranking is recomputed using the current locale.
            updateSuggestions()
        } else {
            refresh(in: context)
        }
    }

    private func reloadLibrary(in context: ModelContext) throws {
        bindLibraryContext(context)
        // Never keep an old snapshot reusable after a failed mandatory read.
        cachedLibrary = nil
        let values = try loadLibrary(context)
        let keys = SavedTaskShortcutRules.aliasKeys(in: values)
        entries = values
        preparedAliasKeys = keys
        // Pending values may later be rolled back without a save notification.
        // They are displayed now, but cannot populate the reusable snapshot.
        if !context.hasChanges, let revision = libraryRevision?.value {
            cachedLibrary = LibrarySnapshot(entries: values, aliasKeys: keys, revision: revision)
        }
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

@available(watchOS 11, *)
private final class SavedTaskLocaleObserver: @unchecked Sendable {
    private let token: any NSObjectProtocol
    init(_ token: any NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}
