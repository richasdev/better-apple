import AppKit
import Combine

struct MusicTrack: Equatable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    let isPlaying: Bool
    let artworkURL: URL?
}

/// Player dictionaries and explicitly authorized browser automation, never MediaRemote.
@MainActor
final class MusicService: ObservableObject {
    struct Player: Hashable, Identifiable, CaseIterable {
        let id: String
        let title: String
        let bundleIdentifier: String
        var rawValue: String { id }
        static let appleMusic = Player(adapter: AppleMusicAdapter())
        static let spotify = Player(adapter: SpotifyMusicAdapter())
        static let allCases: [Player] = [.appleMusic, .spotify] + YouTubeMusicAdapter.Browser.allCases.map { Player(adapter: YouTubeMusicAdapter(browser: $0)) }

        init(adapter: any MusicPlayerAdapter) {
            id = adapter.id
            title = adapter.title
            bundleIdentifier = adapter.bundleIdentifier
        }
    }
    @Published private(set) var selectedPlayer: Player = .appleMusic
    @Published private(set) var track: MusicTrack?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var volume: Double = 0.5
    @Published private(set) var errorMessage: String?
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    var connectionHelp: String? { adapter.connectionHelp }
    private let defaults: UserDefaults
    private nonisolated static let scriptQueue = AppleScriptExecution.queue
    private let queue = MusicService.scriptQueue
    private var timer: Timer?
    private var visible = false
    private var authorizedByUser = false
    private var busy = false
    private var generation = 0
    private var artworkTask: URLSessionDataTask?
    private var artworkIdentity: String?
    private var volumeTask: Task<Void, Never>?
    private var seekTask: Task<Void, Never>?
    private var visibilityGeneration = 0
    private var adapters: [String: any MusicPlayerAdapter] = [:]
    private var adapter: any MusicPlayerAdapter = AppleMusicAdapter()
    @Published private(set) var availablePlayers: [Player] = []

    init(defaults: UserDefaults = .standard, adapters: [any MusicPlayerAdapter] = [AppleMusicAdapter(), SpotifyMusicAdapter()] + YouTubeMusicAdapter.Browser.allCases.map { YouTubeMusicAdapter(browser: $0) }) {
        self.defaults = defaults
        for adapter in adapters { registerAdapter(adapter) }
        let saved = defaults.string(forKey: "music.selectedPlayer")
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if let preferred = adapters.first(where: { $0.id == saved }) ?? adapters.first(where: { $0.id == "spotify" && running.contains($0.bundleIdentifier) }) ?? adapters.first {
            adapter = preferred
            selectedPlayer = Player(adapter: preferred)
        }
    }

    func registerAdapter(_ adapter: any MusicPlayerAdapter) {
        adapters[adapter.id] = adapter
        availablePlayers = adapters.values.map { Player(adapter: $0) }.sorted { $0.title < $1.title }
    }

    func connect(to player: Player) {
        guard let adapter = adapters[player.id] else {
            errorMessage = "This player integration is not registered."
            return
        }
        connect(to: adapter)
    }

    func connect(to adapter: any MusicPlayerAdapter) {
        disconnect()
        registerAdapter(adapter)
        self.adapter = adapter
        selectedPlayer = Player(adapter: adapter)
        defaults.set(adapter.id, forKey: "music.selectedPlayer")
        authorizedByUser = true
        guard !isPlayerRunning else { refresh(); return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: adapter.bundleIdentifier) else {
            errorMessage = "\(adapter.title) is not installed."
            return
        }
        isConnecting = true
        let token = generation
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.isConnecting = false
                if let error { self.fail(error) } else { self.refresh() }
            }
        }
    }

    func disconnect() {
        generation += 1
        authorizedByUser = false
        volumeTask?.cancel()
        seekTask?.cancel()
        isConnected = false
        isConnecting = false
        timer?.invalidate()
        timer = nil
        artworkTask?.cancel()
        artworkTask = nil
        artworkIdentity = nil
        artwork = nil
        track = nil
        errorMessage = nil
        busy = false
    }

    func start() {
        guard !visible else { return }
        visible = true
        updateTimer()
        refresh()
    }
    func stop() {
        visible = false
        visibilityGeneration += 1
        timer?.invalidate()
        timer = nil
        artworkTask?.cancel()
        artworkTask = nil
        if artwork == nil { artworkIdentity = nil }
    }
    func playPause() { command(.playPause) }
    func next() { command(.next) }
    func previous() { command(.previous) }
    func seek(to position: TimeInterval) {
        guard position.isFinite, let track else { return }
        let value = min(max(0, position), track.duration)
        seekTask?.cancel()
        seekTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.command(.seek(value))
        }
    }
    func setVolume(_ value: Double) {
        guard value.isFinite else { return }
        volume = min(1, max(0, value))
        let value = volume
        volumeTask?.cancel()
        volumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.command(.volume(value))
        }
    }
    func openPlayer() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: selectedPlayer.bundleIdentifier) else {
            errorMessage = "\(selectedPlayer.title) is not installed."
            return
        }
        if let page = adapter.launchURL {
            NSWorkspace.shared.open([page], withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
    }

    private func refresh() {
        guard authorizedByUser, !busy else { return }
        guard isPlayerRunning else {
            track = nil
            artwork = nil
            fail(NSError(domain: "BetterApple.Music", code: 3, userInfo: [NSLocalizedDescriptionKey: "Open \(selectedPlayer.title), then connect again."]))
            return
        }
        busy = true
        isConnecting = !isConnected
        let requestGeneration = generation
        let script = adapter.snapshotScript
        let jsonSnapshot = adapter.snapshotIsJSON
        queue.async { [weak self] in
            let result = Self.execute(script)
            Task { @MainActor in
                guard let self, self.generation == requestGeneration else { return }
                self.busy = false
                self.isConnecting = false
                switch result {
                case .failure(let error): self.fail(error)
                case .success(let descriptor):
                    let values: [Any]?
                    if jsonSnapshot {
                        guard let data = descriptor.stringValue?.data(using: .utf8),
                              let row = try? JSONSerialization.jsonObject(with: data) as? [Any], row.count == 8 else {
                            self.fail(NSError(domain: "BetterApple.Music", code: 2, userInfo: [NSLocalizedDescriptionKey: "The browser returned an invalid playback snapshot. Reconnect to YouTube."]))
                            return
                        }
                        values = row
                    } else { values = nil }
                    // Assign only on change: every @Published write invalidates observing views,
                    // and a paused player otherwise re-rendered them on each 2 s poll.
                    if !self.isConnected { self.isConnected = true }
                    if self.errorMessage != nil { self.errorMessage = nil }
                    let volume = min(1, max(0, (values?[6] as? Double ?? Double(descriptor.atIndex(7)?.int32Value ?? 50)) / 100))
                    if self.volume != volume { self.volume = volume }
                    let title = values?[0] as? String ?? descriptor.atIndex(1)?.stringValue ?? ""
                    if title.isEmpty {
                        if self.track != nil { self.track = nil }
                        if self.artwork != nil { self.artwork = nil }
                        self.artworkIdentity = nil
                        self.artworkTask?.cancel()
                        self.artworkTask = nil
                    }
                    else {
                        let track = MusicTrack(title: title, artist: values?[1] as? String ?? descriptor.atIndex(2)?.stringValue ?? "", album: values?[2] as? String ?? descriptor.atIndex(3)?.stringValue ?? "", duration: max(0, values?[3] as? Double ?? Self.number(descriptor.atIndex(4))), position: max(0, values?[4] as? Double ?? Self.number(descriptor.atIndex(5))), isPlaying: values?[5] as? Bool ?? descriptor.atIndex(6)?.booleanValue ?? false, artworkURL: URL(string: values?[7] as? String ?? descriptor.atIndex(8)?.stringValue ?? ""))
                        if self.track != track { self.track = track }
                        if self.visible { self.loadArtwork() }
                    }
                    self.updateTimer()
                }
            }
        }
    }

    private var isPlayerRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == selectedPlayer.bundleIdentifier }
    }

    private func command(_ operation: MusicPlayerCommand) {
        guard authorizedByUser, isConnected, isPlayerRunning else { return }
        let requestGeneration = generation
        let script = adapter.script(for: operation)
        queue.async { [weak self] in
            let result = Self.execute(script)
            Task { @MainActor in
                guard let self, self.generation == requestGeneration else { return }
                if case .failure(let error) = result { self.fail(error) }
                else { self.refresh() }
            }
        }
    }

    private func updateTimer() {
        guard visible, authorizedByUser, isConnected else { return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fail(_ error: Error) {
        isConnecting = false
        errorMessage = error.localizedDescription
        // Permission failure stops polling; reconnect is an explicit user action.
        isConnected = false
        timer?.invalidate()
        timer = nil
    }

    private func loadArtwork() {
        guard visible, let track else { return }
        let identity = track.title + "|" + track.artist + "|" + track.album
        guard artworkIdentity != identity else { return }
        artworkIdentity = identity
        artwork = nil
        artworkTask?.cancel()
        let requestGeneration = generation
        let requestVisibility = visibilityGeneration
        if let url = track.artworkURL, url.scheme == "https" {
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
            request.httpMethod = "GET"
            artworkTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
                guard let data, data.count <= 10_000_000,
                      (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                Task { @MainActor in
                    guard let self, self.generation == requestGeneration, self.visible, self.visibilityGeneration == requestVisibility, self.artworkIdentity == identity else { return }
                    self.artwork = NSImage(data: data)
                }
            }
            artworkTask?.resume()
        } else if let artworkScript = adapter.artworkScript {
            queue.async { [weak self] in
                let result = Self.execute(artworkScript)
                guard case .success(let descriptor) = result else { return }
                let data = descriptor.data
                guard data.count <= 10_000_000 else { return }
                Task { @MainActor in
                    guard let self, self.generation == requestGeneration, self.visible, self.visibilityGeneration == requestVisibility, self.artworkIdentity == identity else { return }
                    self.artwork = NSImage(data: data)
                }
            }
        }
    }

    private nonisolated static func number(_ descriptor: NSAppleEventDescriptor?) -> Double {
        guard let descriptor else { return 0 }
        let value = descriptor.coerce(toDescriptorType: typeIEEE64BitFloatingPoint)?.doubleValue ?? Double(descriptor.int32Value)
        return value.isFinite ? value : 0
    }

    /// Compiled scripts, touched only on `scriptQueue`. Polling reuses the snapshot script
    /// instead of recompiling it every 2 s.
    // Bound the cache because seek and volume commands embed changing values.
    private nonisolated static let compiledScripts = CompiledMusicScripts()

    private nonisolated static func execute(_ source: String) -> Result<NSAppleEventDescriptor, Error> {
        dispatchPrecondition(condition: .onQueue(scriptQueue))
        return autoreleasepool {
            var error: NSDictionary?
            let script: NSAppleScript
            if let cached = compiledScripts.values[source] { script = cached }
            else {
                guard let created = NSAppleScript(source: source) else {
                    return .failure(NSError(domain: "BetterApple.Music", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create player command."]))
                }
                if created.compileAndReturnError(nil) {
                    if compiledScripts.values.count >= 32 { compiledScripts.values.removeAll() }
                    compiledScripts.values[source] = created
                }
                script = created
            }
            let result = script.executeAndReturnError(&error)
            if let error {
                let code = (error[NSAppleScript.errorNumber] as? Int) ?? -1
                let message = code == -1743 ? "Automation access was denied. Enable BetterApple for this player in System Settings → Privacy & Security → Automation, then reconnect." : ((error[NSAppleScript.errorMessage] as? String) ?? "Player command failed.")
                return .failure(NSError(domain: "BetterApple.Music", code: code, userInfo: [NSLocalizedDescriptionKey: message]))
            }
            return .success(result)
        }
    }

    deinit { timer?.invalidate(); artworkTask?.cancel(); volumeTask?.cancel(); seekTask?.cancel() }
}

/// Mutable storage is accessed exclusively after execute() verifies the shared queue.
private final class CompiledMusicScripts: @unchecked Sendable {
    var values: [String: NSAppleScript] = [:]
}
