import Foundation
import SwiftUI
import AppKit
import XrayGUICore

@Observable
@MainActor
final class AppState {
    // MARK: - Coordinator
    let coordinator: ProxyCoordinator

    // MARK: - Shared UI Ticker
    //
    // Single coalesced 1Hz clock that any visible view can subscribe to. Used by
    // DashboardView (uptime display) and StatisticsView (stats refresh trigger).
    // Refcounted by `reason` — when no view is interested, the timer is fully
    // torn down so the process can idle. Suspended while the system is asleep.
    private(set) var uiTick: Date = Date()
    @ObservationIgnored private var uiTickInterests: Set<String> = []
    @ObservationIgnored private var uiTickTimer: DispatchSourceTimer?
    @ObservationIgnored private var systemAsleep = false

    func beginUITicking(reason: String) {
        guard !uiTickInterests.contains(reason) else { return }
        uiTickInterests.insert(reason)
        refreshUITickTimer()
    }

    func endUITicking(reason: String) {
        guard uiTickInterests.contains(reason) else { return }
        uiTickInterests.remove(reason)
        refreshUITickTimer()
    }

    func handleSystemWillSleep() {
        systemAsleep = true
        refreshUITickTimer()
    }

    func handleSystemDidWake() {
        systemAsleep = false
        refreshUITickTimer()
        // Force one immediate tick so any subscribed view re-renders on wake
        // without waiting up to a full second for the next scheduled fire.
        if !uiTickInterests.isEmpty {
            uiTick = Date()
        }
    }

    private func refreshUITickTimer() {
        let shouldTick = !uiTickInterests.isEmpty && !systemAsleep
        if shouldTick, uiTickTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(
                deadline: .now() + .seconds(1),
                repeating: .seconds(1),
                leeway: .milliseconds(200)
            )
            timer.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.uiTick = Date()
                }
            }
            timer.resume()
            uiTickTimer = timer
        } else if !shouldTick, let timer = uiTickTimer {
            timer.cancel()
            uiTickTimer = nil
        }
    }

    // MARK: - Forwarded State
    var servers: [ServerConfig] {
        get { coordinator.servers }
        set { coordinator.servers = newValue }
    }

    var subscriptions: [Subscription] {
        get { coordinator.subscriptions }
        set { coordinator.subscriptions = newValue }
    }

    var settings: AppSettings {
        get { coordinator.settings }
        set { coordinator.settings = newValue }
    }

    var proxyStatus: ProxyStatus {
        get { coordinator.proxyStatus }
        set { coordinator.proxyStatus = newValue }
    }

    var tunnels: [Tunnel] {
        get { coordinator.tunnels }
        set { coordinator.tunnels = newValue }
    }

    var logs: [String] {
        get { coordinator.logs }
        set { coordinator.logs = newValue }
    }

    var tunnelStatistics: [TunnelStatisticsSnapshot] {
        coordinator.tunnelStatistics
    }

    var tunnelStatisticsSummary: TunnelStatisticsSummary {
        coordinator.tunnelStatisticsSummary
    }

    var isLoading: Bool {
        get { coordinator.isLoading }
        set { coordinator.isLoading = newValue }
    }

    // MARK: - Services (forwarded for app delegate access)
    var xrayManager: any XrayManaging { coordinator.xrayManager }
    var proxyManager: any ProxyManaging { coordinator.proxyManager }

    // MARK: - Init

    /// DI initializer for testing
    init(coordinator: ProxyCoordinator) {
        self.coordinator = coordinator
        coordinator.loadData()
        coordinator.setupLogCallback()
    }

    /// Convenience initializer with default dependencies
    convenience init() {
        let store = Store()
        let xrayManager = XrayManager()
        let proxyManager = DefaultProxyManager()
        let coordinator = ProxyCoordinator(store: store, xrayManager: xrayManager, proxyManager: proxyManager)
        self.init(coordinator: coordinator)
    }

    // MARK: - Data Loading

    func loadData() {
        coordinator.loadData()
    }

    // MARK: - Auto Start

    func performAutoStartIfNeeded() async {
        await coordinator.performAutoStartIfNeeded()
    }

    // MARK: - Server Methods

    func addServer(_ server: ServerConfig) {
        coordinator.addServer(server)
    }

    func updateServer(_ server: ServerConfig) {
        coordinator.updateServer(server)
    }

    func deleteServer(_ id: String) {
        coordinator.deleteServer(id)
    }

    func setActiveServer(_ id: String?) {
        coordinator.setActiveServer(id)
    }

    func testLatency(_ serverId: String) async {
        await coordinator.testLatency(serverId)
    }

    func testAllLatency() async {
        await coordinator.testAllLatency()
    }

    func importServerUrl(_ urlString: String) -> ServerConfig? {
        coordinator.importServerUrl(urlString)
    }

    func importFromClipboard() -> [ServerConfig] {
        guard let clipboardString = NSPasteboard.general.string(forType: .string) else { return [] }
        let lines = clipboardString.components(separatedBy: .newlines)
        var imported: [ServerConfig] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("vless://"), let parsed = SubscriptionManager.parseVlessUrl(trimmed) {
                let server = coordinator.withStoreData { self.coordinator.store.addServer(&$0, server: parsed) }
                imported.append(server)
            }
        }
        return imported
    }

    // MARK: - Subscription Methods

    func addSubscription(name: String, url: String) async {
        await coordinator.addSubscription(name: name, url: url)
    }

    func updateSubscription(_ id: String) async {
        await coordinator.updateSubscription(id)
    }

    func updateAllSubscriptions() async -> (success: Int, failed: Int) {
        await coordinator.updateAllSubscriptions()
    }

    func deleteSubscription(_ id: String) {
        coordinator.deleteSubscription(id)
    }

    // MARK: - Proxy Control

    func startProxy() async throws {
        try await coordinator.startProxy()
    }

    func startProxy(server: ServerConfig) async throws {
        try await coordinator.startProxy(server: server)
    }

    func stopProxy() async throws {
        try await coordinator.stopProxy()
    }

    func setProxyMode(_ mode: ProxyMode) async {
        await coordinator.setProxyMode(mode)
    }

    // MARK: - Settings

    func updateSettings(_ update: (inout AppSettings) -> Void) async {
        await coordinator.updateSettings(update)
    }

    // MARK: - Logs

    func appendLog(_ message: String) {
        coordinator.appendLog(message)
    }

    func clearLogs() {
        coordinator.clearLogs()
    }

    // MARK: - Multi-Tunnel

    func addTunnel(serverId: String, httpPort: Int? = nil, socksPort: Int? = nil) async throws -> Tunnel {
        try await coordinator.addTunnel(serverId: serverId, httpPort: httpPort, socksPort: socksPort)
    }

    func updateTunnelPorts(_ tunnelId: String, httpPort: Int, socksPort: Int) async throws {
        try await coordinator.updateTunnelPorts(tunnelId, httpPort: httpPort, socksPort: socksPort)
    }

    func pauseTunnel(_ tunnelId: String) async {
        await coordinator.pauseTunnel(tunnelId)
    }

    func resumeTunnel(_ tunnelId: String) async throws {
        try await coordinator.resumeTunnel(tunnelId)
    }

    func resumeAllTunnels() async {
        await coordinator.resumeAllTunnels()
    }

    func removeTunnel(_ tunnelId: String) async {
        await coordinator.removeTunnel(tunnelId)
    }

    func pauseAllTunnels() async {
        await coordinator.pauseAllTunnels()
    }

    func stopAllTunnels() async {
        await coordinator.stopAllTunnels()
    }

    var hasPausedTunnels: Bool {
        coordinator.hasPausedTunnels
    }

    func nextAvailablePortsPreview() -> (http: Int, socks: Int) {
        coordinator.nextAvailablePortsPreview()
    }

    func refreshTunnelStatistics(now: Date = Date()) async {
        await coordinator.refreshTunnelStatistics(now: now)
    }

    // MARK: - Shell Export

    var shellExportString: String {
        coordinator.shellExportString
    }

    func copyShellExport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shellExportString, forType: .string)
    }

    // MARK: - Cleanup

    func cleanup() async {
        await coordinator.cleanup()
    }
}
