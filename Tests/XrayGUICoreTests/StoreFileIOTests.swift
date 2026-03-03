import Testing
import Foundation
@testable import XrayGUICore

/// Tests for Store persistence (file I/O) using a temporary directory,
/// so tests don't touch ~/Library/Application Support/XrayGUI/.
///
/// Strategy: Store uses a hardcoded path derived from FileManager's
/// applicationSupportDirectory. Since we can't inject the path in the current
/// design, these tests exercise the real file path and clean up after themselves.
/// The tests are marked as mutually isolated so they don't step on each other.
@Suite("Store File I/O Tests", .serialized)
struct StoreFileIOTests {

    /// The real path Store writes to.
    private static let storeURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("XrayGUI", isDirectory: true)
            .appendingPathComponent("xray-gui-data.json")
    }()

    /// Backup any existing store file before each test and restore after.
    private func withCleanStore(_ body: (Store) throws -> Void) throws {
        let url = Self.storeURL
        let backupURL = url.deletingPathExtension().appendingPathExtension("test-backup.json")

        // Back up existing file, replacing any stale backup from a previous run
        if FileManager.default.fileExists(atPath: url.path) {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.copyItem(at: url, to: backupURL)
        }

        defer {
            // Restore original file or remove the test-written one
            try? FileManager.default.removeItem(at: url)
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try? FileManager.default.moveItem(at: backupURL, to: url)
            }
        }

        let store = Store()
        try body(store)
    }

    // MARK: - Load

    @Test("load() returns default StoreData when file does not exist")
    func loadReturnsDefaultWhenMissing() throws {
        try withCleanStore { store in
            // Ensure no file exists
            try? FileManager.default.removeItem(at: Self.storeURL)

            let data = store.load()
            #expect(data.servers.isEmpty)
            #expect(data.subscriptions.isEmpty)
            #expect(data.tunnels.isEmpty)
            #expect(data.settings.httpPort == 1087)
        }
    }

    @Test("load() merges zero-value httpPort with default 1087")
    func loadMergesZeroHttpPort() throws {
        try withCleanStore { store in
            // Write JSON with httpPort=0
            let json = """
            {"settings": {"httpPort": 0, "socksPort": 0, "dnsServers": []}}
            """
            try json.write(to: Self.storeURL, atomically: true, encoding: .utf8)

            let data = store.load()
            #expect(data.settings.httpPort == 1087)
            #expect(data.settings.socksPort == 1080)
        }
    }

    @Test("load() merges empty dnsServers with defaults")
    func loadMergesEmptyDnsServers() throws {
        try withCleanStore { store in
            let json = """
            {"settings": {"httpPort": 1087, "socksPort": 1080, "dnsServers": []}}
            """
            try json.write(to: Self.storeURL, atomically: true, encoding: .utf8)

            let data = store.load()
            #expect(!data.settings.dnsServers.isEmpty)
        }
    }

    @Test("load() merges empty bypassDomains with defaults")
    func loadMergesEmptyBypassDomains() throws {
        try withCleanStore { store in
            let json = """
            {"settings": {"httpPort": 1087, "socksPort": 1080, "dnsServers": ["1.1.1.1"], "bypassDomains": []}}
            """
            try json.write(to: Self.storeURL, atomically: true, encoding: .utf8)

            let data = store.load()
            #expect(!data.settings.bypassDomains.isEmpty)
        }
    }

    @Test("load() returns default and backs up corrupted file")
    func loadHandlesCorruptedFile() throws {
        try withCleanStore { store in
            let corruptJson = "{ this is NOT valid JSON at all {{{"
            try corruptJson.write(to: Self.storeURL, atomically: true, encoding: .utf8)

            let data = store.load()

            // Returns defaults
            #expect(data.servers.isEmpty)
            #expect(data.settings.httpPort == 1087)

            // Backup file should have been created
            let backupURL = Self.storeURL.deletingPathExtension().appendingPathExtension("corrupted.json")
            let backupExists = FileManager.default.fileExists(atPath: backupURL.path)
            defer { try? FileManager.default.removeItem(at: backupURL) }
            #expect(backupExists == true)

            // Original file should no longer exist (moved to backup)
            #expect(!FileManager.default.fileExists(atPath: Self.storeURL.path))
        }
    }

    // MARK: - Save + Load Round-trip

    @Test("save then load returns same data")
    func saveLoadRoundTrip() throws {
        try withCleanStore { store in
            var data = StoreData()
            let server = store.addServer(&data, server: ServerConfig(name: "RoundTrip", address: "rt.com", uuid: "rt-uuid"))
            _ = store.addSubscription(&data, name: "MySub", url: "https://sub.example.com")
            store.setActiveServer(&data, id: server.id)

            // addServer and addSubscription already call save internally
            let loaded = store.load()

            #expect(loaded.servers.count == 1)
            #expect(loaded.servers[0].address == "rt.com")
            #expect(loaded.subscriptions.count == 1)
            #expect(loaded.settings.activeServerId == server.id)
        }
    }

    @Test("save() writes valid JSON to disk")
    func saveWritesValidJson() throws {
        try withCleanStore { store in
            var data = StoreData()
            _ = store.addServer(&data, server: ServerConfig(name: "JSON", address: "json.com", uuid: "j"))
            // addServer calls save internally

            #expect(FileManager.default.fileExists(atPath: Self.storeURL.path))

            let rawData = try Data(contentsOf: Self.storeURL)
            let parsed = try JSONSerialization.jsonObject(with: rawData) as? [String: Any]
            #expect(parsed?["servers"] != nil)
            #expect(parsed?["settings"] != nil)
        }
    }

    @Test("save() overwrites existing file atomically")
    func saveOverwrites() throws {
        try withCleanStore { store in
            var data = StoreData()
            _ = store.addServer(&data, server: ServerConfig(name: "First", address: "first.com", uuid: "f"))
            // Second save overwrites
            _ = store.addServer(&data, server: ServerConfig(name: "Second", address: "second.com", uuid: "s"))

            let loaded = store.load()
            #expect(loaded.servers.count == 2)
        }
    }
}
