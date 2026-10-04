import SwiftUI

struct TerminalHostView: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> NSView {
        session.engine.view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct TerminalDrawer: View {
    @ObservedObject var store: TerminalStore

    var body: some View {
        if !store.sessions.isEmpty {
            VStack(spacing: 0) {
                Rectangle().fill(Theme.line).frame(height: 1)
                TerminalTabStrip(store: store)
                if store.expanded, let session = store.selected {
                    TerminalSessionView(session: session, height: store.height)
                        .id(session.id)
                }
            }
            .overlay(alignment: .top) {
                if store.expanded {
                    ResizeHandle(height: Binding(
                        get: { store.height },
                        set: { store.height = $0 }
                    ))
                }
            }
        }
    }
}

struct ResizeHandle: View {
    @Binding var height: CGFloat
    @State private var startHeight: CGFloat?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering || startHeight != nil ? Theme.ember.opacity(0.6) : Color.clear)
            .frame(height: hovering || startHeight != nil ? 3 : 1)
            .frame(maxWidth: .infinity)
            .frame(height: 10, alignment: .top)
            .contentShape(Rectangle())
            .onHover { inside in
                guard inside != hovering else { return }
                hovering = inside
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let start = startHeight ?? height
                        startHeight = start
                        height = min(900, max(120, start - value.translation.height))
                    }
                    .onEnded { _ in startHeight = nil }
            )
    }
}

struct TerminalTabStrip: View {
    @ObservedObject var store: TerminalStore

    var body: some View {
        HStack(spacing: 6) {
            Button {
                store.expanded.toggle()
            } label: {
                Image(systemName: store.expanded ? "chevron.down" : "chevron.up")
            }
            .buttonStyle(IconButton(size: 24))
            .help(store.expanded ? "Recolher terminal" : "Expandir terminal")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.sessions) { session in
                        TerminalTab(
                            session: session,
                            selected: store.selectedID == session.id,
                            onSelect: {
                                store.selectedID = session.id
                                store.expanded = true
                            },
                            onClose: { store.close(session.id) }
                        )
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(Theme.surface)
    }
}

struct TerminalTab: View {
    let session: TerminalSession
    let selected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Dot(color: session.running ? Theme.ok : Theme.faded)
            Text(session.title)
                .font(Theme.mono(11.5, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Theme.emberLight : Theme.faded)
                .lineLimit(1)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.faded)
            .accessibilityLabel("Fechar sessão")
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.surface2 : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Theme.ember.opacity(0.5) : Color.clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
