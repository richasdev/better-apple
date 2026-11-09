import Foundation
import CoreAudio
import IOKit.ps

struct SystemEventNotice: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case lowBattery, audioOutput }
    let kind: Kind
    let name: String
    let symbol: String
    let detail: String
    let percentage: Int?
}

/// Initial state is silent. A low battery announces once per discharge, and an
/// actual change of default output announces once per device identity.
struct SystemNoticeLedger {
    private var initializedPower = false
    private var lowBatteryAnnounced = false
    private var outputInitialized = false
    private var outputID: AudioDeviceID?

    mutating func power(percentage: Int?, onBattery: Bool) -> SystemEventNotice? {
        guard let percentage, (0...100).contains(percentage) else { return nil }
        let low = onBattery && percentage <= 20
        if !initializedPower {
            initializedPower = true
            lowBatteryAnnounced = low
            return nil
        }
        guard low else { lowBatteryAnnounced = false; return nil }
        guard !lowBatteryAnnounced else { return nil }
        lowBatteryAnnounced = true
        return SystemEventNotice(kind: .lowBattery, name: "Low Battery", symbol: "battery.25percent",
                                 detail: "\(percentage)%", percentage: percentage)
    }

    mutating func output(id: AudioDeviceID?, name: String?, bluetooth: Bool) -> SystemEventNotice? {
        guard outputInitialized else { outputInitialized = true; outputID = id; return nil }
        guard id != outputID else { return nil }
        outputID = id
        guard id != nil else { return nil }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = trimmed.isEmpty ? "Audio output" : String(trimmed.prefix(100))
        return SystemEventNotice(kind: .audioOutput, name: title,
                                 symbol: Self.outputSymbol(name: title, bluetooth: bluetooth),
                                 detail: "Audio output", percentage: nil)
    }

    static func outputSymbol(name: String, bluetooth: Bool) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        return bluetooth ? "headphones" : "hifispeaker.fill"
    }
}

/// Public notification sources only. No audio capture, microphone access,
/// Bluetooth scanning, private AirPods data, periodic timer or Focus inspection.
@MainActor
final class SystemEventNoticeService {
    var onNotice: ((SystemEventNotice) -> Void)?
    private(set) var isRunning = false
    private var ledger = SystemNoticeLedger()
    private var generation = UUID()
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var powerSource: CFRunLoopSource?
    private var powerBridge: SystemNoticeWeakBridge?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        generation = UUID()
        ledger = SystemNoticeLedger()
        consumePower()
        consumeOutput()

        let token = generation
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.generation == token else { return }
                self.consumeOutput()
            }
        }
        var address = Self.outputAddress
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener) == noErr {
            outputListener = listener
        }

        let bridge = SystemNoticeWeakBridge(owner: self)
        let context = Unmanaged.passUnretained(bridge).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let bridge = Unmanaged<SystemNoticeWeakBridge>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak bridge] in bridge?.owner?.consumePower() }
        }, context)?.takeRetainedValue() {
            powerBridge = bridge
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    func stop() {
        isRunning = false
        generation = UUID()
        if let listener = outputListener {
            var address = Self.outputAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
        }
        outputListener = nil
        if let powerSource { CFRunLoopSourceInvalidate(powerSource) }
        powerSource = nil
        powerBridge = nil
        ledger = SystemNoticeLedger()
    }

    fileprivate func consumePower() {
        guard isRunning else { return }
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Double,
                  let maximum = description[kIOPSMaxCapacityKey] as? Double,
                  current.isFinite, maximum.isFinite, maximum > 0 else { continue }
            let percentage = Int((min(1, max(0, current / maximum)) * 100).rounded(.down))
            let onBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            if let event = ledger.power(percentage: percentage, onBattery: onBattery) { onNotice?(event) }
            break
        }
    }

    private func consumeOutput() {
        guard isRunning else { return }
        var address = Self.outputAddress
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return }
        guard device != 0 else {
            _ = ledger.output(id: nil, name: nil, bluetooth: false)
            return
        }
        var name: Unmanaged<CFString>?
        address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let named = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr
        // kAudioObjectPropertyName returns an owned CFObject (AudioHardwareBase.h).
        let outputName = named ? name?.takeRetainedValue() as String? : nil
        var transport = UInt32(0)
        address.mSelector = kAudioDevicePropertyTransportType
        size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
        let bluetooth = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
        if let event = ledger.output(id: device, name: outputName, bluetooth: bluetooth) { onNotice?(event) }
    }

    private static var outputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    deinit {
        if let listener = outputListener {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
        }
        if let powerSource { CFRunLoopSourceInvalidate(powerSource) }
    }
}

private final class SystemNoticeWeakBridge: @unchecked Sendable {
    weak var owner: SystemEventNoticeService?
    init(owner: SystemEventNoticeService) { self.owner = owner }
}
