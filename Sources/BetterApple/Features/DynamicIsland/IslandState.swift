import SwiftUI
import BetterAppleCore

@MainActor
final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var pinned = false
    @Published var selected: ModuleID = .calculator
    @Published var expandedContentVisible = false
    @Published var compactContentVisible = true
    @Published var focusRequest = 0
}

