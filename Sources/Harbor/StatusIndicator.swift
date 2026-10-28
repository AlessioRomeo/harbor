import HarborCore
import SwiftUI

extension SessionIndicator {
    var label: String {
        switch self {
        case .notStarted: "Not started"
        case .idle: "Idle"
        case .running: "Running"
        case .ended: "Shell ended"
        case .claudeWorking: "Claude is working"
        case .claudeIdle: "Claude is open"
        case .needsAttention(.finished): "Claude finished"
        case .needsAttention(.waiting): "Claude is waiting for you"
        case .needsAttention(.failed): "Claude stopped with an error"
        }
    }
}

struct StatusIndicator: View {
    let indicator: SessionIndicator

    var body: some View {
        symbol
            .frame(width: 16, height: 16)
            .help(indicator.label)
            .accessibilityLabel(indicator.label)
            .animation(.easeInOut(duration: 0.25), value: indicator)
    }

    @ViewBuilder
    private var symbol: some View {
        switch indicator {
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
        case .claudeWorking:
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.running)
                .symbolEffect(.pulse, options: .repeating)
        case .claudeIdle:
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.quietIndicator)
        case .needsAttention(let reason):
            Circle()
                .fill(reason == .failed ? Theme.failure : Theme.attention)
                .frame(width: 10, height: 10)
                .shadow(color: (reason == .failed ? Theme.failure : Theme.attention).opacity(0.6), radius: 4)
        }
    }
}
