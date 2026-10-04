import SwiftUI

enum DialogRole {
    case normal, destructive, cancel
}

struct DialogAction {
    let title: String
    var role: DialogRole = .normal
    let handler: () -> Void

    init(_ title: String, role: DialogRole = .normal, handler: @escaping () -> Void = {}) {
        self.title = title
        self.role = role
        self.handler = handler
    }
}

private struct AppDialogView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String?
    let actions: [DialogAction]

    private var cancel: DialogAction {
        actions.first { $0.role == .cancel } ?? DialogAction("Cancelar", role: .cancel)
    }

    private var others: [DialogAction] { actions.filter { $0.role != .cancel } }

    private var stacked: Bool { others.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if stacked {
                VStack(spacing: 8) {
                    ForEach(Array(others.enumerated()), id: \.offset) { index, action in
                        button(action, primary: index == 0, fill: true)
                    }
                    button(cancel, primary: false, fill: true)
                }
            } else {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    button(cancel, primary: false, fill: false)
                    ForEach(Array(others.enumerated()), id: \.offset) { index, action in
                        button(action, primary: index == 0, fill: false)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func button(_ action: DialogAction, primary: Bool, fill: Bool) -> some View {
        let run = {
            action.handler()
            dismiss()
        }
        Group {
            switch action.role {
            case .destructive:
                Button(action.title, action: run)
                    .buttonStyle(ToneButton(color: Theme.danger, text: Theme.dangerText))
            case .cancel:
                Button(action.title, action: run)
                    .buttonStyle(GhostButton())
                    .keyboardShortcut(.cancelAction)
            case .normal where primary:
                Button(action.title, action: run)
                    .buttonStyle(EmberButton())
                    .keyboardShortcut(.defaultAction)
            case .normal:
                Button(action.title, action: run)
                    .buttonStyle(GhostButton())
            }
        }
        .frame(maxWidth: fill ? .infinity : nil)
    }
}

extension View {
    func appDialog(
        _ title: String,
        isPresented: Binding<Bool>,
        message: String? = nil,
        actions: [DialogAction]
    ) -> some View {
        sheet(isPresented: isPresented) {
            AppDialogView(title: title, message: message, actions: actions)
        }
    }

    func appDialog<Item>(
        _ title: @escaping (Item) -> String,
        item: Binding<Item?>,
        message: ((Item) -> String?)? = nil,
        actions: @escaping (Item) -> [DialogAction]
    ) -> some View {
        sheet(isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })) {
            if let value = item.wrappedValue {
                AppDialogView(title: title(value), message: message?(value), actions: actions(value))
            }
        }
    }
}

struct MenuEntry {
    enum Kind {
        case action(title: String, systemImage: String?, checked: Bool, destructive: Bool, disabled: Bool, handler: () -> Void)
        case divider
        case section(String)
        case submenu(title: String, disabled: Bool, entries: [MenuEntry])
    }

    let kind: Kind
}

protocol MenuEntryConvertible {
    var entry: MenuEntry { get }
}

struct MenuAction: MenuEntryConvertible {
    let title: String
    var systemImage: String?
    var checked = false
    var destructive = false
    var disabled = false
    let handler: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        checked: Bool = false,
        destructive: Bool = false,
        disabled: Bool = false,
        handler: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.checked = checked
        self.destructive = destructive
        self.disabled = disabled
        self.handler = handler
    }

    var entry: MenuEntry {
        MenuEntry(kind: .action(title: title, systemImage: systemImage, checked: checked, destructive: destructive, disabled: disabled, handler: handler))
    }
}

struct MenuDivider: MenuEntryConvertible {
    var entry: MenuEntry { MenuEntry(kind: .divider) }
}

struct MenuSection: MenuEntryConvertible {
    let title: String

    init(_ title: String) { self.title = title }

    var entry: MenuEntry { MenuEntry(kind: .section(title)) }
}

struct SubMenu: MenuEntryConvertible {
    let title: String
    var disabled = false
    let entries: [MenuEntry]

    init(_ title: String, disabled: Bool = false, @MenuBuilder content: () -> [MenuEntry]) {
        self.title = title
        self.disabled = disabled
        self.entries = content()
    }

    var entry: MenuEntry { MenuEntry(kind: .submenu(title: title, disabled: disabled, entries: entries)) }
}

@resultBuilder
enum MenuBuilder {
    static func buildExpression(_ expression: some MenuEntryConvertible) -> [MenuEntry] { [expression.entry] }
    static func buildExpression<T: MenuEntryConvertible>(_ expression: [T]) -> [MenuEntry] { expression.map(\.entry) }
    static func buildBlock(_ parts: [MenuEntry]...) -> [MenuEntry] { parts.flatMap { $0 } }
    static func buildOptional(_ part: [MenuEntry]?) -> [MenuEntry] { part ?? [] }
    static func buildEither(first: [MenuEntry]) -> [MenuEntry] { first }
    static func buildEither(second: [MenuEntry]) -> [MenuEntry] { second }
    static func buildArray(_ parts: [[MenuEntry]]) -> [MenuEntry] { parts.flatMap { $0 } }
}

private struct MenuRow: View {
    let entry: MenuEntry
    let width: CGFloat
    let dismissAll: () -> Void
    @State private var hovering = false
    @State private var showingSub = false

    var body: some View {
        switch entry.kind {
        case .divider:
            Rectangle()
                .fill(Theme.line2)
                .frame(height: 1)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
        case .section(let title):
            SectionLabel(text: title)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
        case .action(let title, let systemImage, let checked, let destructive, let disabled, let handler):
            Button {
                dismissAll()
                DispatchQueue.main.async(execute: handler)
            } label: {
                row(title: title, systemImage: systemImage, checked: checked, destructive: destructive, trailing: nil)
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled ? 0.4 : 1)
            .onHover { hovering = $0 }
        case .submenu(let title, let disabled, let entries):
            Button {
                showingSub.toggle()
            } label: {
                row(title: title, systemImage: nil, checked: false, destructive: false, trailing: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled ? 0.4 : 1)
            .onHover { hovering = $0 }
            .popover(isPresented: $showingSub, arrowEdge: .trailing) {
                MenuList(entries: entries, width: width, dismissAll: dismissAll)
            }
        }
    }

    private func row(title: String, systemImage: String?, checked: Bool, destructive: Bool, trailing: String?) -> some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(destructive ? Theme.dangerText : Theme.faded)
                    .frame(width: 14)
            }
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(destructive ? Theme.dangerText : Theme.text2)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.ember)
            }
            if let trailing {
                Image(systemName: trailing)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.faded)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering || showingSub ? Theme.surface2 : Color.clear))
        .contentShape(Rectangle())
    }
}

private struct MenuList: View {
    let entries: [MenuEntry]
    let width: CGFloat
    let dismissAll: () -> Void

    private var rows: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                MenuRow(entry: entry, width: width, dismissAll: dismissAll)
            }
        }
        .padding(6)
        .frame(width: width)
    }

    var body: some View {
        Group {
            if entries.count > 11 {
                ScrollView { rows }
                    .frame(width: width, height: 340)
            } else {
                rows
            }
        }
        .background(Theme.surface)
        .preferredColorScheme(.dark)
    }
}

struct AppMenu<Label: View>: View {
    var width: CGFloat = 240
    var edge: Edge = .bottom
    var primaryAction: (() -> Void)?
    @ViewBuilder let label: () -> Label
    @MenuBuilder let content: () -> [MenuEntry]
    @State private var open = false
    @State private var longPressed = false

    var body: some View {
        Button {
            if longPressed {
                longPressed = false
            } else if let primaryAction {
                primaryAction()
            } else {
                open.toggle()
            }
        } label: {
            label()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                guard primaryAction != nil else { return }
                longPressed = true
                open = true
            }
        )
        .popover(isPresented: $open, arrowEdge: edge) {
            MenuList(entries: content(), width: width, dismissAll: { open = false })
        }
    }
}

struct AppPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(label: String, value: Value)]
    var width: CGFloat = 220
    var mono = false

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    var body: some View {
        AppMenu(width: width) {
            HStack(spacing: 6) {
                Text(currentLabel)
                    .font(mono ? Theme.mono(12) : .system(size: 12.5))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.faded)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2, lineWidth: 1))
            .contentShape(Rectangle())
        } content: {
            options.map { option in
                MenuAction(option.label, checked: option.value == selection) { selection = option.value }
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}
