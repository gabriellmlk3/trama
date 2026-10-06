import SwiftUI

struct WidthSwitch<Wide: View, Narrow: View>: View {
    var minWidth: CGFloat = 640
    @ViewBuilder let wide: () -> Wide
    @ViewBuilder let narrow: () -> Narrow
    @State private var isWide = true

    var body: some View {
        Group {
            if isWide {
                wide()
            } else {
                narrow()
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: Bool.self) { $0.size.width >= minWidth } action: { isWide = $0 }
    }
}
