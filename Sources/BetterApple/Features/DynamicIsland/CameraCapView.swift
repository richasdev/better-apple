import SwiftUI

/// A narrow, non-key trigger confined to the measured camera gap. The real hardware
/// hides most of this surface; the small chin remains a usable pointer target.
struct CameraCapView: View {
    let hover: (Bool) -> Void
    let expand: () -> Void
    var body: some View {
        Button(action: expand) {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 10,
                                   bottomTrailingRadius: 10, topTrailingRadius: 0)
                .fill(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).focusable(false)
        .accessibilityLabel("Open Dynamic Island at the camera")
        .onHover(perform: hover)
    }
}
