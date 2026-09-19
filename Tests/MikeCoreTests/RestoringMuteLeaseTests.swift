import Testing
@testable import MikeCore

struct RestoringMuteLeaseTests {
    @Test
    func mutesAndRestoresAnInitiallyUnmutedDevice() throws {
        let controller = FakeMuteController(isMuted: false)
        let lease = RestoringMuteLease(controller: controller)

        try lease.acquire()
        #expect(controller.isCurrentlyMuted)

        try lease.release()
        #expect(!controller.isCurrentlyMuted)
        #expect(controller.assignedStates == [true, false])
    }

    @Test
    func preservesAnInitiallyMutedDevice() throws {
        let controller = FakeMuteController(isMuted: true)
        let lease = RestoringMuteLease(controller: controller)

        try lease.acquire()
        try lease.release()

        #expect(controller.isCurrentlyMuted)
        #expect(controller.assignedStates.isEmpty)
    }

    @Test
    func repeatedAcquireAndReleaseAreIdempotent() throws {
        let controller = FakeMuteController(isMuted: false)
        let lease = RestoringMuteLease(controller: controller)

        try lease.acquire()
        try lease.acquire()
        try lease.release()
        try lease.release()

        #expect(controller.assignedStates == [true, false])
    }

    @Test
    func retainsLeaseWhenRestorationFailsSoItCanRetry() throws {
        let controller = FakeMuteController(isMuted: false)
        let lease = RestoringMuteLease(controller: controller)

        try lease.acquire()
        controller.shouldFailNextAssignment = true

        #expect(throws: FakeMuteController.Error.assignmentFailed) {
            try lease.release()
        }
        #expect(lease.isHeld)
        #expect(controller.isCurrentlyMuted)

        try lease.release()
        #expect(!lease.isHeld)
        #expect(!controller.isCurrentlyMuted)
    }
}

private final class FakeMuteController: DeviceMuteControlling {
    enum Error: Swift.Error {
        case assignmentFailed
    }

    private(set) var isCurrentlyMuted: Bool
    private(set) var assignedStates: [Bool] = []
    var shouldFailNextAssignment = false

    init(isMuted: Bool) {
        isCurrentlyMuted = isMuted
    }

    func isMuted() throws -> Bool {
        isCurrentlyMuted
    }

    func setMuted(_ muted: Bool) throws {
        if shouldFailNextAssignment {
            shouldFailNextAssignment = false
            throw Error.assignmentFailed
        }
        isCurrentlyMuted = muted
        assignedStates.append(muted)
    }
}
