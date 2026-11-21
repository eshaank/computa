import Observation
import os

/// Holds and releases the power assertion that keeps this Mac awake.
public protocol SleepPreventing: AnyObject {
    /// Creates an assertion and returns its identifier.
    func acquire() throws -> UInt32
    /// Releases an assertion made by `acquire`.
    func release(_ assertion: UInt32) throws
}

/// The Prevent Sleep switch. It is on only while an assertion is held.
@MainActor
@Observable
public final class SleepPreventionModel {
    /// True exactly when an assertion is held.
    public var isOn: Bool { assertion != nil }
    /// The last failure, in words, until it is cleared.
    public private(set) var lastError: String?

    private var assertion: UInt32?
    @ObservationIgnored private let preventer: any SleepPreventing
    @ObservationIgnored private let logger = Logger(subsystem: "app.computa.Computa", category: "sleep")

    public init(preventer: any SleepPreventing) {
        self.preventer = preventer
    }

    /// Turns prevention on or off. Asking for the state it is already in does nothing.
    public func set(on: Bool) {
        if on { turnOn() } else { turnOff() }
    }

    /// Forgets the last failure message.
    public func clearError() {
        lastError = nil
    }

    private func turnOn() {
        guard assertion == nil else { return }
        do {
            assertion = try preventer.acquire()
            lastError = nil
            logger.info("prevent sleep on (assertion \(self.assertion ?? 0))")
        } catch {
            logger.error("could not create the prevent-sleep assertion: \(error)")
            lastError = "Could not keep this Mac awake: \(error)"
        }
    }

    private func turnOff() {
        guard let held = assertion else { return }
        do {
            try preventer.release(held)
            assertion = nil
            lastError = nil
            logger.info("prevent sleep off (released assertion \(held))")
        } catch {
            // The assertion may still be held, so the switch stays on and says why.
            logger.error("could not release prevent-sleep assertion \(held): \(error)")
            lastError = "Could not release the assertion: \(error)"
        }
    }
}
