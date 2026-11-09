// Pure transition checks: no hardware subscriptions, playback or power changes.
import Foundation

@main
struct SystemNoticeSmoke {
    @MainActor static func main() {
        var count = 0
        func check(_ value: Bool) { precondition(value); count += 1 }
        var ledger = SystemNoticeLedger()
        check(ledger.power(percentage: 60, onBattery: true) == nil)
        check(ledger.power(percentage: 21, onBattery: true) == nil)
        let low = ledger.power(percentage: 20, onBattery: true)
        check(low?.kind == .lowBattery && low?.percentage == 20 && low?.detail == "20%")
        check(ledger.power(percentage: 19, onBattery: true) == nil)
        check(ledger.power(percentage: 4, onBattery: true) == nil)
        check(ledger.power(percentage: 4, onBattery: false) == nil)
        check(ledger.power(percentage: 4, onBattery: true)?.percentage == 4)
        check(ledger.power(percentage: 60, onBattery: true) == nil)
        check(ledger.power(percentage: 18, onBattery: true)?.percentage == 18)
        check(ledger.power(percentage: nil, onBattery: true) == nil)
        check(ledger.power(percentage: -1, onBattery: true) == nil)
        check(ledger.power(percentage: 101, onBattery: true) == nil)
        var initialLow = SystemNoticeLedger()
        check(initialLow.power(percentage: 10, onBattery: true) == nil)
        check(initialLow.power(percentage: 9, onBattery: true) == nil)
        check(initialLow.power(percentage: 80, onBattery: false) == nil)
        check(initialLow.power(percentage: 20, onBattery: true) != nil)

        check(ledger.output(id: 1, name: "Speakers", bluetooth: false) == nil)
        check(ledger.output(id: 1, name: "Speakers", bluetooth: false) == nil)
        let switched = ledger.output(id: 2, name: "AirPods Pro", bluetooth: true)
        check(switched?.kind == .audioOutput && switched?.name == "AirPods Pro" && switched?.symbol == "airpodspro" && switched?.percentage == nil)
        check(ledger.output(id: 2, name: "AirPods Pro", bluetooth: true) == nil)
        check(ledger.output(id: nil, name: nil, bluetooth: false) == nil)
        check(ledger.output(id: 2, name: "AirPods Pro", bluetooth: true) != nil)
        check(ledger.output(id: 3, name: "   ", bluetooth: false)?.name == "Audio output")
        check(ledger.output(id: 4, name: String(repeating: "x", count: 200), bluetooth: false)?.name.count == 100)
        check(SystemNoticeLedger.outputSymbol(name: "AIRPODS MAX", bluetooth: true) == "airpodsmax")
        check(SystemNoticeLedger.outputSymbol(name: "AirPods", bluetooth: true) == "airpods")
        check(SystemNoticeLedger.outputSymbol(name: "Headset", bluetooth: true) == "headphones")
        check(SystemNoticeLedger.outputSymbol(name: "Display", bluetooth: false) == "hifispeaker.fill")
        let service = SystemEventNoticeService()
        check(!service.isRunning)
        service.stop()
        service.stop()
        check(!service.isRunning)
        print("PASS: \(count) system-notice ledger and passive teardown checks; no CoreAudio/IOPS listeners started.")
    }
}
