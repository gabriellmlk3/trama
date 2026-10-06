import AppKit
import SwiftUI

struct WindowControlsInset: NSViewRepresentable {
    @Binding var inset: CGFloat

    func makeNSView(context: Context) -> InsetView {
        let view = InsetView()
        view.onChange = { inset = $0 }
        return view
    }

    func updateNSView(_ view: InsetView, context: Context) {
        view.onChange = { inset = $0 }
    }

    final class InsetView: NSView {
        var onChange: (CGFloat) -> Void = { _ in }
        private var observers: [NSObjectProtocol] = []

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let window else { return }
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                })
            }
            report()
        }

        private func report() {
            guard let window else { return }
            var value: CGFloat = 0
            if !window.styleMask.contains(.fullScreen), let zoom = window.standardWindowButton(.zoomButton), !zoom.isHidden, let container = zoom.superview {
                value = container.convert(zoom.frame, to: nil).maxX
            }
            DispatchQueue.main.async { [weak self] in
                self?.onChange(value)
            }
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}
