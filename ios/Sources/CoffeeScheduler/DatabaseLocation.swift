import Foundation

/// Keeps the database in a folder the user picked in iCloud Drive.
///
/// SQLite works on a local working copy in Application Support. On launch and
/// when the app returns to the foreground, a newer `coffee.db` in the iCloud
/// folder is copied in; after every change the working copy is copied back out.
/// Both copies go through NSFileCoordinator, which is what lets iCloud Drive
/// download an evicted file first and keeps it from syncing a half-written one.
///
/// A folder picked through the document picker needs no iCloud entitlement, so
/// this works with xtool, which can't provision iCloud containers, and with a
/// free Apple ID.
@MainActor
final class DatabaseLocation {
    static let fileName = "coffee.db"

    private let defaults = UserDefaults.standard
    private let bookmarkKey = "databaseFolderBookmark"
    private let syncedDateKey = "databaseLastSyncedRemoteDate"

    /// The local copy SQLite opens.
    let workingCopy: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(DatabaseLocation.fileName)
    }()

    /// The picked folder, if any. Access to it is held open for the app's lifetime.
    private(set) var folder: URL?

    var remoteFile: URL? { folder?.appendingPathComponent(Self.fileName) }

    init() {
        guard let data = defaults.data(forKey: bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        folder = url
        if stale { saveBookmark(for: url) }
    }

    /// Adopt a folder returned by the document picker. If the folder already
    /// holds a `coffee.db` (from another device or the web app) it replaces the
    /// working copy; otherwise the working copy is copied into the folder.
    func choose(folder url: URL) throws {
        folder?.stopAccessingSecurityScopedResource()
        guard url.startAccessingSecurityScopedResource() else {
            throw LocationError("Couldn't get access to that folder.")
        }
        folder = url
        saveBookmark(for: url)
        defaults.removeObject(forKey: syncedDateKey)

        if remoteModificationDate() != nil {
            try pullIfNewer()
        } else {
            try push()
        }
    }

    /// Copy the iCloud file over the working copy if it changed since we last
    /// synced. The caller must close the database first. Returns true when the
    /// working copy was replaced.
    @discardableResult
    func pullIfNewer() throws -> Bool {
        guard let remote = remoteFile, let remoteDate = remoteModificationDate() else { return false }
        if let synced = defaults.object(forKey: syncedDateKey) as? Date, remoteDate <= synced {
            return false
        }

        try coordinate(reading: remote) { source in
            try Self.copy(source, over: self.workingCopy)
        }
        defaults.set(remoteModificationDate() ?? remoteDate, forKey: syncedDateKey)
        return true
    }

    /// Copy the working copy out to the iCloud folder.
    func push() throws {
        guard let remote = remoteFile,
              FileManager.default.fileExists(atPath: workingCopy.path)
        else { return }

        try coordinate(writing: remote) { destination in
            try Self.copy(self.workingCopy, over: destination)
        }
        defaults.set(remoteModificationDate() ?? Date(), forKey: syncedDateKey)
    }

    private func remoteModificationDate() -> Date? {
        guard var url = remoteFile else { return nil }
        // Ask for fresh values: iCloud may have changed the file since the last read.
        url.removeAllCachedResourceValues()
        return try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func saveBookmark(for url: URL) {
        if let data = try? url.bookmarkData() {
            defaults.set(data, forKey: bookmarkKey)
        }
    }

    /// Small file, so a whole-file atomic write is simplest: it writes a temp
    /// file beside the destination and renames it into place.
    private static func copy(_ source: URL, over destination: URL) throws {
        try Data(contentsOf: source).write(to: destination, options: .atomic)
    }

    private func coordinate(reading url: URL, _ body: (URL) throws -> Void) throws {
        var coordinatorError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { url in
            do { try body(url) } catch { bodyError = error }
        }
        if let error = coordinatorError ?? bodyError { throw error }
    }

    private func coordinate(writing url: URL, _ body: (URL) throws -> Void) throws {
        var coordinatorError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { url in
            do { try body(url) } catch { bodyError = error }
        }
        if let error = coordinatorError ?? bodyError { throw error }
    }
}

struct LocationError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
