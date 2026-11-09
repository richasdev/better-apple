import SwiftUI
import BetterAppleCore

struct IslandConnectionNotice: Equatable, Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let connected: Bool
}

@MainActor
final class IslandState: ObservableObject {
    @Published var connectionNotice: IslandConnectionNotice?
    @Published var connectionNoticeCompact = false
    @Published var expanded = false
    @Published var pinned = false
    @Published var selected: ModuleID = .calculator
    @Published var expandedContentVisible = false
    @Published var compactContentVisible = true
    @Published var focusRequest = 0
}

