import Foundation
import Testing

@testable import ComputaCore

@Suite struct TickTests {
    @Test func convertsTheWireMessage() {
        let message = Computa_V1_Tick.with {
            $0.sequence = 42
            $0.value = 87.5
            $0.unixMs = 1_800_000_000_250
        }

        let tick = Tick(message)

        #expect(tick.sequence == 42)
        #expect(tick.value == 87.5)
        #expect(tick.date == Date(timeIntervalSince1970: 1_800_000_000.25))
    }
}
