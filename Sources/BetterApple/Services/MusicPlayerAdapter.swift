import Foundation

/// A supported scripting integration. Each adapter owns its player's vocabulary and
/// produces a normalized snapshot row: title, artist, album, duration seconds,
/// position seconds, playing Boolean, volume 0...100 and optional HTTPS artwork URL.
/// Adapters are application code, never loaded from user-supplied JSON or scripts.
protocol MusicPlayerAdapter: Sendable {
    var id: String { get }
    var title: String { get }
    var bundleIdentifier: String { get }
    var snapshotScript: String { get }
    var artworkScript: String? { get }
    func script(for command: MusicPlayerCommand) -> String
}

enum MusicPlayerCommand: Sendable {
    case playPause, next, previous
    case seek(TimeInterval)
    case volume(Double)
}

extension MusicPlayerAdapter {
    var artworkScript: String? { nil }

    func script(for command: MusicPlayerCommand) -> String {
        let operation: String
        switch command {
        case .playPause: operation = "playpause"
        case .next: operation = "next track"
        case .previous: operation = "previous track"
        case .seek(let seconds):
            let safeSeconds = seconds.isFinite ? max(0, seconds) : 0
            operation = "set player position to \(safeSeconds)"
        case .volume(let level):
            let safeLevel = level.isFinite ? min(1, max(0, level)) : 0
            operation = "set sound volume to \(Int(safeLevel * 100))"
        }
        return playerScript(operation)
    }

    func playerScript(_ operation: String) -> String {
        "with timeout of 3 seconds\ntell application id \"\(bundleIdentifier)\"\n\(operation)\nend tell\nend timeout"
    }

    func snapshotScript(duration: String, artwork: String) -> String {
        playerScript("""
        set v to sound volume
        if player state is stopped then return {"", "", "", 0, 0, false, v, ""}
        set t to current track
        return {name of t, artist of t, album of t, \(duration), player position, player state is playing, v, \(artwork)}
        """)
    }
}

struct AppleMusicAdapter: MusicPlayerAdapter {
    let id = "appleMusic"
    let title = "Apple Music"
    let bundleIdentifier = "com.apple.Music"
    var snapshotScript: String { snapshotScript(duration: "duration of t", artwork: "\"\"") }
    var artworkScript: String? { playerScript("get raw data of artwork 1 of current track") }
}

struct SpotifyMusicAdapter: MusicPlayerAdapter {
    let id = "spotify"
    let title = "Spotify"
    let bundleIdentifier = "com.spotify.client"
    var snapshotScript: String { snapshotScript(duration: "(duration of t) / 1000.0", artwork: "artwork url of t") }
}
