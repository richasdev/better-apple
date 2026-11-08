import AppKit
import Combine
import CoreAudio
import Darwin
import IOKit.ps

/// Sampling exists only while a visible system surface has subscribed through start().
@MainActor
final class SystemStatusService: ObservableObject {
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var memoryUsedBytes: UInt64 = 0
    @Published private(set) var memoryTotalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var batteryLevel: Double?
    @Published private(set) var isCharging = false
    @Published private(set) var outputVolume: Double?
    @Published private(set) var networkBytesPerSecond: Double = 0
    private var timer: Timer?
    private let sampler = SystemSampler()
    private let queue = DispatchQueue(label: "app.betterapple.system", qos: .utility)
    private var generation = 0
    private var busy = false

    func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        timer.tolerance = 0.6
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        generation += 1
        busy = false
        queue.async { [sampler] in sampler.reset() }
    }

    func setOutputVolume(_ value: Double) {
        guard value.isFinite else { return }
        let value = min(1, max(0, value))
        queue.async { [weak self] in
            let actual = SystemSampler.setVolume(value)
            Task { @MainActor in self?.outputVolume = actual }
        }
    }

    private func sample() {
        guard !busy else { return }
        busy = true
        let current = generation
        queue.async { [weak self, sampler] in
            let snapshot = sampler.read()
            Task { @MainActor in
                guard let self, current == self.generation else { return }
                self.busy = false
                self.cpuUsage = snapshot.cpu
                self.memoryUsedBytes = snapshot.memory
                self.batteryLevel = snapshot.battery
                self.isCharging = snapshot.charging
                self.outputVolume = snapshot.volume
                self.networkBytesPerSecond = snapshot.network
            }
        }
    }

    deinit { timer?.invalidate() }
}

private struct SystemSnapshot {
    var cpu: Double = 0
    var memory: UInt64 = 0
    var battery: Double?
    var charging = false
    var volume: Double?
    var network: Double = 0
}

/// All mutable sampler state is confined to one serial utility queue.
private final class SystemSampler: @unchecked Sendable {
    private var previousCPU: [UInt32]?
    private var previousNetwork: (bytes: UInt64, time: TimeInterval)?
    func reset() { previousCPU = nil; previousNetwork = nil }

    func read() -> SystemSnapshot {
        var result = SystemSnapshot()
        var cpu = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let cpuStatus = withUnsafeMutablePointer(to: &cpu) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if cpuStatus == KERN_SUCCESS {
            let ticks = [cpu.cpu_ticks.0, cpu.cpu_ticks.1, cpu.cpu_ticks.2, cpu.cpu_ticks.3]
            if let previousCPU {
                let delta = zip(ticks, previousCPU).map { UInt64($0 &- $1) }
                let total = delta.reduce(0, +)
                if total > 0 { result.cpu = min(1, max(0, 1 - Double(delta[Int(CPU_STATE_IDLE)]) / Double(total))) }
            }
            previousCPU = ticks
        }

        var memory = vm_statistics64()
        var memoryCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let memoryStatus = withUnsafeMutablePointer(to: &memory) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(memoryCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &memoryCount)
            }
        }
        if memoryStatus == KERN_SUCCESS {
            let pages = UInt64(memory.active_count) + UInt64(memory.wire_count) + UInt64(memory.compressor_page_count)
            result.memory = min(ProcessInfo.processInfo.physicalMemory, pages * UInt64(vm_kernel_page_size))
        }
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let current = description[kIOPSCurrentCapacityKey] as? Double,
                      let maximum = description[kIOPSMaxCapacityKey] as? Double, maximum > 0 else { continue }
                result.battery = min(1, max(0, current / maximum))
                result.charging = description[kIOPSIsChargingKey] as? Bool ?? false
                break
            }
        }
        result.volume = Self.volume()
        let now = ProcessInfo.processInfo.systemUptime
        if let bytes = Self.networkBytes() {
            if let previous = previousNetwork, now > previous.time, bytes >= previous.bytes {
                result.network = Double(bytes - previous.bytes) / (now - previous.time)
            }
            previousNetwork = (bytes, now)
        }
        return result
    }

    private static func networkBytes() -> UInt64? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(first) }
        var total: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let interface = entry.pointee
            if interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               interface.ifa_flags & UInt32(IFF_UP) != 0,
               interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
               let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                total += UInt64(data.pointee.ifi_ibytes) + UInt64(data.pointee.ifi_obytes)
            }
            cursor = interface.ifa_next
        }
        return total
    }

    private static func outputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != 0 else { return nil }
        return device
    }

    private static func volumeElements(_ device: AudioDeviceID) -> [AudioObjectPropertyElement] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &address) { return [kAudioObjectPropertyElementMain] }
        return [1, 2].filter { element in
            address.mElement = element
            return AudioObjectHasProperty(device, &address)
        }
    }

    static func volume() -> Double? {
        guard let device = outputDevice() else { return nil }
        let values: [Double] = volumeElements(device).compactMap { element in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
            return Double(value)
        }
        guard !values.isEmpty else { return nil }
        return min(1, max(0, values.reduce(0, +) / Double(values.count)))
    }

    static func setVolume(_ value: Double) -> Double? {
        guard let device = outputDevice() else { return nil }
        for element in volumeElements(device) {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var writable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &writable) == noErr, writable.boolValue else { continue }
            var scalar = Float32(value)
            _ = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar)
        }
        return volume()
    }
}
