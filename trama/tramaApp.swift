import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
@MainActor
enum EntryPoint {
    static func main() {
        if CLI.shouldRunAsCLI(CommandLine.arguments) {
            exit(CLI.main())
        }
        TramaApp.main()
    }
}

struct TramaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Trama", id: "principal") {
            ContentView()
                .environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nova trama…") { model.showingNewTrama = true }
                    .keyboardShortcut("n")
            }
            CommandMenu("Trama") {
                Button("Início") { model.screen = .home }
                    .keyboardShortcut("0")
                Button("Introdução") { model.showingOnboarding = true }
                Divider()
                Button("Abrir agent") {
                    if let t = model.selectedTrama { model.openClaudeInAll(t) }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(model.selectedTrama == nil)
                Button("Estacionar trama") {
                    if let t = model.selectedTrama, t.isActive {
                        Task { await model.park(t.slug) }
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(model.selectedTrama?.isActive != true)
                Divider()
                Button("Achados & perdidos") { model.screen = .findings }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Atualizar e buscar remotos") {
                    Task {
                        await model.fetchRemotes()
                        await model.refreshFindings()
                    }
                }
                .keyboardShortcut("r")
                Divider()
                Button("Alternar terminal") {
                    model.terminals.expanded.toggle()
                }
                .keyboardShortcut("`", modifiers: [.command])
                .disabled(model.terminals.sessions.isEmpty)
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(model)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            MenuBarLabel()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 3) {
            Image("MenuBarIcon")
            if model.waitingCount > 0 {
                Text("\(model.waitingCount)")
            }
        }
    }
}
