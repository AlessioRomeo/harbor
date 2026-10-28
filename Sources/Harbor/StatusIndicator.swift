import SwiftUI

/// What a session is doing, as the sidebar shows it at a glance.
enum SessionState: Equatable {
    case notStarted
    case idle
    case running
    case ended

    var label: String {
        switch self {
        case .notStarted: "Not started"
        case .idle: "Idle"
        case .running: "Running"
        case .ended: "Shell ended"
        }
    }
}

struct StatusIndicator: View {
    let status: SessionState

    var body: some View {
        symbol
            .frame(width: 14, height: 14)
            .help(status.label)
            .accessibilityLabel(status.label)
            .animation(.easeInOut(duration: 0.25), value: status)
    }

    @ViewBuilder
    private var symbol: some View {
        switch status {
        case .notStarted:
            Color.clear
        case .idle:
            Circle()
                .strokeBorder(Theme.quietIndicator, lineWidth: 1.5)
                .frame(width: 8, height: 8)
        case .running:
            Circle()
                .fill(Theme.running)
                .frame(width: 8, height: 8)
        case .ended:
            Image(systemName: "power")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.quietIndicator)
        }
    }
}
