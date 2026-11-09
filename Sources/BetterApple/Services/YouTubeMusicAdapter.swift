import Foundation

/// Explicit, local browser automation. Only exact YouTube hosts are read or controlled.
/// No MediaRemote, browser extension, account token or embedded web interface.
struct YouTubeMusicAdapter: MusicPlayerAdapter {
    enum Browser: String, CaseIterable, Sendable {
        case chrome, safari, brave
        var title: String {
            switch self { case .chrome: return "Chrome"; case .safari: return "Safari"; case .brave: return "Brave" }
        }
        var bundleIdentifier: String {
            switch self { case .chrome: return "com.google.Chrome"; case .safari: return "com.apple.Safari"; case .brave: return "com.brave.Browser" }
        }
    }
    let browser: Browser
    var id: String { "youtube-" + browser.rawValue }
    var title: String { "YouTube · " + browser.title }
    var bundleIdentifier: String { browser.bundleIdentifier }
    var snapshotIsJSON: Bool { true }
    var launchURL: URL? { URL(string: "https://www.youtube.com") }
    var connectionHelp: String? {
        let menu = browser == .safari ? "Safari → Settings → Advanced → Show features for web developers, then Develop → Developer Settings" : "\(browser.title) → View → Developer"
        return "Open YouTube or YouTube Music in \(browser.title). Enable Allow JavaScript from Apple Events in \(menu), then reconnect. Uses the first YouTube tab containing a video; empty homepages are skipped."
    }

    var snapshotScript: String { browserScript(javaScript: Self.snapshotJavaScript) }

    func script(for command: MusicPlayerCommand) -> String {
        let operation: String
        switch command {
        case .playPause:
            operation = "if(v.paused){v.play().catch(function(){});}else{v.pause();}"
        case .next:
            operation = "var b=document.querySelector('ytmusic-player-bar .next-button, .ytp-next-button');if(!b)throw Error('Next is unavailable for this video');b.click();"
        case .previous:
            operation = "var b=document.querySelector('ytmusic-player-bar .previous-button, .ytp-prev-button');if(b){b.click();}else{v.currentTime=0;}"
        case .seek(let seconds):
            operation = "if(!Number.isFinite(v.duration))throw Error('Live streams cannot seek');v.currentTime=Math.min(v.duration,\(seconds.isFinite ? max(0, seconds) : 0));"
        case .volume(let value):
            operation = "v.volume=\(value.isFinite ? min(1, max(0, value)) : 0);v.muted=false;"
        }
        return browserScript(javaScript: Self.wrap("var v=document.querySelector('video');if(!v)throw Error('Open a YouTube video first');\(operation)return 'OK';"))
    }

    static var snapshotJavaScript: String {
        wrap("""
        var v=document.querySelector('video');
        if(!v)return JSON.stringify(['','','',0,0,false,50,'']);
        var m=navigator.mediaSession&&navigator.mediaSession.metadata;
        var t=(m&&m.title)||document.querySelector('ytmusic-player-bar .title, h1.ytd-watch-metadata')?.textContent||document.title.replace(/ - YouTube$/, '');
        var a=(m&&m.artist)||document.querySelector('ytmusic-player-bar .byline, #owner #channel-name')?.textContent||'';
        var art=(m&&m.artwork&&m.artwork.length)?m.artwork[m.artwork.length-1].src:'';
        return JSON.stringify([t.trim(),a.trim(),(m&&m.album)||'',Number.isFinite(v.duration)?v.duration:0,Number.isFinite(v.currentTime)?v.currentTime:0,!v.paused&&!v.ended,Math.round((v.muted?0:v.volume)*100),art]);
        """)
    }

    private static func wrap(_ body: String) -> String {
        "(function(){if(!['youtube.com','www.youtube.com','music.youtube.com','m.youtube.com'].includes(location.hostname))throw Error('Unsupported page');\(body)})()"
    }

    private func browserScript(javaScript: String) -> String {
        let targeted = Self.wrap("if(!document.querySelector('video'))return '__BETTERAPPLE_NO_VIDEO__';return \(javaScript);")
        let quoted = "\"" + targeted.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ") + "\""
        let execute = browser == .safari ? "do JavaScript \(quoted) in t" : "execute t javascript \(quoted)"
        return playerScript("""
        repeat with w in windows
            repeat with t in tabs of w
                set u to URL of t
                if u starts with "https://www.youtube.com/" or u starts with "https://youtube.com/" or u starts with "https://music.youtube.com/" or u starts with "https://m.youtube.com/" then
                    set playbackResult to \(execute)
                    if playbackResult is not "__BETTERAPPLE_NO_VIDEO__" then return playbackResult
                end if
            end repeat
        end repeat
        error "Open a YouTube video or YouTube Music tab in \(browser.title), then reconnect." number -1728
        """)
    }
}
