import ComputaCore
import IOKit.pwr_mgt

/// Keeps this Mac from idle-sleeping with an IOKit power assertion. macOS also drops the
/// assertion if the process exits.
public final class IOKitSleepPreventer: SleepPreventing {
    /// Shown by `pmset -g assertions` next to the process name.
    public static let assertionName = "Computa: Prevent Sleep"

    public struct Failure: Error, CustomStringConvertible {
        public let call: String
        public let code: IOReturn

        public var description: String {
            "\(call) failed (0x\(String(UInt32(bitPattern: code), radix: 16)))"
        }
    }

    public init() {}

    public func acquire() throws -> UInt32 {
        var assertion = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.assertionName as CFString,
            &assertion
        )
        guard result == kIOReturnSuccess else {
            throw Failure(call: "IOPMAssertionCreateWithName", code: result)
        }
        return assertion
    }

    public func release(_ assertion: UInt32) throws {
        let result = IOPMAssertionRelease(assertion)
        guard result == kIOReturnSuccess else {
            throw Failure(call: "IOPMAssertionRelease", code: result)
        }
    }
}
