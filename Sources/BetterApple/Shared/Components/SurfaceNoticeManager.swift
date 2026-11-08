import AppKit
import SwiftUI

final class SurfaceNoticePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Event-triggered feedback. Showing a notice never requests keyboard focus;
/// intentional pointer/keyboard interaction pauses its finite dismissal deadline.
@MainActor
final class SurfaceNoticeManager {
    private var panel: SurfaceNoticePanel?
    private var dismissal: Task<Void, Never>?
    private var keyObserver: NSObjectProtocol?
    private var hovered = false
    private var generation = 0

    func show(_ message: String, openSettings: @escaping () -> Void) {
        dismiss(animated: false)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let available = screen.visibleFrame.insetBy(dx: 16, dy: 16)
        let size = NSSize(width: min(380, available.width), height: min(132, available.height))
        let target = NSRect(x: available.maxX - size.width, y: available.maxY - size.height, width: size.width, height: size.height)
        let window = SurfaceNoticePanel(contentRect: target, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false, screen: screen)
        window.isReleasedWhenClosed = false; window.isOpaque = false; window.backgroundColor = .clear
        window.level = .floating; window.hasShadow = true; window.hidesOnDeactivate = false
        window.animationBehavior = .none; window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let hosting = NSHostingView(rootView: SurfaceNoticeView(message: message,
            dismiss: { [weak self] in self?.dismiss() },
            openSettings: { [weak self] in self?.dismiss(); openSettings() },
            pointerInside: { [weak self] inside in self?.hovered = inside; self?.scheduleDismissal() }))
        hosting.sizingOptions = []; window.contentView = hosting; panel = window
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleDismissal() }
        }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !reduced { window.alphaValue = 0; window.setFrame(target.offsetBy(dx: 0, dy: -4), display: false) }
        window.orderFrontRegardless()
        if !reduced {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = WorkspaceMotion.content; context.timingFunction = WorkspaceMotion.windowTimingFunction(expanding: true)
                window.animator().alphaValue = 1; window.animator().setFrame(target, display: true)
            }
        }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        scheduleDismissal()
    }
    private func scheduleDismissal() {
        dismissal?.cancel(); dismissal = nil
        guard let panel, !hovered, !panel.isKeyWindow else { return }
        let current = generation
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, self.generation == current, !self.hovered, self.panel?.isKeyWindow == false else { return }
            self.dismiss()
        }
    }
    func dismiss(animated: Bool = true) {
        generation += 1; dismissal?.cancel(); dismissal = nil; hovered = false
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }; keyObserver = nil
        guard let closing = panel else { return }
        panel = nil
        let close = { closing.orderOut(nil); closing.contentView = nil; closing.close() }
        if animated && closing.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = WorkspaceMotion.quick; context.timingFunction = WorkspaceMotion.windowTimingFunction(expanding: false)
                closing.animator().alphaValue = 0
                closing.animator().setFrame(closing.frame.offsetBy(dx: 0, dy: -2), display: true)
            } completionHandler: { Task { @MainActor in close() } }
        } else { close() }
    }
}

private struct SurfaceNoticeView: View {
    let message: String
    let dismiss: () -> Void
    let openSettings: () -> Void
    let pointerInside: (Bool) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill").font(.title2).foregroundStyle(.orange).padding(.top, 3)
            VStack(alignment: .leading, spacing: 6) {
                Text("BetterApple").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(message).font(.callout).lineLimit(3).textSelection(.enabled)
                Button("Open Settings…", action: openSettings).buttonStyle(.link)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(SurfaceButtonStyle()).accessibilityLabel("Dismiss message")
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if reduceTransparency { RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .windowBackgroundColor)) }
            else { RoundedRectangle(cornerRadius: 16).fill(.regularMaterial) }
        }
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.1)))
        .onHover(perform: pointerInside)
    }
}
