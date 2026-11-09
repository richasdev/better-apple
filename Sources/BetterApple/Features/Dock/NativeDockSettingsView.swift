import SwiftUI

struct NativeDockSettingsView: View {
    @ObservedObject var service: NativeDockService
    var body: some View {
        Section("macOS Dock") {
            Toggle("Replace macOS Dock", isOn: Binding(get: { service.desiredEnabled }, set: { enabled in
                Task { try? await service.setEnabled(enabled) }
            })).disabled(service.isBusy)
            if service.isBusy {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Updating macOS Dock…").font(.caption) }
            }
            Text("Uses macOS’s supported automatic hiding for the native Dock and shows the BetterApple Dock on every connected display. The native Dock can still reappear at the screen edge; macOS does not offer a public API to remove it completely.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Automation access to System Events is requested only when you choose this option. Normal quit restores your previous macOS Dock setting. Your replacement choice is remembered for the next launch.")
                .font(.caption).foregroundStyle(.secondary)
            if service.isActive { Label("Replacement active on every display", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
            if let error = service.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            if service.hasPendingRestoration {
                Button("Restore previous macOS Dock setting") { Task { try? await service.setEnabled(false) } }
                    .disabled(service.isBusy)
            }
        }
    }
}
