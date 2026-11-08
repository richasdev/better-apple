# Native services

All services are owned by the application coordinator. `start`/`stop` and `TimerService.setVisible` are idempotent visibility controls; views must not create separate service instances or run their own polling loops. Published UI state stays on the main actor; blocking player commands, EventKit queries and system sampling run on dedicated serial utility queues.

## Calendar

Uses EventKit `requestFullAccessToEvents` (macOS 14+), only following an explicit request. The app bundle must include `NSCalendarsFullAccessUsageDescription`. An `EKEventStore` is lazily created on a queue that owns all its queries. Calendar changes and wake notifications refresh the next seven days, capped to 50 events. One scheduled deadline expires the next event. No repeating calendar polling. Stopping removes observers and cancels the deadline. Events are kept in memory only. Permission revocation clears results on the next refresh. No write API is used, although the public EventKit permission is named full access.

## Music

`MusicPlayerAdapter` is an explicit protocol implemented by `AppleMusicAdapter` and `SpotifyMusicAdapter`. Script vocabulary lives in those adapters; the service owns scheduling, UI state and transport. Additional adapters can be injected in `MusicService(adapters:)`, registered with `registerAdapter`, or selected directly through `connect(to: adapter)`. `availablePlayers` exposes all registered descriptors; `Player.allCases` is the built-in picker list for compatibility. Adapters are trusted compiled application code, not user-imported scripts. A new supported scripting player does not require edits to the service.

Apple Music and Spotify adapters use their supported AppleScript dictionaries through `NSAppleScript`. The app must include `NSAppleEventsUsageDescription`; hardened runtime signing also requires `com.apple.security.automation.apple-events`. It does not use MediaRemote, ScriptingBridge-generated private interfaces, Accessibility or global media-key interception. `connect(to:)` is explicit: open the player first, then connect. Launching BetterApple does not send Apple Events. Commands are serialized away from the UI with a three-second AppleScript timeout, and constant snippets accept only finite, clamped numeric input. Volume/seek changes coalesce for 120 ms. Permission errors stop polling and require explicit reconnect. Queries run every two seconds only while a connected music surface is visible. In-flight Apple Events can take up to their timeout after the surface closes.

Metadata includes playback position and duration, and commands implement play/pause, previous/next, seek and player volume. Track artwork loads only on track changes: Apple Music returns artwork bytes; Spotify provides an HTTPS artwork URL loaded using the system HTTP cache. That artwork request goes to the image host chosen by Spotify, with no analytics. Fetches cancel when music surfaces are hidden. Metadata that finishes after hiding cannot start artwork work; in-flight artwork deliveries also check a visibility generation before updating UI. Artwork is optional and errors leave the system-symbol fallback intact. Music library/cloud items may not expose artwork, and Spotify/player updates can change scripting capabilities. Actual permission dialogs, both players and all playback commands require interactive validation on the target Mac; build success alone does not prove these integration paths. No claim of universal now-playing discovery is made.

## System

CPU uses public Mach host tick deltas. The first reading has no delta and reports zero. RAM reports active + wired + compressed physical pages, capped to physical memory; this is a documented estimate, not an exact reproduction of Activity Monitor. IOKit Power Sources reads internal-battery capacity; desktops return nil. Core Audio controls supported default-output master/channel scalar properties; HDMI and other fixed-volume devices return nil. Network reports aggregate incoming plus outgoing bytes per second across active non-loopback link interfaces. VPN/bridge interfaces can count the same packet twice, so this is activity rather than billed throughput. Sampling is every three seconds with tolerance while visible, and stops entirely when hidden. Sampling state resets on stop so the next CPU/network reading never averages across a hidden interval. No privileged helpers are used.

## Timer

A user-created countdown stores an absolute in-process deadline. Pause snapshots remaining time; resume derives a new deadline. Only visible surfaces run a one-second UI timer. One cancellable sleeping task delivers completion even if the countdown view is hidden, using the built-in Glass sound and an accessibility announcement. Wake notifications reconcile the deadline after sleep. Countdown state is intentionally not restored across app termination, and completion cannot alert while BetterApple is quit. The sound follows system audio availability and silent volume settings; notification permission is not requested.

## Verified

A local executable smoke harness also passed Timer start/pause/resume/cancel and non-finite input checks, verified Music start does not implicitly connect, and read live CPU/RAM/battery/network/volume without modifying system settings. These readings describe host activity, not BetterApple resource usage. Calendar permission and playback integration were not exercised.

The four Swift services were type-checked together using the installed Xcode SDK with `-swift-version 5 -target arm64-apple-macosx14.0`. Runtime and permission validation results belong in the project validation documents; no user Calendar or Automation permission was requested during the service implementation.

Apple DTS confirms that [background NSAppleScript execution must be serialized](https://developer.apple.com/forums/thread/759287); the music service shares one serial script queue across all instances.

Official references: [EventKit access](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:)), [NSAppleScript](https://developer.apple.com/documentation/foundation/nsapplescript/executeandreturnerror(_:)), [IOPowerSources](https://developer.apple.com/documentation/iokit/iopowersources_h).

### Repeatable service smoke harness

The retained harness checks timer pause/resume and invalid input, no automatic music connection, third-party adapter registration/selection without launching it, and live public system readings. It does not request Calendar or Automation access, play a sound, control players or write volume.

```sh
/opt/homebrew/bin/rtk proxy xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 -parse-as-library Sources/BetterApple/Services/*.swift Scripts/service-smoke.swift -o /tmp/betterapple-service-smoke
/opt/homebrew/bin/rtk proxy /tmp/betterapple-service-smoke
```

Use `x86_64-apple-macosx14.0` instead of `arm64-apple-macosx14.0` on an Intel development Mac.
