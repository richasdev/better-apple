import SwiftUI
import BetterAppleCore

@MainActor
protocol IslandModule {
    var id: ModuleID { get }
    func content() -> AnyView
}

struct NativeIslandModule: IslandModule {
    let id: ModuleID
    let build: @MainActor () -> AnyView
    func content() -> AnyView { build() }
}

@MainActor
final class IslandModuleRegistry {
    private var modules: [ModuleID: any IslandModule] = [:]
    func register(_ module: any IslandModule) { modules[module.id] = module }
    func content(for id: ModuleID) -> AnyView { modules[id]?.content() ?? AnyView(EmptyView()) }
}
