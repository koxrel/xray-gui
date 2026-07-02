import Foundation

public protocol Storing: Sendable {
    func load() -> StoreData
    func save(_ data: StoreData)
    func configFileURL(for tunnelId: String) -> URL
    func removeConfigFile(for tunnelId: String)

    @discardableResult func addServer(_ data: inout StoreData, server: ServerConfig) -> ServerConfig
    @discardableResult func updateServer(_ data: inout StoreData, server: ServerConfig) -> ServerConfig
    func deleteServer(_ data: inout StoreData, id: String)
    func setActiveServer(_ data: inout StoreData, id: String?)
    func setServerLatency(_ data: inout StoreData, id: String, latency: Int)

    func addSubscription(_ data: inout StoreData, name: String, url: String) -> Subscription
    func updateSubscription(_ data: inout StoreData, subscription: Subscription)
    func deleteSubscription(_ data: inout StoreData, id: String)
    func addServersForSubscription(_ data: inout StoreData, subscriptionId: String, servers: [ServerConfig]) -> [String]
    func removeServersForSubscription(_ data: inout StoreData, subscriptionId: String)
    /// Reconciles a subscription's servers against freshly parsed content while preserving
    /// the `id`, `isActive`, and `latency` of servers that still exist (matched by
    /// `ServerConfig.identityKey`). Returns the ids of the subscription's servers after reconciliation.
    @discardableResult
    func reconcileServersForSubscription(_ data: inout StoreData, subscriptionId: String, servers: [ServerConfig]) -> [String]

    @discardableResult func updateSettingsTyped(_ data: inout StoreData, _ update: (inout AppSettings) -> Void) -> AppSettings
}
