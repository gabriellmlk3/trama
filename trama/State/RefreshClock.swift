import SwiftUI

@MainActor
final class RefreshClock: ObservableObject {
    @Published private(set) var stamp: Int64 = 0

    func tick(_ value: Int64) {
        stamp = value
    }
}

private struct RefreshObserver: ViewModifier {
    @ObservedObject var clock: RefreshClock
    let every: Int
    let action: () async -> Void
    @State private var seen = 0

    func body(content: Content) -> some View {
        content.onChange(of: clock.stamp) { _, _ in
            seen += 1
            guard seen % every == 0 else { return }
            Task { await action() }
        }
    }
}

extension View {
    func onRefresh(_ clock: RefreshClock, every: Int = 1, perform action: @escaping () async -> Void) -> some View {
        modifier(RefreshObserver(clock: clock, every: every, action: action))
    }
}
