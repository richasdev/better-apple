import Foundation
import AppKit
import IOBluetooth

@main struct BluetoothSmoke {
    @MainActor static func main() {
        // No start(): this harness never touches the Bluetooth adapter or asks for TCC.
        let service = BluetoothConnectionService()
        service.stop(); service.stop()
        assert(!service.isRunning)
        var ledger = BluetoothConnectionLedger()
        ledger.seed(["existing", "existing"])
        assert(!ledger.connect("existing"), "Startup devices must remain silent")
        assert(ledger.disconnect("existing"))
        assert(!ledger.disconnect("existing"))
        assert(ledger.connect("existing"), "A reconnect must emit once")
        assert(!ledger.connect("existing"))
        assert(ledger.connect("second"))
        ledger.reset()
        assert(ledger.connectedIDs.isEmpty)
        let cases: [(String?, BluetoothDeviceClassMajor, String)] = [
            ("My AirPods Pro", 4, "airpodspro"), ("AirPods Max", 4, "airpodsmax"),
            ("AirPods", 4, "airpods"), ("Headset", 4, "headphones"),
            ("Keyboard", 5, "keyboard"), ("Phone", 2, "iphone"),
            ("Laptop", 1, "laptopcomputer"), (nil, 0, "wave.3.right")
        ]
        for (name, deviceClass, symbol) in cases {
            let event = BluetoothConnectionService.presentation(name: name, majorClass: deviceClass, connected: true)
            assert(event.symbol == symbol && event.connected)
            assert(NSImage(systemSymbolName: event.symbol, accessibilityDescription: nil) != nil)
        }
        let empty = BluetoothConnectionService.presentation(name: "  \n", majorClass: 0, connected: false)
        assert(empty.name == "Bluetooth device" && !empty.connected)
        let long = BluetoothConnectionService.presentation(name: String(repeating: "a", count: 1000), majorClass: 0, connected: true)
        assert(long.name.count == 100)
        print("PASS: Bluetooth baseline silence, duplicate/reconnect ledger, reset, passive stop, AirPods/class symbols and safe naming; hardware subscription deliberately not started")
    }
}
