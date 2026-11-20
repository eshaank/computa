import Foundation

/// One value streamed by the daemon's phase 0 trial call.
public struct Tick: Sendable, Equatable {
    /// Starts at 1 and goes up by one per tick within a stream.
    public let sequence: UInt64
    /// A made-up value between 0 and 100.
    public let value: Double
    /// When the daemon produced the tick.
    public let date: Date

    public init(sequence: UInt64, value: Double, date: Date) {
        self.sequence = sequence
        self.value = value
        self.date = date
    }
}

extension Tick {
    init(_ message: Computa_V1_Tick) {
        self.init(
            sequence: message.sequence,
            value: message.value,
            date: Date(timeIntervalSince1970: Double(message.unixMs) / 1000)
        )
    }
}
