// Native JavaScriptCore fixtures execute the actual adapter script. Compilation
// checks load installed app dictionaries only: no Apple Events are executed.
import AppKit
import JavaScriptCore

private enum SmokeFailure: Error { case failed(String) }

@main
struct YouTubeSmoke {
    @MainActor static func main() throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ name: String) throws {
            guard condition() else { throw SmokeFailure.failed(name) }
            checks += 1
        }
        func fixture(host: String = "www.youtube.com", video: Bool = true, metadata: String = "null", duration: String = "180", position: String = "12", muted: Bool = false, ended: Bool = false, paused: Bool = false, selectors: Bool = true) -> JSContext {
            let context = JSContext()!
            let hostLiteral = String(data: try! JSONEncoder().encode(host), encoding: .utf8)!
            context.evaluateScript("""
            var location={hostname:\(hostLiteral)},navigator={mediaSession:{metadata:\(metadata)}};
            var __queries=0,__playCalls=0,__pauseCalls=0,__nextCalls=0,__previousCalls=0;
            var __v={duration:\(duration),currentTime:\(position),paused:\(paused),ended:\(ended),muted:\(muted),volume:0.37};
            __v.play=function(){__playCalls++;this.paused=false;return {catch:function(){}};};
            __v.pause=function(){__pauseCalls++;this.paused=true;};
            var document={title:'Document song - YouTube',querySelector:function(s){
              __queries++;
              if(s==='video')return \(video ? "__v" : "null");
              if(!\(selectors))return null;
              if(s.indexOf(' .next-button')>=0)return {click:function(){__nextCalls++;}};
              if(s.indexOf(' .previous-button')>=0)return {click:function(){__previousCalls++;}};
              if(s.indexOf(' .title')>=0)return {textContent:'  Fallback song  '};
              if(s.indexOf(' .byline')>=0)return {textContent:'  Fallback artist  '};
              return null;
            }};
            """)
            return context
        }
        func snapshot(_ context: JSContext) throws -> [Any] {
            context.exception = nil
            guard let json = context.evaluateScript(YouTubeMusicAdapter.snapshotJavaScript)?.toString(), context.exception == nil,
                  let row = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any] else {
                throw SmokeFailure.failed("snapshot evaluation: \(context.exception?.toString() ?? "invalid JSON")")
            }
            return row
        }
        func embeddedJavaScript(_ script: String, browser: YouTubeMusicAdapter.Browser = .chrome) throws -> String {
            let prefix = browser == .safari ? "set playbackResult to do JavaScript " : "set playbackResult to execute t javascript "
            guard let range = script.range(of: prefix) else { throw SmokeFailure.failed("command extraction") }
            let tail = script[range.upperBound...]
            var escaped = false
            var length = 0
            for character in tail {
                length += 1
                if length == 1 { continue }
                if escaped { escaped = false; continue }
                if character == "\\" { escaped = true; continue }
                if character == "\"" { break }
            }
            return try JSONDecoder().decode(String.self, from: Data(tail.prefix(length).utf8))
        }
        func commandJavaScript(_ command: MusicPlayerCommand, browser: YouTubeMusicAdapter.Browser = .chrome) throws -> String {
            try embeddedJavaScript(YouTubeMusicAdapter(browser: browser).script(for: command), browser: browser)
        }
        let metadata = #"{"title":"  Metadata song  ","artist":"  Artist  ","album":"Album","artwork":[{"src":"https://example.com/small.jpg"},{"src":"https://example.com/large.jpg"}]}"#
        let row = try snapshot(fixture(metadata: metadata))
        try expect(row.count == 8, "normalized eight-value snapshot")
        try expect(row[0] as? String == "Metadata song" && row[1] as? String == "Artist" && row[2] as? String == "Album", "media metadata and trimming")
        try expect(row[3] as? Double == 180 && row[4] as? Double == 12 && row[5] as? Bool == true, "duration position and playback")
        try expect(row[6] as? Int == 37 && row[7] as? String == "https://example.com/large.jpg", "volume and artwork")
        let fallback = try snapshot(fixture())
        try expect(fallback[0] as? String == "Fallback song" && fallback[1] as? String == "Fallback artist", "DOM title artist fallback")
        let document = try snapshot(fixture(selectors: false))
        try expect(document[0] as? String == "Document song", "document title fallback")
        let empty = try snapshot(fixture(video: false))
        try expect(empty[0] as? String == "" && empty[3] as? Double == 0, "missing video empty state")
        let live = try snapshot(fixture(duration: "Infinity", position: "NaN", muted: true, ended: true))
        try expect(live[3] as? Double == 0 && live[4] as? Double == 0 && live[5] as? Bool == false && live[6] as? Int == 0, "live nonfinite progress muted and ended state")
        for host in ["youtube.com", "www.youtube.com", "music.youtube.com", "m.youtube.com"] {
            let supported = try snapshot(fixture(host: host))
            try expect(supported.count == 8, "exact supported host \(host)")
        }
        for host in ["youtube.com.evil.example", "www.youtube.com.evil", "evilyoutube.com", "example.com"] {
            let context = fixture(host: host)
            context.evaluateScript(YouTubeMusicAdapter.snapshotJavaScript)
            try expect(context.exception != nil && context.objectForKeyedSubscript("__queries").toInt32() == 0, "reject unsupported host before DOM access")
        }
        let playing = fixture()
        playing.evaluateScript(try commandJavaScript(.playPause))
        try expect(playing.exception == nil && playing.objectForKeyedSubscript("__pauseCalls").toInt32() == 1, "pause actual command JavaScript")
        playing.evaluateScript(try commandJavaScript(.playPause))
        try expect(playing.exception == nil && playing.objectForKeyedSubscript("__playCalls").toInt32() == 1, "play actual command JavaScript")
        playing.evaluateScript(try commandJavaScript(.next))
        playing.evaluateScript(try commandJavaScript(.previous))
        try expect(playing.exception == nil && playing.objectForKeyedSubscript("__nextCalls").toInt32() == 1 && playing.objectForKeyedSubscript("__previousCalls").toInt32() == 1, "next previous command buttons")
        let noPrevious = fixture(selectors: false)
        noPrevious.evaluateScript(try commandJavaScript(.previous))
        try expect(noPrevious.exception == nil && noPrevious.evaluateScript("__v.currentTime")?.toDouble() == 0, "previous fallback restarts video")
        noPrevious.evaluateScript(try commandJavaScript(.next))
        try expect(noPrevious.exception != nil, "missing next control reports error")
        for (input, expected) in [(Double.nan, 0.0), (.infinity, 0), (-5, 0), (1.5, 1), (0.6, 0.6)] {
            let context = fixture(muted: true)
            context.evaluateScript(try commandJavaScript(.volume(input)))
            try expect(context.exception == nil && context.evaluateScript("__v.volume")?.toDouble() == expected && context.evaluateScript("__v.muted")?.toBool() == false, "finite clamped volume \(input)")
        }
        for (input, expected) in [(Double.nan, 0.0), (.infinity, 0), (-5, 0), (400, 180), (30, 30)] {
            let context = fixture()
            context.evaluateScript(try commandJavaScript(.seek(input)))
            try expect(context.exception == nil && context.evaluateScript("__v.currentTime")?.toDouble() == expected, "finite bounded seek \(input)")
        }
        let noSeek = fixture(duration: "Infinity")
        noSeek.evaluateScript(try commandJavaScript(.seek(20)))
        try expect(noSeek.exception != nil, "live stream seeking reports unavailable")
        let forbidden = fixture(host: "example.com")
        forbidden.evaluateScript(try commandJavaScript(.playPause))
        try expect(forbidden.exception != nil && forbidden.objectForKeyedSubscript("__queries").toInt32() == 0, "command host guard")
        for browser in YouTubeMusicAdapter.Browser.allCases {
            let noVideo = fixture(video: false)
            let commandResult = noVideo.evaluateScript(try commandJavaScript(.playPause, browser: browser))?.toString()
            try expect(noVideo.exception == nil && commandResult == "__BETTERAPPLE_NO_VIDEO__" && noVideo.objectForKeyedSubscript("__playCalls").toInt32() == 0 && noVideo.objectForKeyedSubscript("__pauseCalls").toInt32() == 0, "missing video command sentinel \(browser.title)")
            let adapter = YouTubeMusicAdapter(browser: browser)
            let home = fixture(video: false)
            let snapshotResult = home.evaluateScript(try embeddedJavaScript(adapter.snapshotScript, browser: browser))?.toString()
            try expect(home.exception == nil && snapshotResult == "__BETTERAPPLE_NO_VIDEO__", "homepage snapshot sentinel \(browser.title)")
            let video = fixture(metadata: metadata)
            let videoResult = video.evaluateScript(try embeddedJavaScript(adapter.snapshotScript, browser: browser))?.toString()
            let videoRow = try JSONSerialization.jsonObject(with: Data((videoResult ?? "").utf8)) as? [Any]
            try expect(video.exception == nil && videoRow?[0] as? String == "Metadata song", "targeted video snapshot \(browser.title)")
        }
        var compiled: [String] = []
        var unavailable: [String] = []
        let adapters: [any MusicPlayerAdapter] = YouTubeMusicAdapter.Browser.allCases.map { YouTubeMusicAdapter(browser: $0) as any MusicPlayerAdapter } + [SpotifyMusicAdapter()]
        for adapter in adapters {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: adapter.bundleIdentifier) != nil else {
                unavailable.append(adapter.title); continue
            }
            let commands: [MusicPlayerCommand] = [.playPause, .previous, .next, .seek(42), .volume(0.4)]
            let sources = [adapter.snapshotScript] + commands.map { adapter.script(for: $0) }
            for source in sources {
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source), script.compileAndReturnError(&error) else {
                    throw SmokeFailure.failed("\(adapter.title) AppleScript compilation: \(String(describing: error))")
                }
                checks += 1
            }
            compiled.append(adapter.title)
        }
        print("PASS: \(checks) YouTube JS fixture and compile-only checks. Compiled dictionaries: \(compiled.joined(separator: ", ")). Not installed: \(unavailable.joined(separator: ", ")).")
        print("No browser Apple Events were executed; no playback, permissions or page access occurred. Physical browser integration remains unverified.")
    }
}
