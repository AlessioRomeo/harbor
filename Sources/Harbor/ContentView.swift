import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color(nsColor: Theme.terminalBackground).ignoresSafeArea()
            if let controller = model.selectedController {
                TerminalPane(controller: controller, topInset: 18)
                    .ignoresSafeArea()
            } else if case .failed(let message) = model.host.state {
                MessageView(title: "Harbor can't reach its sessions", message: message)
            }
        }
        .frame(minWidth: 520, minHeight: 320)
    }
}

struct MessageView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.title3.weight(.medium))
            Text(message)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .frame(maxWidth: 420)
        .padding(32)
    }
}
