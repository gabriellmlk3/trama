import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AgentPasteboard {
    struct Result {
        var attachments: [AgentAttachment] = []
        var errors: [String] = []
    }

    static func intercept(into directory: String) -> Result? {
        let pasteboard = NSPasteboard.general
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty {
            return store(urls, into: directory)
        }
        let hasText = !(pasteboard.string(forType: .string) ?? "").isEmpty
        guard !hasText, let png = imageData(pasteboard) else { return nil }
        var result = Result()
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-")
        do {
            result.attachments = [try AgentAttachments.store(data: png, name: "colagem-\(stamp).png", in: directory)]
        } catch {
            result.errors = [errorMessage(error)]
        }
        return result
    }

    static func store(_ urls: [URL], into directory: String) -> Result {
        var result = Result()
        for url in urls {
            do {
                result.attachments.append(try AgentAttachments.store(file: url.path, in: directory))
            } catch {
                result.errors.append(errorMessage(error))
            }
        }
        return result
    }

    static func chooseFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Escolha os arquivos para anexar"
        return panel.runModal() == .OK ? panel.urls : []
    }

    private static func imageData(_ pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff) else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}

struct AttachmentChips: View {
    let items: [AgentAttachment]
    var onRemove: ((AgentAttachment) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.isImage ? "photo" : "doc")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.emberText)
                        Text(item.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 180)
                        if let onRemove {
                            Button {
                                onRemove(item)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.faded)
                            .accessibilityLabel("Remover \(item.name)")
                        }
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(Capsule().fill(Theme.surface))
                    .overlay(Capsule().stroke(Theme.line2, lineWidth: 1))
                }
            }
        }
    }
}

struct AttachmentInput: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Binding var attachments: [AgentAttachment]
    var focused: FocusState<Bool>.Binding
    let directory: String?
    @State private var monitor: Any?
    @State private var dropping = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if dropping {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.ember, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $dropping, perform: drop)
            .onAppear(perform: install)
            .onDisappear(perform: remove)
    }

    private func add(_ result: AgentPasteboard.Result) {
        attachments.append(contentsOf: result.attachments)
        if !result.errors.isEmpty { model.showError(result.errors.joined(separator: "\n")) }
    }

    private func install() {
        guard monitor == nil else { return }
        let focused = focused
        let directory = directory
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard focused.wrappedValue,
                  let directory,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "v",
                  let result = AgentPasteboard.intercept(into: directory) else { return event }
            add(result)
            return nil
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let directory else { return false }
        let accepted = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !accepted.isEmpty else { return false }
        for provider in accepted {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async { add(AgentPasteboard.store([url], into: directory)) }
            }
        }
        return true
    }
}

extension View {
    func agentAttachmentInput(_ attachments: Binding<[AgentAttachment]>, focused: FocusState<Bool>.Binding, directory: String?) -> some View {
        modifier(AttachmentInput(attachments: attachments, focused: focused, directory: directory))
    }
}
