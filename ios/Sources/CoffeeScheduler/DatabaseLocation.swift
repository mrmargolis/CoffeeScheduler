import Foundation

/// Keeps the database in a folder the user picked in iCloud Drive.
///
/// SQLite works on a local working copy in Application Support. On launch and
/// when the app returns to the foreground, a newer `coffee.db` in the iCloud
/// folder is copied in; after every change the working copy is copied back out.
/// Both copies go through NSFileCoordinator, which is what lets iCloud Drive
/// download an evicted file first and keeps it from syncing a half-written one.
///
/// Each copy has two halves. The working copy is read and written here, on
/// the main actor, where SQLite is too, so it is never read part way through
/// a write. The iCloud file is read and written off the main actor
/// (`CloudFile`), since a coordinated read waits for a download.
///
/// A folder picked through the document picker needs no iCloud entitlement, so
/// this works with xtool, which can't provision iCloud containers, and with a
/// free Apple ID.
@MainActor
final class DatabaseLocation {
    static let fileName = "coffee.db"
    static let backupFileName = "coffee.backup.db"

    private let defaults: UserDefaults
    private let bookmarkKey = "databaseFolderBookmark"
    private let syncedDateKey = "databaseLastSyncedRemoteDate"

    /// The local copy SQLite opens.
    let workingCopy: URL

    /// Where the local copy lives, for code that only reads it.
    static var workingCopyURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    /// The picked folder, if any. Access to it is held open for the app's lifetime.
    private(set) var folder: URL?
    private var isScoped = false

    /// Counts the changes made to the working copy, to tell when one lands
    /// while the iCloud file is being fetched.
    private var changes = 0
    private var needsPush = false

    var remoteFile: URL? { folder?.appendingPathComponent(Self.fileName) }

    /// The defaults and the working copy are parameters for the tests.
    init(defaults: UserDefaults = .standard, workingCopy: URL = DatabaseLocation.workingCopyURL) {
        self.defaults = defaults
        self.workingCopy = workingCopy
        guard let data = defaults.data(forKey: bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return }
        guard open(url) else { return }
        if stale { saveBookmark(for: url) }
    }

    /// Adopt a folder returned by the document picker. The caller then pulls
    /// the folder's `coffee.db` (from another device) if it has one, and
    /// pushes the working copy into it if not.
    func adopt(folder url: URL) throws {
        let previous = isScoped ? folder : nil
        guard open(url) else {
            throw LocationError("Couldn't get access to that folder.")
        }
        previous?.stopAccessingSecurityScopedResource()
        saveBookmark(for: url)
        defaults.removeObject(forKey: syncedDateKey)
        needsPush = true
    }

    var hasRemoteFile: Bool { remoteModificationDate() != nil }

    /// Say that the working copy has changed and is to be pushed.
    func workingCopyChanged() {
        changes += 1
        needsPush = true
    }

    /// Copy the iCloud file over the working copy if it changed since we last
    /// synced. `close` is called just before the working copy is replaced:
    /// SQLite must let go of the file first. Returns true when it was replaced.
    ///
    /// The working copy is left alone if it changed while the iCloud file was
    /// being fetched. That change is pushed next and wins, as a change made
    /// here always has.
    @discardableResult
    func pullIfNewer(closing close: () -> Void) async throws -> Bool {
        guard let remote = remoteFile, let remoteDate = remoteModificationDate() else { return false }
        if let synced = defaults.object(forKey: syncedDateKey) as? Date, remoteDate <= synced {
            return false
        }

        let before = changes
        let data = try await CloudFile.read(remote)
        guard changes == before else { return false }

        close()
        try data.write(to: workingCopy, options: .atomic)
        defaults.set(remoteModificationDate() ?? remoteDate, forKey: syncedDateKey)
        return true
    }

    /// Copy the working copy out to the iCloud folder, if it has changed
    /// since it was last copied there.
    func push() async throws {
        guard needsPush, let remote = remoteFile,
            FileManager.default.fileExists(atPath: workingCopy.path)
        else { return }

        needsPush = false
        do {
            try await CloudFile.write(try Data(contentsOf: workingCopy), to: remote)
        } catch {
            needsPush = true
            throw error
        }
        defaults.set(remoteModificationDate() ?? Date(), forKey: syncedDateKey)
    }

    /// Keep a copy of the working copy beside the database in the iCloud
    /// folder, replacing the last one. Taken before an import, so the data
    /// as it was can be put back from Files by renaming the copy.
    func backUp() async throws {
        guard let backup = folder?.appendingPathComponent(Self.backupFileName),
            FileManager.default.fileExists(atPath: workingCopy.path)
        else { return }

        try await CloudFile.write(try Data(contentsOf: workingCopy), to: backup)
    }

    /// Take `url` as the folder. A folder from the document picker is
    /// security-scoped; one that isn't only has to be readable.
    private func open(_ url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        guard scoped || FileManager.default.isReadableFile(atPath: url.path) else { return false }
        folder = url
        isScoped = scoped
        return true
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
}

/// The iCloud Drive side of a copy, off the main actor: a coordinated read
/// waits for iCloud to download a file it has evicted, which can take as long
/// as the network does.
private enum CloudFile {
    @concurrent
    static func read(_ url: URL) async throws -> Data {
        var coordinatorError: NSError?
        var result: Result<Data, any Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinatorError { throw coordinatorError }
        guard let result else { throw LocationError("Couldn't read \(url.lastPathComponent).") }
        return try result.get()
    }

    /// Small file, so a whole-file atomic write is simplest: it writes a temp
    /// file beside the destination and renames it into place.
    @concurrent
    static func write(_ data: Data, to url: URL) async throws {
        var coordinatorError: NSError?
        var bodyError: (any Error)?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { url in
            do { try data.write(to: url, options: .atomic) } catch { bodyError = error }
        }
        if let error = coordinatorError ?? bodyError { throw error }
    }
}

struct LocationError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
