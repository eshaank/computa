import ComputaCore
import ComputaUI
import Foundation
import IOKit.pwr_mgt
import Testing

/// Uses the real power management API: the assertion must show up for this process while held
/// and be gone after release.
@Suite(.serialized) struct IOKitSleepPreventerTests {
    /// Names of the assertions this process holds, as `pmset -g assertions` would list them.
    func heldAssertionNames() -> [String] {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let all = byProcess?.takeRetainedValue() as? [Int: [[String: Any]]]
        else { return [] }
        let mine = all[Int(ProcessInfo.processInfo.processIdentifier)] ?? []
        return mine.compactMap { $0[kIOPMAssertionNameKey as String] as? String }
    }

    @Test func acquiredAssertionIsHeldUntilReleased() throws {
        let preventer = IOKitSleepPreventer()
        let assertion = try preventer.acquire()
        #expect(heldAssertionNames().contains(IOKitSleepPreventer.assertionName))
        try preventer.release(assertion)
        #expect(!heldAssertionNames().contains(IOKitSleepPreventer.assertionName))
    }

    @Test func releasingAnUnknownAssertionFails() {
        #expect(throws: IOKitSleepPreventer.Failure.self) {
            try IOKitSleepPreventer().release(0xDEAD_BEEF)
        }
    }

    @MainActor
    @Test func modelWithTheRealPreventerHoldsExactlyOneAssertion() {
        let model = SleepPreventionModel(preventer: IOKitSleepPreventer())
        model.set(on: true)
        model.set(on: true)
        #expect(model.isOn)
        #expect(heldAssertionNames().filter { $0 == IOKitSleepPreventer.assertionName }.count == 1)
        model.set(on: false)
        #expect(!model.isOn)
        #expect(!heldAssertionNames().contains(IOKitSleepPreventer.assertionName))
    }
}
