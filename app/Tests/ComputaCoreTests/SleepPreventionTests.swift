import Testing

@testable import ComputaCore

final class FakeSleepPreventer: SleepPreventing {
    struct Failure: Error, CustomStringConvertible { var description: String }

    var acquireCalls = 0
    var released: [UInt32] = []
    var failAcquire = false
    var failRelease = false

    func acquire() throws -> UInt32 {
        acquireCalls += 1
        if failAcquire { throw Failure(description: "IOPMAssertionCreateWithName returned 0xe00002c2") }
        return UInt32(100 + acquireCalls)
    }

    func release(_ assertion: UInt32) throws {
        if failRelease { throw Failure(description: "release failed") }
        released.append(assertion)
    }
}

@MainActor
@Suite struct SleepPreventionTests {
    @Test func startsOff() {
        let model = SleepPreventionModel(preventer: FakeSleepPreventer())
        #expect(!model.isOn)
        #expect(model.lastError == nil)
    }

    @Test func turningOnAcquiresOnce() {
        let fake = FakeSleepPreventer()
        let model = SleepPreventionModel(preventer: fake)
        model.set(on: true)
        #expect(model.isOn)
        #expect(fake.acquireCalls == 1)
    }

    @Test func turningOnTwiceHoldsOneAssertion() {
        let fake = FakeSleepPreventer()
        let model = SleepPreventionModel(preventer: fake)
        model.set(on: true)
        model.set(on: true)
        #expect(fake.acquireCalls == 1)
        model.set(on: false)
        #expect(fake.released == [101])
    }

    @Test func failingAcquireLeavesItOffAndRecordsTheError() {
        let fake = FakeSleepPreventer()
        fake.failAcquire = true
        let model = SleepPreventionModel(preventer: fake)
        model.set(on: true)
        #expect(!model.isOn)
        #expect(model.lastError?.contains("0xe00002c2") == true)

        // A later success clears the message.
        fake.failAcquire = false
        model.set(on: true)
        #expect(model.isOn)
        #expect(model.lastError == nil)
    }

    @Test func turningOffReleasesTheHeldAssertion() {
        let fake = FakeSleepPreventer()
        let model = SleepPreventionModel(preventer: fake)
        model.set(on: true)
        model.set(on: false)
        #expect(!model.isOn)
        #expect(fake.released == [101])
        model.set(on: false)
        #expect(fake.released == [101], "turning off when off releases nothing")
    }

    @Test func failingReleaseKeepsItOnBecauseTheAssertionMayStillBeHeld() {
        let fake = FakeSleepPreventer()
        let model = SleepPreventionModel(preventer: fake)
        model.set(on: true)
        fake.failRelease = true
        model.set(on: false)
        #expect(model.isOn)
        #expect(model.lastError != nil)
    }
}
