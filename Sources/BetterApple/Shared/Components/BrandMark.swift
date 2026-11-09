import SwiftUI
import AppKit

enum BrandAsset {
    private static let dark = load("logo-dark")
    private static let light = load("logo-light")
    static func image(darkMode: Bool) -> NSImage? { darkMode ? dark : light }
    private static func load(_ name: String) -> NSImage? {
        Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Logo").flatMap(NSImage.init(contentsOf:))
    }
}

struct BrandMark: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Group {
            if let image = BrandAsset.image(darkMode: scheme == .dark) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "apple.logo").resizable().scaledToFit().foregroundStyle(.yellow)
            }
        }.accessibilityLabel("BetterApple")
    }
}
