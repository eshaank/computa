import Foundation

/// A session's, tab's or pane's memory, as the Sessions tab shows it.
///
/// "Mem" means resident size: what is in RAM now. Footprint also counts memory macOS has
/// compressed or moved to swap, so footprints can add up to more than the RAM installed; it is
/// the second, labelled figure.
public struct SessionMemory: Sendable, Equatable {
    /// In RAM now. Nil when unknown: a daemon too old to send resident sizes, with no processes
    /// to add them up from.
    public var resident: UInt64?
    public var footprint: UInt64

    public init(resident: UInt64?, footprint: UInt64) {
        self.resident = resident
        self.footprint = footprint
    }

    /// The figure shown first: resident, or the footprint when resident is unknown.
    public var shownBytes: UInt64 { resident ?? footprint }

    /// True when `shownBytes` is the footprint, so it must be labelled "Footprint", not "Mem".
    public var isFootprintOnly: Bool { resident == nil }

    /// Picks the resident figure: the one the daemon reported, else the parts added up, else
    /// nothing. A real zero (no footprint either) stays a zero; a zero beside a footprint does not,
    /// because that is an older daemon saying nothing, not an empty pane.
    static func resolved(reported: UInt64, parts: UInt64?, footprint: UInt64) -> SessionMemory {
        if reported > 0 { return SessionMemory(resident: reported, footprint: footprint) }
        if let parts, parts > 0 { return SessionMemory(resident: parts, footprint: footprint) }
        return SessionMemory(resident: footprint == 0 ? 0 : nil, footprint: footprint)
    }

    /// Added up. The resident total is known only when every part's is, so a total never mixes
    /// resident sizes with footprints.
    public static func total(_ parts: [SessionMemory]) -> SessionMemory {
        var resident: UInt64? = 0
        var footprint: UInt64 = 0
        for part in parts {
            footprint += part.footprint
            if let known = resident, let more = part.resident { resident = known + more } else { resident = nil }
        }
        return SessionMemory(resident: resident, footprint: footprint)
    }
}

extension RexPane {
    /// Resident from the daemon, else added up over the pane's processes, which have carried
    /// resident sizes for longer than panes have.
    public var memory: SessionMemory {
        let parts: UInt64? = processes.isEmpty ? nil : processes.reduce(0) { $0 + $1.residentBytes }
        return .resolved(reported: residentBytes, parts: parts, footprint: memoryBytes)
    }
}

extension RexTab {
    public var memory: SessionMemory {
        .resolved(reported: residentBytes, parts: SessionMemory.total(panes.map(\.memory)).resident, footprint: memoryBytes)
    }
}

extension RexSession {
    public var memory: SessionMemory {
        .resolved(reported: residentBytes, parts: SessionMemory.total(tabs.map(\.memory)).resident, footprint: memoryBytes)
    }
}
