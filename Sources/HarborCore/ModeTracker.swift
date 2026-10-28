/// Follows the terminal modes a byte stream switches on and off, so a replay that starts
/// partway through the stream can first restore the modes in effect at that point.
public struct ModeTracker: Equatable, Sendable {
    private enum State: Equatable, Sendable {
        case ground
        case escape
        case csi
    }

    private static let maxSequenceLength = 64
    private static let alternateScreenModes: Set<Int> = [47, 1047, 1049]
    private static let defaultOnModes: Set<Int> = [7, 25]
    private static let restoredModes: [Int] = [
        1, 7, 25, 9, 1000, 1002, 1003, 1004, 1005, 1006, 1015, 1016, 2004,
    ]

    private var state = State.ground
    private var sequence: [UInt8] = []
    private var alternateScreen = false
    private var enabledModes = ModeTracker.defaultOnModes
    private var applicationKeypad = false
    private var keyboardFlagsStack: [Int] = []

    public init() {}

    public mutating func feed(_ bytes: some Sequence<UInt8>) {
        for byte in bytes {
            consume(byte)
        }
    }

    public func prelude() -> [UInt8] {
        var output = ""
        if alternateScreen {
            output += "\u{1B}[?1049h"
        }
        for mode in Self.restoredModes {
            let isOn = enabledModes.contains(mode)
            if isOn != Self.defaultOnModes.contains(mode) {
                output += "\u{1B}[?\(mode)\(isOn ? "h" : "l")"
            }
        }
        if applicationKeypad {
            output += "\u{1B}="
        }
        for flags in keyboardFlagsStack {
            output += "\u{1B}[>\(flags)u"
        }
        return Array(output.utf8)
    }

    private mutating func consume(_ byte: UInt8) {
        switch state {
        case .ground:
            if byte == 0x1B { state = .escape }
        case .escape:
            consumeEscape(byte)
        case .csi:
            consumeCSI(byte)
        }
    }

    private mutating func consumeEscape(_ byte: UInt8) {
        state = .ground
        switch byte {
        case UInt8(ascii: "["):
            sequence.removeAll(keepingCapacity: true)
            state = .csi
        case UInt8(ascii: "="):
            applicationKeypad = true
        case UInt8(ascii: ">"):
            applicationKeypad = false
        case UInt8(ascii: "c"):
            self = ModeTracker()
        case 0x1B:
            state = .escape
        default:
            break
        }
    }

    private mutating func consumeCSI(_ byte: UInt8) {
        switch byte {
        case 0x20...0x3F:
            sequence.append(byte)
            if sequence.count > Self.maxSequenceLength { state = .ground }
        case 0x40...0x7E:
            state = .ground
            dispatchCSI(final: byte)
        case 0x1B:
            state = .escape
        default:
            state = .ground
        }
    }

    private mutating func dispatchCSI(final: UInt8) {
        let prefix = sequence.first.flatMap { (0x3C...0x3F).contains($0) ? $0 : nil }
        let parameterBytes = sequence.drop { $0 == prefix }.prefix { (0x30...0x3B).contains($0) }
        let intermediates = sequence.filter { (0x20...0x2F).contains($0) }
        let parameters = String(decoding: parameterBytes, as: UTF8.self)
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) }

        switch (prefix, intermediates, final) {
        case (UInt8(ascii: "?"), [], UInt8(ascii: "h")):
            setPrivateModes(parameters.compactMap { $0 }, on: true)
        case (UInt8(ascii: "?"), [], UInt8(ascii: "l")):
            setPrivateModes(parameters.compactMap { $0 }, on: false)
        case (UInt8(ascii: ">"), [], UInt8(ascii: "u")):
            keyboardFlagsStack.append(parameters.first.flatMap { $0 } ?? 0)
        case (UInt8(ascii: "<"), [], UInt8(ascii: "u")):
            let count = parameters.first.flatMap { $0 } ?? 1
            keyboardFlagsStack.removeLast(min(max(count, 1), keyboardFlagsStack.count))
        case (UInt8(ascii: "="), [], UInt8(ascii: "u")):
            setKeyboardFlags(parameters.first.flatMap { $0 } ?? 0, mode: parameters.dropFirst().first.flatMap { $0 } ?? 1)
        case (nil, [UInt8(ascii: "!")], UInt8(ascii: "p")):
            softReset()
        default:
            break
        }
    }

    private mutating func setPrivateModes(_ modes: [Int], on: Bool) {
        for mode in modes {
            if Self.alternateScreenModes.contains(mode) {
                alternateScreen = on
            } else if on {
                enabledModes.insert(mode)
            } else {
                enabledModes.remove(mode)
            }
        }
    }

    private mutating func setKeyboardFlags(_ flags: Int, mode: Int) {
        let current = keyboardFlagsStack.last ?? 0
        let updated: Int
        switch mode {
        case 2: updated = current | flags
        case 3: updated = current & ~flags
        default: updated = flags
        }
        if keyboardFlagsStack.isEmpty {
            keyboardFlagsStack.append(updated)
        } else {
            keyboardFlagsStack[keyboardFlagsStack.count - 1] = updated
        }
    }

    private mutating func softReset() {
        enabledModes.remove(1)
        enabledModes.insert(7)
        enabledModes.insert(25)
        applicationKeypad = false
    }
}
