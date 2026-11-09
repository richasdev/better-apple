import AppKit
import Foundation

@main struct WidgetSmoke {
    @MainActor static func main() throws {
        let suite = "app.betterapple.widget-smoke"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = NSApplication.shared
        let manager = WidgetManager(calendar: CalendarService(), music: MusicService(), system: SystemStatusService(), timer: TimerService(defaults: defaults), defaults: defaults)
        manager.hide()
        manager.add(kind: .notes)
        let originalID = manager.widgets[0].id
        manager.update(originalID) { widget in
            widget.note = "Personalized local note"
            widget.title = "Work notes"
            widget.fontSize = 18
            widget.accent = .purple
            widget.options = WidgetDisplayOptions()
        }
        let duplicateID = manager.duplicate(id: originalID)!
        let duplicate = manager.widgets.first { $0.id == duplicateID }!
        assert(duplicateID != originalID && duplicate.note == "Personalized local note")
        assert(duplicate.title == "Work notes" && duplicate.fontSize == 18 && duplicate.accent == .purple)
        assert(manager.activeKinds.isEmpty)
        manager.flushPersistence()
        let saved = try JSONDecoder().decode([WidgetConfiguration].self, from: defaults.data(forKey: "widgets.layout")!)
        assert(saved.count == 2 && saved[1].options != nil)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(duplicate)) as! [String: Any]
        for key in ["title", "fontSize", "options", "surfaceStyle", "showHeader", "cornerRadius", "ink", "typeWeight"] { json.removeValue(forKey: key) }
        let legacy = try JSONDecoder().decode(WidgetConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        assert(legacy.title == nil && legacy.options == nil && !legacy.displayOptions.showSeconds)
        _ = try legacy.validated()
        assert(legacy.surface == .card && legacy.displaysHeader && legacy.radius == 22)
        var desktop = WidgetConfiguration(kind: .clock)
        desktop.x = 381; desktop.y = 92
        desktop.apply(.desktopClock)
        _ = try desktop.validated()
        assert(desktop.surface == .minimal && !desktop.displaysHeader && desktop.fontSize == 164)
        assert(desktop.ink == .white && desktop.typeWeight == .bold && !desktop.shadow && !desktop.border)
        assert(desktop.x == 381 && desktop.y == 92)
        assert(desktop.displayOptions.showTimeZone && desktop.displayOptions.clockTimeZoneIdentifier == nil)
        let restored = try JSONDecoder().decode(WidgetConfiguration.self, from: JSONEncoder().encode(desktop))
        assert(restored.surfaceStyle == .minimal && restored.ink == .white && restored.typeWeight == .bold)
        assert(restored.showHeader == false && restored.fontSize == 164)
        var bar = WidgetConfiguration(kind: .battery)
        bar.apply(.statusBar); bar.height = 72
        _ = try bar.validated()
        bar.apply(.glass)
        assert(bar.surface == .glass && bar.radius == 26 && bar.opacity == 0.85 && bar.height >= 160)
        bar.apply(.pureBlack)
        assert(bar.surface == .card && bar.theme == .dark && bar.opacity == 1 && bar.ink == .white && !bar.border)
        bar.cornerRadius = .infinity
        do { _ = try bar.validated(); fatalError("Invalid radius accepted") } catch {}
        assert(bar.sanitized().cornerRadius == nil)
        var note = WidgetConfiguration(kind: .notes)
        note.height = 72
        do { _ = try note.validated(); fatalError("Unreadable note size accepted") } catch {}
        desktop.fontSize = 201
        do { _ = try desktop.validated(); fatalError("Oversized clock font accepted") } catch {}
        var clock = WidgetConfiguration(kind: .clock)
        var options = WidgetDisplayOptions()
        options.clockTimeZoneIdentifier = "UTC"
        clock.options = options
        assert(WidgetClockFormatting.time(Date(timeIntervalSince1970: 0), options: options) == "00:00")
        options.clockTimeZoneIdentifier = "Asia/Tokyo"
        assert(WidgetClockFormatting.time(Date(timeIntervalSince1970: 0), options: options) == "09:00")
        options.showSeconds = true
        clock.options = options
        assert(WidgetClockFormatting.time(Date(timeIntervalSince1970: 7), options: options) == "09:00:07")
        let clockRoundtrip = try JSONDecoder().decode(WidgetConfiguration.self, from: JSONEncoder().encode(clock))
        assert(clockRoundtrip.displayOptions == options)
        options.clockTimeZoneIdentifier = "not/a/timezone"
        clock.options = options
        do { _ = try clock.validated(); fatalError("Invalid time zone accepted") } catch {}
        var layout = WidgetLayoutPreferences(); layout.gridSize = 0
        do { _ = try layout.validated(); fatalError("Invalid grid accepted") } catch {}
        assert(WidgetClockFormatting.scheduleStart(showSeconds: false, now: Date(timeIntervalSince1970: 127)).timeIntervalSince1970 == 120)
        manager.setAllVisible(false)
        assert(manager.widgets.allSatisfy { !$0.visible })
        manager.remove(id: originalID); manager.remove(id: duplicateID)
        manager.flushPersistence()
        print("PASS: widget legacy/new JSON, desktop/glass/status presets, large clock and compact dimensions, radius validation, duplicate identity and note/style preservation, time zones and seconds, option validation, minute alignment and hidden service demand")
    }
}
