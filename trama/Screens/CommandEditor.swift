import AppKit
import SwiftUI

final class EditorTextView: NSTextView {
    var onSubmit: () -> Void = {}
    var onHistory: (Int) -> Void = { _ in }
    var onInterrupt: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 36, 76:
            if flags.contains(.shift) || flags.contains(.option) {
                insertNewlineIgnoringFieldEditor(nil)
            } else {
                onSubmit()
            }
        case 126 where isOnFirstLine && flags.isDisjoint(with: [.shift, .option, .command]):
            onHistory(-1)
        case 125 where isOnLastLine && flags.isDisjoint(with: [.shift, .option, .command]):
            onHistory(1)
        case 48:
            break
        default:
            if flags.contains(.control), event.charactersIgnoringModifiers == "c" {
                onInterrupt()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    private var isOnFirstLine: Bool {
        !string.prefix(selectedRange().location).contains("\n")
    }

    private var isOnLastLine: Bool {
        let end = selectedRange().location + selectedRange().length
        let nsString = string as NSString
        return !nsString.substring(from: min(end, nsString.length)).contains("\n")
    }
}

struct CommandEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let focusToken: Int
    let onSubmit: () -> Void
    let onHistory: (Int) -> Void
    let onInterrupt: () -> Void

    private static let maxHeight: CGFloat = 120

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = EditorTextView(frame: .zero)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = NSColor(Theme.text)
        textView.insertionPointColor = NSColor(Theme.ember)
        textView.textContainerInset = NSSize(width: 0, height: 3)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        textView.onSubmit = onSubmit
        textView.onHistory = onHistory
        textView.onInterrupt = onInterrupt
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        context.coordinator.reportHeight()
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CommandEditor
        weak var textView: EditorTextView?
        var focusToken = -1

        init(_ parent: CommandEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            reportHeight()
        }

        func reportHeight() {
            guard let textView, let container = textView.textContainer, let layout = textView.layoutManager else { return }
            layout.ensureLayout(for: container)
            let needed = ceil(layout.usedRect(for: container).height + textView.textContainerInset.height * 2)
            let clamped = min(max(needed, 24), CommandEditor.maxHeight)
            if abs(parent.height - clamped) > 0.5 {
                DispatchQueue.main.async { self.parent.height = clamped }
            }
        }
    }
}
