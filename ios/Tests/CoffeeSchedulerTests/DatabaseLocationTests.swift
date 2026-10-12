import Foundation
import Testing

@testable import CoffeeScheduler

/// The copies to and from iCloud Drive, with a temporary folder standing in
/// for the one the user picks and text standing in for the database.
@MainActor
struct DatabaseLocationTests {
    private let workingCopy: URL
    private let folder: URL
    private let defaults: UserDefaults

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        folder = root.appendingPathComponent("Coffee")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        workingCopy = root.appendingPathComponent("working.db")
        defaults = try #require(UserDefaults(suiteName: "DatabaseLocationTests-\(UUID().uuidString)"))
    }

    private var remote: URL { folder.appendingPathComponent(DatabaseLocation.fileName) }

    private func location() -> DatabaseLocation {
        DatabaseLocation(defaults: defaults, workingCopy: workingCopy)
    }

    private func write(_ text: String, to url: URL, secondsFromNow: TimeInterval = 0) throws {
        try Data(text.utf8).write(to: url)
        let date = Date().addingTimeInterval(secondsFromNow)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func text(at url: URL) throws -> String {
        try #require(String(bytes: try Data(contentsOf: url), encoding: .utf8))
    }

    @Test func anEmptyFolderIsGivenTheWorkingCopy() async throws {
        try write("local", to: workingCopy)
        let location = location()
        try location.adopt(folder: folder)
        #expect(!location.hasRemoteFile)

        try await location.push()

        #expect(try text(at: remote) == "local")
        // What was just pushed is not pulled back
        #expect(try await location.pullIfNewer {} == false)
    }

    @Test func aFolderWithADatabaseReplacesTheWorkingCopy() async throws {
        try write("local", to: workingCopy)
        try write("from another device", to: remote)
        let location = location()
        try location.adopt(folder: folder)
        #expect(location.hasRemoteFile)

        var closed = false
        let pulled = try await location.pullIfNewer { closed = true }

        #expect(pulled)
        #expect(closed)
        #expect(try text(at: workingCopy) == "from another device")
        #expect(try await location.pullIfNewer {} == false)
    }

    @Test func aLaterChangeInTheFolderIsPulled() async throws {
        try write("first", to: remote)
        let location = location()
        try location.adopt(folder: folder)
        try await location.pullIfNewer {}

        try write("second", to: remote, secondsFromNow: 60)

        #expect(try await location.pullIfNewer {})
        #expect(try text(at: workingCopy) == "second")
    }

    @Test func theWorkingCopyIsPushedOnlyWhenItHasChanged() async throws {
        try write("one", to: workingCopy)
        let location = location()
        try location.adopt(folder: folder)
        try await location.push()

        try write("two", to: workingCopy)
        try await location.push()
        #expect(try text(at: remote) == "one")

        location.workingCopyChanged()
        try await location.push()
        #expect(try text(at: remote) == "two")
    }

    @Test func aChangeMadeDuringAPullIsKept() async throws {
        try write("first", to: remote)
        let location = location()
        try location.adopt(folder: folder)
        try await location.pullIfNewer {}
        try write("from another device", to: remote, secondsFromNow: 60)

        // The pull runs as far as its fetch, which waits off the main actor;
        // the change here lands before the fetched copy comes back
        let pull = Task { try await location.pullIfNewer {} }
        await Task.yield()
        try write("changed here", to: workingCopy)
        location.workingCopyChanged()

        #expect(try await pull.value == false)
        #expect(try text(at: workingCopy) == "changed here")

        try await location.push()
        #expect(try text(at: remote) == "changed here")
    }

    @Test func aBackupSitsBesideTheDatabase() async throws {
        try write("remote", to: remote)
        try write("local", to: workingCopy)
        let location = location()
        try location.adopt(folder: folder)

        try await location.backUp()

        #expect(try text(at: folder.appendingPathComponent(DatabaseLocation.backupFileName)) == "local")
        #expect(try text(at: remote) == "remote")
    }

    @Test func theFolderIsRememberedByTheNextLaunch() async throws {
        try write("local", to: workingCopy)
        try location().adopt(folder: folder)

        let relaunched = location()

        #expect(relaunched.folder?.lastPathComponent == "Coffee")
    }

    @Test func aFolderThatIsNotThereIsRefused() throws {
        let location = location()
        #expect(throws: LocationError.self) {
            try location.adopt(folder: folder.appendingPathComponent("missing"))
        }
        #expect(location.folder == nil)
    }

    @Test func nothingIsCopiedWithoutAFolder() async throws {
        try write("local", to: workingCopy)
        let location = location()
        location.workingCopyChanged()

        try await location.push()
        try await location.backUp()

        #expect(try await location.pullIfNewer {} == false)
        #expect(try text(at: workingCopy) == "local")
    }
}
