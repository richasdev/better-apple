import Foundation
import IOBluetooth

struct BluetoothConnectionEvent: Equatable, Sendable {
    let name: String
    let connected: Bool
    let symbol: String
}

/// Baseline connections are remembered silently. Repeated transport notifications do not
/// become repeated banners; a real disconnect allows the next connection through.
struct BluetoothConnectionLedger {
    private(set) var connectedIDs = Set<String>()
    mutating func seed(_ ids: [String]) { connectedIDs.formUnion(ids) }
    mutating func connect(_ id: String) -> Bool { connectedIDs.insert(id).inserted }
    mutating func disconnect(_ id: String) -> Bool { connectedIDs.remove(id) != nil }
    mutating func reset() { connectedIDs.removeAll() }
}

/// Passive Classic Bluetooth baseband notifications only: no inquiry, pairing, name
/// requests or undocumented AirPods battery protocol. BLE-only peripherals may not
/// produce these events. Permission is controlled by macOS, not bypassed by this service.
@MainActor
final class BluetoothConnectionService: NSObject {
    var onEvent: ((BluetoothConnectionEvent) -> Void)?
    private(set) var isRunning = false
    private var connectionNotification: IOBluetoothUserNotification?
    private var disconnections: [String: IOBluetoothUserNotification] = [:]
    private var ledger = BluetoothConnectionLedger()
    private lazy var receiver = BluetoothNotificationReceiver(owner: self)

    @discardableResult func start() -> Bool {
        guard !isRunning else { return true }
        guard let notification = IOBluetoothDevice.register(forConnectNotifications: receiver,
            selector: #selector(BluetoothNotificationReceiver.connected(_:device:))) else { return false }
        connectionNotification = notification
        isRunning = true
        // Initial devices are not new connections. Register disconnect observers so
        // existing headphones can later disconnect/reconnect with the same semantics.
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] where device.isConnected() {
            guard let id = device.addressString, !id.isEmpty else { continue }
            ledger.seed([id])
            observeDisconnection(device, id: id)
        }
        return true
    }

    func stop() {
        isRunning = false
        connectionNotification?.unregister()
        connectionNotification = nil
        disconnections.values.forEach { $0.unregister() }
        disconnections.removeAll()
        ledger.reset()
    }

    fileprivate func didConnect(_ device: IOBluetoothDevice, notification: IOBluetoothUserNotification) {
        guard isRunning, notification === connectionNotification,
              let id = device.addressString, !id.isEmpty else { return }
        let isNew = ledger.connect(id)
        observeDisconnection(device, id: id)
        if isNew { onEvent?(Self.presentation(name: device.name, majorClass: device.deviceClassMajor, connected: true)) }
    }

    fileprivate func didDisconnect(_ device: IOBluetoothDevice, notification: IOBluetoothUserNotification) {
        guard isRunning, let id = device.addressString, !id.isEmpty,
              notification === disconnections[id] else { return }
        disconnections.removeValue(forKey: id)?.unregister()
        if ledger.disconnect(id) {
            onEvent?(Self.presentation(name: device.name, majorClass: device.deviceClassMajor, connected: false))
        }
    }

    private func observeDisconnection(_ device: IOBluetoothDevice, id: String) {
        guard disconnections[id] == nil else { return }
        if let notification = device.register(forDisconnectNotification: receiver,
            selector: #selector(BluetoothNotificationReceiver.disconnected(_:device:))) {
            disconnections[id] = notification
        }
    }

    nonisolated static func presentation(name: String?, majorClass: BluetoothDeviceClassMajor, connected: Bool) -> BluetoothConnectionEvent {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = trimmed.isEmpty ? "Bluetooth device" : String(trimmed.prefix(100))
        let normalized = title.lowercased()
        let symbol: String
        if normalized.contains("airpods max") { symbol = "airpodsmax" }
        else if normalized.contains("airpods pro") { symbol = "airpodspro" }
        else if normalized.contains("airpods") { symbol = "airpods" }
        else {
            switch majorClass {
            case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio): symbol = "headphones"
            case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPeripheral): symbol = "keyboard"
            case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorComputer): symbol = "laptopcomputer"
            case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPhone): symbol = "iphone"
            default: symbol = "wave.3.right"
            }
        }
        return BluetoothConnectionEvent(name: title, connected: connected, symbol: symbol)
    }

    deinit {
        connectionNotification?.unregister()
        disconnections.values.forEach { $0.unregister() }
    }
}

/// IOBluetooth owns its notification target until unregister. This weak bridge prevents
/// that ownership from retaining the feature or its application coordinator indefinitely.
private final class BluetoothNotificationReceiver: NSObject {
    weak var owner: BluetoothConnectionService?
    init(owner: BluetoothConnectionService) { self.owner = owner }
    @objc func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        Task { @MainActor [weak owner] in owner?.didConnect(device, notification: notification) }
    }
    @objc func disconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        Task { @MainActor [weak owner] in owner?.didDisconnect(device, notification: notification) }
    }
}
