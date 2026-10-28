import AppKit
import SwiftUI

@main
struct HarborApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Harbor", id: "main") {
            ContentView()
                .environment(model)
                .preferredColorScheme(.dark)
                .task { model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands { HarborCommands(model: model) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct HarborCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") { model.newSession() }
                .keyboardShortcut("t")
            Button("New Group") { model.newGroup() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .printItem) {}
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Clear to Start") { model.clearSelected() }
                .keyboardShortcut("k")
            Button("Find…") { showFindBar() }
                .keyboardShortcut("f")
        }
        CommandGroup(after: .toolbar) {
            Button("Bigger") { model.changeFontSize(by: 1) }
                .keyboardShortcut("+")
            Button("Smaller") { model.changeFontSize(by: -1) }
                .keyboardShortcut("-")
            Button("Default Size") { model.resetFontSize() }
                .keyboardShortcut("0")
            Divider()
        }
    }

    /// SwiftTerm's find bar opens through the standard find action, which reads the menu item's tag.
    private func showFindBar() {
        let item = NSMenuItem()
        item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
    }
}
