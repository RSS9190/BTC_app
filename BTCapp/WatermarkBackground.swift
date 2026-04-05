import SwiftUI

// MARK: - Watermark

struct WatermarkBackground<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background {
                Image("btc_watermark")
                    .resizable()
                    .scaledToFit()
                    .opacity(scheme == .dark ? 0.18 : 0.22)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
    }
}
