import Foundation

/// This adapter never contacts System Events or changes the user's native Dock.
private actor FakeNativeDockAccess: NativeDockPreferenceAccess {
    private var value: Bool
    private let defaults: UserDefaults
    private var failReads = false
    private var failWrites = false
    private var ignoreWrites = false
    private var delay: UInt64 = 0
    private(set) var writes: [Bool] = []
    private(set) var reads = 0
    private(set) var baselinesAtWrite: [Bool?] = []
    init(value: Bool, defaults: UserDefaults) { self.value = value; self.defaults = defaults }
    func configure(failReads: Bool = false, failWrites: Bool = false, ignoreWrites: Bool = false, delay: UInt64 = 0) {
        self.failReads = failReads; self.failWrites = failWrites; self.ignoreWrites = ignoreWrites; self.delay = delay
    }
    func readAutohide() async throws -> Bool {
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        reads += 1
        if failReads { throw NativeDockError.denied }
        return value
    }
    func writeAutohide(_ value: Bool) async throws {
        writes.append(value)
        baselinesAtWrite.append(defaults.object(forKey: "nativeDock.previousAutohide") as? Bool)
        if failWrites { throw NativeDockError.denied }
        if !ignoreWrites { self.value = value }
    }
    func current() -> Bool { value }
}

@main struct NativeDockSmoke {
    @MainActor static func main() async throws {
        let name = "app.betterapple.native-dock-smoke.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var count = 0
        func check(_ condition: Bool, _ label: String) {
            guard condition else { fatalError(label) }
            count += 1
        }
        func clear() { defaults.removePersistentDomain(forName: name) }
        let access = FakeNativeDockAccess(value: false, defaults: defaults)
        let service = NativeDockService(defaults: defaults, access: access)
        var activations = 0
        service.onActivate = { activations += 1 }
        await service.activateIfRequested()
        check(await access.reads == 0 && !service.desiredEnabled && !service.isActive, "A fresh installation must not request Automation")
        check(await service.restoreForTermination(), "Quitting without replacement must need no restoration")
        let readsBeforeChoice = await access.reads
        let writesBeforeChoice = await access.writes
        check(readsBeforeChoice == 0 && writesBeforeChoice.isEmpty, "Ordinary quit must not contact System Events without prior choice")
        try await service.setEnabled(true)
        check(service.desiredEnabled && service.isActive && !service.isBusy && activations == 1, "Activation must commit and call onActivate only after verification")
        check(await access.current(), "Activation must enable autohide")
        check(await access.baselinesAtWrite.first! == false, "The original false setting must be persisted before the first write")
        check(defaults.object(forKey: "nativeDock.previousAutohide") as? Bool == false, "False baseline must remain distinct from absence")
        try await service.setEnabled(true)
        check(defaults.object(forKey: "nativeDock.previousAutohide") as? Bool == false, "Repeated enable must not replace baseline with our own true setting")
        try await service.setEnabled(false)
        check(!(await access.current()) && !service.desiredEnabled && !service.isActive, "Disable must restore false")
        check(defaults.object(forKey: "nativeDock.previousAutohide") == nil, "Successful restore clears recovery data")
        clear()

        let initiallyHidden = FakeNativeDockAccess(value: true, defaults: defaults)
        let hiddenService = NativeDockService(defaults: defaults, access: initiallyHidden)
        try await hiddenService.setEnabled(true)
        try await hiddenService.setEnabled(false)
        check(await initiallyHidden.current(), "Originally enabled autohide must remain enabled on disable")
        clear()

        let quitAccess = FakeNativeDockAccess(value: false, defaults: defaults)
        let quitService = NativeDockService(defaults: defaults, access: quitAccess)
        try await quitService.setEnabled(true)
        check(await quitService.restoreForTermination(), "Normal quit must restore successfully")
        check(!(await quitAccess.current()) && quitService.desiredEnabled && !quitService.isActive, "Quit restores the original preference but remembers replacement choice")
        check(defaults.object(forKey: "nativeDock.previousAutohide") == nil && defaults.bool(forKey: "nativeDock.replacementWanted"), "Quit must clear baseline only after restoration and retain opt-in")
        let relaunched = NativeDockService(defaults: defaults, access: quitAccess)
        await relaunched.activateIfRequested()
        let relaunchedValue = await quitAccess.current()
        check(relaunched.isActive && relaunchedValue, "A remembered opt-in activates on next launch")
        clear()

        defaults.set(true, forKey: "nativeDock.replacementWanted")
        defaults.set(false, forKey: "nativeDock.previousAutohide")
        let crashedAccess = FakeNativeDockAccess(value: true, defaults: defaults)
        let afterCrash = NativeDockService(defaults: defaults, access: crashedAccess)
        await afterCrash.activateIfRequested()
        check(afterCrash.isActive && defaults.object(forKey: "nativeDock.previousAutohide") as? Bool == false, "Crash recovery must preserve the pre-mutation false baseline")
        try await afterCrash.setEnabled(false)
        check(!(await crashedAccess.current()), "Disable after crash must restore the original false value")
        clear()

        let deniedAccess = FakeNativeDockAccess(value: false, defaults: defaults)
        await deniedAccess.configure(failReads: true)
        let denied = NativeDockService(defaults: defaults, access: deniedAccess)
        do { try await denied.setEnabled(true); fatalError("Read denial must fail") } catch { }
        check(!denied.desiredEnabled && !denied.isActive && denied.errorMessage?.contains("Automation") == true, "Permission denial must show a useful error without confirming replacement")
        let deniedWrites = await deniedAccess.writes
        check(defaults.object(forKey: "nativeDock.previousAutohide") == nil && deniedWrites.isEmpty, "Read denial must not mutate or record a guessed baseline")
        await deniedAccess.configure(failWrites: true)
        do { try await denied.setEnabled(true); fatalError("Write denial must fail") } catch { }
        check(defaults.object(forKey: "nativeDock.previousAutohide") as? Bool == false && denied.hasPendingRestoration, "Failed writes preserve recovery baseline")
        await deniedAccess.configure()
        try await denied.setEnabled(false)
        check(!denied.hasPendingRestoration && denied.errorMessage == nil, "A successful explicit restore clears error and recovery state")
        clear()

        let unconfirmedAccess = FakeNativeDockAccess(value: false, defaults: defaults)
        await unconfirmedAccess.configure(ignoreWrites: true)
        let unconfirmed = NativeDockService(defaults: defaults, access: unconfirmedAccess)
        var unconfirmedActivations = 0
        unconfirmed.onActivate = { unconfirmedActivations += 1 }
        do { try await unconfirmed.setEnabled(true); fatalError("A write that does not take effect must fail verification") } catch { }
        check(!unconfirmed.desiredEnabled && !unconfirmed.isActive && unconfirmedActivations == 0 && unconfirmed.hasPendingRestoration, "Failed verification must not activate BetterApple replacement")
        await unconfirmedAccess.configure()
        try await unconfirmed.setEnabled(true)
        await unconfirmedAccess.configure(ignoreWrites: true)
        check(!(await unconfirmed.restoreForTermination()), "An unconfirmed restore must fail even when the write returned successfully")
        check(unconfirmed.isActive && defaults.object(forKey: "nativeDock.previousAutohide") as? Bool == false, "Failed restore verification must retain the original baseline")
        await unconfirmedAccess.configure(failWrites: true)
        check(!(await unconfirmed.restoreForTermination()), "Failed quit restoration must be reported")
        check(unconfirmed.desiredEnabled && unconfirmed.isActive && defaults.object(forKey: "nativeDock.previousAutohide") as? Bool == false, "Failed restoration must retain opt-in, active state and baseline for retry")
        await unconfirmedAccess.configure()
        try await unconfirmed.setEnabled(false)
        clear()

        let journalAccess = FakeNativeDockAccess(value: false, defaults: defaults)
        var flushSucceeds = false
        let journalService = NativeDockService(defaults: defaults, access: journalAccess, journalFlush: { flushSucceeds })
        do { try await journalService.setEnabled(true); fatalError("Failed journal persistence must abort") } catch { }
        let journalFailedWrites = await journalAccess.writes
        check(journalFailedWrites.isEmpty && !journalService.isActive && !journalService.desiredEnabled, "Failed journal flush must prevent every external write")
        do { try await journalService.setEnabled(true); fatalError("Retry must not bypass a previously failed journal flush") } catch { }
        check(await journalAccess.writes.isEmpty, "An in-memory baseline is not permission to skip journal flushing")
        flushSucceeds = true
        try await journalService.setEnabled(true)
        check(journalService.isActive, "A successfully flushed journal permits explicit retry")
        try await journalService.setEnabled(false)
        clear()

        let queuedAccess = FakeNativeDockAccess(value: false, defaults: defaults)
        await queuedAccess.configure(delay: 20_000_000)
        let queued = NativeDockService(defaults: defaults, access: queuedAccess)
        let enabling = Task { try await queued.setEnabled(true) }
        await Task.yield()
        let disabling = Task { try await queued.setEnabled(false) }
        try await enabling.value; try await disabling.value
        check(await queuedAccess.writes == [true, false], "An off request during enable must serialize after it")
        let queuedValue = await queuedAccess.current()
        check(!queued.desiredEnabled && !queued.isActive && !queued.isBusy && !queuedValue, "Queued disable must leave the original Dock restored")
        // Real NSAppleScript descriptors (local, no System Events): AppleScript
        // booleans are typeTrue/typeFalse, which the parser must accept.
        for (source, expected) in [("return true", true), ("return false", false)] {
            var error: NSDictionary?
            let descriptor = NSAppleScript(source: source)!.executeAndReturnError(&error)
            check(error == nil && SystemEventsNativeDockAccess.boolean(from: descriptor) == expected, "Real AppleScript boolean '\(source)' must parse")
        }
        check(SystemEventsNativeDockAccess.boolean(from: NSAppleEventDescriptor(boolean: true)) == true, "typeBoolean must still parse")
        check(SystemEventsNativeDockAccess.boolean(from: NSAppleEventDescriptor(string: "true")) == nil, "Text is not a Dock setting")
        print("PASS: \(count) isolated native Dock transaction checks; opt-in, verification, original true/false, persistence/crash recovery, queued requests, permission errors and quit restoration. No System Events or user Dock mutation.")
    }
}
