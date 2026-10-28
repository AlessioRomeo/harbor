import Foundation
import Testing
@testable import HarborCore

struct FrameTests {
    @Test func roundTripsAcrossSplitReads() throws {
        let frames = [Frame(.output, payload: Array("héllo".utf8)), Frame(.input), Frame(.resize, payload: [1, 2, 3])]
        let bytes = frames.flatMap { $0.encoded() }
        var decoder = FrameDecoder()
        var decoded: [Frame] = []
        for byte in bytes {
            decoder.append([byte])
            while let frame = try decoder.next() {
                decoded.append(frame)
            }
        }
        #expect(decoded == frames)
    }

    @Test func decodesSeveralFramesFromOneRead() throws {
        var decoder = FrameDecoder()
        decoder.append(Frame(.input, payload: [7]).encoded() + Frame(.output, payload: [8]).encoded())
        #expect(try decoder.next() == Frame(.input, payload: [7]))
        #expect(try decoder.next() == Frame(.output, payload: [8]))
        #expect(try decoder.next() == nil)
    }

    @Test func rejectsUnknownType() {
        var decoder = FrameDecoder()
        decoder.append([0xEE, 0, 0, 0, 0])
        #expect(throws: FrameError.unknownType(0xEE)) { try decoder.next() }
    }

    @Test func rejectsOversizedPayload() {
        var decoder = FrameDecoder()
        decoder.append([FrameType.output.rawValue, 0x7F, 0xFF, 0xFF, 0xFF])
        #expect(throws: FrameError.tooLarge(0x7FFF_FFFF)) { try decoder.next() }
    }

    @Test func requestsRoundTripAsJSON() throws {
        let request = HostRequest.kill(id: UUID(), saveOutput: true)
        #expect(try Frame.json(.request, request).decode(HostRequest.self) == request)
    }
}
