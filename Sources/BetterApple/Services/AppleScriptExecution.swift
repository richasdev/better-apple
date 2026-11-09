import Foundation

/// All NSAppleScript clients share serialization, including Music and Dock
/// preferences. A second feature must not introduce concurrent OSA execution.
/// https://developer.apple.com/forums/thread/759287
enum AppleScriptExecution {
    static let queue = DispatchQueue(label: "app.betterapple.applescript", qos: .utility)
}
