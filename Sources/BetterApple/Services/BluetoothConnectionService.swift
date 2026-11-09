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
    private var generation = UUID()
    private let transport = BluetoothConnectionTransport()

    @discardableResult func start() -> Bool {
        guard !isRunning else { return true }
        isRunning = true
        let token = UUID()
        generation = token
        transport.start { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.generation == token else { return }
                self.onEvent?(event)
            }
        }
        return true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation = UUID()
        transport.stop()
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

    deinit { transport.stop() }
}

/// Framework initialization may synchronously wait for CoreBluetooth. Keep it off
/// the main actor, and serialize registration, callbacks and teardown. Invalidated
/// generations cannot deliver a late event after the user disables the feature.
private final class BluetoothConnectionTransport: NSObject, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.betterapple.bluetooth", qos: .utility)
    private var connection: IOBluetoothUserNotification?
    private var disconnections: [String: IOBluetoothUserNotification] = [:]
    private var ledger = BluetoothConnectionLedger()
    private var callback: (@Sendable (BluetoothConnectionEvent) -> Void)?

    func start(_ callback: @escaping @Sendable (BluetoothConnectionEvent) -> Void) {
        queue.async { [self] in
            guard connection == nil else { return }
            self.callback = callback
            connection = IOBluetoothDevice.register(forConnectNotifications: self,
                selector: #selector(connected(_:device:)))
            for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] where device.isConnected() {
                guard let id = device.addressString, !id.isEmpty else { continue }
                ledger.seed([id])
                observeDisconnection(device, id: id)
            }
        }
    }

    func stop() {
        queue.async { [self] in
            connection?.unregister()
            connection = nil
            disconnections.values.forEach { $0.unregister() }
            disconnections.removeAll()
            ledger.reset()
            callback = nil
        }
    }

    @objc private func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        queue.async { [self] in
            guard notification === connection, let id = device.addressString, !id.isEmpty else { return }
            let isNew = ledger.connect(id)
            observeDisconnection(device, id: id)
            if isNew { callback?(BluetoothConnectionService.presentation(name: device.name, majorClass: device.deviceClassMajor, connected: true)) }
        }
    }

    @objc private func disconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        queue.async { [self] in
            guard let id = device.addressString, !id.isEmpty, notification === disconnections[id] else { return }
            disconnections.removeValue(forKey: id)?.unregister()
            if ledger.disconnect(id) { callback?(BluetoothConnectionService.presentation(name: device.name, majorClass: device.deviceClassMajor, connected: false)) }
        }
    }

    private func observeDisconnection(_ device: IOBluetoothDevice, id: String) {
        guard disconnections[id] == nil else { return }
        disconnections[id] = device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
    }
}
