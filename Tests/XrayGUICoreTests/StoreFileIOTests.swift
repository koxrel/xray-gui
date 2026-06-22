import Testing
import Foundation
@testable import XrayGUICore

/// Tests for Store persistence (file I/O) using a per-test temporary directory.
///
/// CRITICAL: these tests must NEVER use the live app-support path. `Store` now
/// takes an injectable `directory:`, so each test runs against a throwaway temp
/// dir. A previous version exercised the real `~/Library/Application Support/
/// XrayGUI/` path with a backup/restore dance — a crash or kill mid-run left the
/// user's data clobbered. Isolated temp dirs make that impossible.
@Suite("Store File I/O Tests", .serialized)
struct StoreFileIOTests {

    /// Runs `body` against a Store rooted at a fresh temp directory, removed after.
    private func withCleanStore(_ body: (Store, _ storeURL: URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xray-store-io-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = Store(directory: dir)
        let storeURL = dir.appendingPathComponent("xray-gui-data.json")
        try body(store, storeURL)
    }

    // MARK: - Load

    @Test("load() returns default StoreData when file does not exist")
    func loadReturnsDefaultWhenMissing() throws {
        try withCleanStore { store, storeURL in
            // Ensure no file exists
            try? FileManager.default.removeItem(at: storeURL)

            let data = store.load()
            #expect(data.servers.isEmpty)
            #expect(data.subscriptions.isEmpty)
            #expect(data.tunnels.isEmpty)
            #expect(data.settings.httpPort == 1087)
        }
    }

    @Test("load() merges zero-value httpPort with default 1087")
    func loadMergesZeroHttpPort() throws {
        try withCleanStore { store, storeURL in
            // Write JSON with httpPort=0
            let json = """
            {"settings": {"httpPort": 0, "socksPort": 0, "dnsServers": []}}
            """
            try json.write(to: storeURL, atomically: true, encoding: .utf8)

            let data = store.load()
            #expect(data.settings.httpPort == 1087)
            #expect(data.settings.socksPort == 1080)
        }
    }

    @Test("load() merges empty dnsServers with defaults")
    func loadMergesEmptyDnsServers() throws {
        try withCleanStore { store, storeURL in
            let json = """
            {"settings": {"httpPort": 1087, "socksPort": 1080, "dnsServers": []}}
            """
            try json.write(to: storeURL, atomically: true, encoding: .utf8)

            let data = store.load()
            #expect(!data.settings.dnsServers.isEmpty)
        }
    }

    @Test("load() merges empty bypassDomains with defaults")
    func loadMergesEmptyBypassDomains() throws {
        try withCleanStore { store, storeURL in
            let json = """
            {"settings": {"httpPort": 1087, "socksPort": 1080, "dnsServers": ["1.1.1.1"], "bypassDomains": []}}
            """
            try json.write(to: storeURL, atomically: true, encoding: .utf8)

            let data = store.load()
            #expect(!data.settings.bypassDomains.isEmpty)
        }
    }

    @Test("load() returns default and backs up corrupted file")
    func loadHandlesCorruptedFile() throws {
        try withCleanStore { store, storeURL in
            let corruptJson = "{ this is NOT valid JSON at all {{{"
            try corruptJson.write(to: storeURL, atomically: true, encoding: .utf8)

            let data = store.load()

            // Returns defaults
            #expect(data.servers.isEmpty)
            #expect(data.settings.httpPort == 1087)

            // Backup file should have been created
            let backupURL = storeURL.deletingPathExtension().appendingPathExtension("corrupted.json")
            let backupExists = FileManager.default.fileExists(atPath: backupURL.path)
            #expect(backupExists == true)

            // Original file should no longer exist (moved to backup)
            #expect(!FileManager.default.fileExists(atPath: storeURL.path))
        }
    }

    // MARK: - Save + Load Round-trip

    @Test("save then load returns same data")
    func saveLoadRoundTrip() throws {
        try withCleanStore { store, _ in
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
        try withCleanStore { store, storeURL in
            var data = StoreData()
            _ = store.addServer(&data, server: ServerConfig(name: "JSON", address: "json.com", uuid: "j"))
            // addServer calls save internally

            #expect(FileManager.default.fileExists(atPath: storeURL.path))

            let rawData = try Data(contentsOf: storeURL)
            let parsed = try JSONSerialization.jsonObject(with: rawData) as? [String: Any]
            #expect(parsed?["servers"] != nil)
            #expect(parsed?["settings"] != nil)
        }
    }

    @Test("save() overwrites existing file atomically")
    func saveOverwrites() throws {
        try withCleanStore { store, _ in
            var data = StoreData()
            _ = store.addServer(&data, server: ServerConfig(name: "First", address: "first.com", uuid: "f"))
            // Second save overwrites
            _ = store.addServer(&data, server: ServerConfig(name: "Second", address: "second.com", uuid: "s"))

            let loaded = store.load()
            #expect(loaded.servers.count == 2)
        }
    }
}
