import Foundation
import SQLite3
import SwiftData

/// The SwiftData store lives in an App Group so the Share extension and the app see the same trips.
enum SharedStore {
    static let appGroup = "group.com.kingway.tripple"
    private static let storeName = "default.store"
    private static let changeKey = "lastExternalChange"

    static let schema = Schema([
        Trip.self, Place.self, SavedLink.self, Expense.self,
        Hotel.self, HotelAttachment.self, Flight.self, Ticket.self, PackingItem.self,
    ])

    /// False on the free-account build (no App Group): the share sheet and widgets can't see the app's trips.
    static var isAppGroupAvailable: Bool { groupDirectory != nil }

    private static var groupDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }

    /// - Parameter cleanUp: pass `true` only when the app launches (nothing else has the store open yet).
    static func makeContainer(cleanUp: Bool = false) throws -> ModelContainer {
        guard let directory = groupDirectory else {
            // No App Group available (e.g. signing not set up): fall back to the app's own store.
            return try ModelContainer(for: schema)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        moveOldStoreIfNeeded(to: directory)
        if cleanUp {
            removeOldStore(movedTo: directory)
            compactIfRequested(directory.appending(path: storeName))
            clearTemporaryFiles()
        }
        let config = ModelConfiguration(schema: schema, url: directory.appending(path: storeName))
        return try ModelContainer(for: schema, configurations: config)
    }

    /// One-time move of data saved before the App Group existed, so existing trips aren't lost.
    private static func moveOldStoreIfNeeded(to directory: URL) {
        let fm = FileManager.default
        let newStore = directory.appending(path: storeName)
        guard !fm.fileExists(atPath: newStore.path(percentEncoded: false)) else { return }
        let oldDirectory = URL.applicationSupportDirectory
        let oldStore = oldDirectory.appending(path: storeName)
        guard oldDirectory != directory, fm.fileExists(atPath: oldStore.path(percentEncoded: false)) else { return }
        // Let SQLite copy the store so recent changes still in its write-ahead log come along.
        guard sqliteBackup(from: oldStore, to: newStore) else {
            for suffix in ["", "-shm", "-wal", "-journal"] {
                try? fm.removeItem(at: directory.appending(path: storeName + suffix))
            }
            return
        }
        // Large attachments (photos, PDFs) are kept in a folder beside the store.
        let support = ".default_SUPPORT"
        let from = oldDirectory.appending(path: support)
        let to = directory.appending(path: support)
        if fm.fileExists(atPath: from.path(percentEncoded: false)), !fm.fileExists(atPath: to.path(percentEncoded: false)) {
            try? fm.copyItem(at: from, to: to)
        }
    }

    // MARK: - Cleanup

    /// After data has moved to the App Group, the old copy in the app's own folder is no longer used: delete it.
    private static func removeOldStore(movedTo directory: URL) {
        let fm = FileManager.default
        let oldDirectory = URL.applicationSupportDirectory
        guard oldDirectory != directory,
              fm.fileExists(atPath: directory.appending(path: storeName).path(percentEncoded: false)) else { return }
        for name in [storeName, "\(storeName)-shm", "\(storeName)-wal", ".default_SUPPORT"] {
            let url = oldDirectory.appending(path: name)
            if fm.fileExists(atPath: url.path(percentEncoded: false)) { try? fm.removeItem(at: url) }
        }
    }

    private static let compactKey = "needsCompaction"

    /// Call after deleting trips: the database is shrunk the next time the app starts.
    static func requestCompaction() {
        defaults?.set(true, forKey: compactKey)
    }

    /// Shrinks the database file so space freed by deleted trips is given back to the iPhone.
    private static func compactIfRequested(_ store: URL) {
        guard defaults?.bool(forKey: compactKey) == true,
              FileManager.default.fileExists(atPath: store.path(percentEncoded: false)) else { return }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(store.path(percentEncoded: false), &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return }
        sqlite3_busy_timeout(db, 2000)
        // Fold the write-ahead log into the main file, then rebuild it without empty space.
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
        if sqlite3_exec(db, "VACUUM;", nil, nil, nil) == SQLITE_OK {
            defaults?.removeObject(forKey: compactKey)
        }
    }

    /// Removes temporary copies of boarding passes / PDFs made for previewing.
    private static func clearTemporaryFiles() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        for url in (try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: url)
        }
    }

    /// Copies a whole SQLite database (including un-checkpointed WAL changes) using SQLite's backup API.
    private static func sqliteBackup(from source: URL, to destination: URL) -> Bool {
        var src: OpaquePointer?
        var dst: OpaquePointer?
        defer {
            sqlite3_close(src)
            sqlite3_close(dst)
        }
        guard sqlite3_open_v2(source.path(percentEncoded: false), &src, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              sqlite3_open_v2(destination.path(percentEncoded: false), &dst, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let backup = sqlite3_backup_init(dst, "main", src, "main") else { return false }
        let step = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        return step == SQLITE_DONE && finish == SQLITE_OK
    }

    // MARK: - Change signal between the extension and the app

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Called by the Share extension after it saves, so the app knows to reload.
    static func markChanged() {
        defaults?.set(Date.now.timeIntervalSince1970, forKey: changeKey)
    }

    static var lastExternalChange: Double {
        defaults?.double(forKey: changeKey) ?? 0
    }
}

enum LinkExtractor {
    /// Pulls the first web link out of text (shared posts often include a caption).
    static func firstURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let matches = detector.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
        return matches.compactMap(\.url).first { $0.scheme == "http" || $0.scheme == "https" }
    }
}
