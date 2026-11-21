import Foundation

/// The three memory figures of one row in the Mem list, as text.
public struct MemoryFigures: Sendable, Equatable {
    /// In RAM now (resident size). The list sorts by this.
    public var mem: String
    /// Footprint minus resident, never below zero: roughly what is compressed or in swap.
    public var compressedOrSwapped: String
    /// Everything allocated, compressed and swapped memory included at full size.
    public var footprint: String

    /// What a figure the daemon does not report shows as.
    public static let notReported = "–"

    /// - Parameter residentReported: False when the daemon sends no resident sizes. Mem and
    ///   Compressed + swap then show `notReported` rather than a wrong "0 B".
    public init(resident: UInt64, footprint: UInt64, residentReported: Bool) {
        self.footprint = Format.memory(footprint)
        if residentReported {
            mem = Format.memory(resident)
            compressedOrSwapped = Format.memory(footprint.subtractingClamped(resident))
        } else {
            mem = Self.notReported
            compressedOrSwapped = Self.notReported
        }
    }

    public init(_ group: ProcessGroup, residentReported: Bool) {
        self.init(resident: group.residentBytes, footprint: group.memoryBytes, residentReported: residentReported)
    }

    public init(_ process: ProcessEntry, residentReported: Bool) {
        self.init(resident: process.residentBytes, footprint: process.memoryBytes, residentReported: residentReported)
    }
}

/// The two network figures of one row in the Net list, as text.
public struct TrafficFigures: Sendable, Equatable {
    public var down: String
    public var up: String

    public init(receive: Double, send: Double) {
        down = Format.rate(receive)
        up = Format.rate(send)
    }

    public init(_ group: ProcessGroup) {
        self.init(receive: group.receiveBytesPerSecond, send: group.sendBytesPerSecond)
    }

    public init(_ process: ProcessEntry) {
        self.init(receive: process.receiveBytesPerSecond, send: process.sendBytesPerSecond)
    }
}

/// What the Net tab's app list can show for a snapshot.
public enum TrafficAvailability: Sendable, Equatable {
    /// The rates are measured; show the list.
    case available
    /// The first snapshot of a stream: the daemon needs two readings before it has rates.
    case measuring
    /// The daemon could not measure, for this reason.
    case problem(String)
    /// The daemon sent no network status at all: it is too old to measure traffic by app.
    case daemonNeedsUpdate

    public init(_ status: ProcessNetworkStatus?) {
        guard let status else {
            self = .daemonNeedsUpdate
            return
        }
        if status.available {
            self = .available
        } else {
            let problem = status.problem.trimmingCharacters(in: .whitespacesAndNewlines)
            self = problem.isEmpty ? .measuring : .problem(problem)
        }
    }
}

/// Words the UI uses to explain the memory and network figures. Kept here so they are easy to
/// find and change.
public enum FigureExplanations {
    /// The Mem list's info popover.
    public static let memory = """
        Mem is what each app has in RAM right now; the list is sorted by it. Footprint, the \
        Memory column in Activity Monitor, is everything the app has allocated, with memory \
        macOS has compressed or moved to swap counted at full size, and Compressed + swap is \
        roughly the difference. That is why footprints can add up to more than the RAM installed.
        """

    public static let memHelp = "In RAM now (resident size). The list is sorted by this. Memory shared between processes counts in each of them."
    public static let compressedHelp = "Approximate: footprint minus what is in RAM. Memory macOS has compressed or moved to swap, counted at its full size."
    public static let footprintHelp = "Everything allocated, compressed and swapped memory included at full size. The Memory column in Activity Monitor."
    public static let residentNotReported = "This computad does not report memory in RAM, so the list is sorted by footprint. Update the daemon to see Mem."

    /// Under the Net tab's app list: how its rates relate to the chart above. Whether VPN
    /// traffic counts has not been checked, so the caption does not say.
    public static let networkCaption = "Rates by app count data only, without packet headers, so they add up to slightly less than the chart and trail it by about a second. Local (loopback) traffic is left out."
    public static let downHelp = "Received, in bytes per second."
    public static let upHelp = "Sent, in bytes per second."
}

/// The Mem tab's extra legend line.
public enum MemoryLegend {
    /// "9.7 GB holding 19.7 GB": the RAM the compressor occupies and the data it holds. Just
    /// the RAM figure when the daemon does not report the data held (an older daemon sends 0).
    public static func compressed(_ memory: MemorySample) -> String {
        let occupied = Format.memory(memory.compressedBytes)
        guard memory.compressorStoredBytes > 0 else { return occupied }
        return "\(occupied) holding \(Format.memory(memory.compressorStoredBytes))"
    }

    /// "22.2 of 23.5 GB", or "none" when there is no swap file.
    public static func swap(_ memory: MemorySample) -> String {
        guard memory.swapTotalBytes > 0 else { return "none" }
        return Format.memoryUsage(used: memory.swapUsedBytes, total: memory.swapTotalBytes, separator: " of ")
    }
}
