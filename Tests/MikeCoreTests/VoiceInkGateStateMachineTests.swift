import Testing
@testable import MikeCore

struct VoiceInkGateStateMachineTests {
    @Test
    func observedCaptureAcquiresAndTailDelayReleasesGate() {
        var machine = VoiceInkGateStateMachine(
            tailDelay: 0.2,
            pendingStartTimeout: 1.5
        )

        #expect(machine.observe(isCapturing: false, at: 0) == [])
        #expect(machine.observe(isCapturing: true, at: 1) == [.acquire])
        #expect(machine.observe(isCapturing: false, at: 2) == [])
        #expect(machine.observe(isCapturing: false, at: 2.19) == [])
        #expect(machine.observe(isCapturing: false, at: 2.2) == [.release])
    }

    @Test
    func prepareToggleAcquiresBeforeCaptureStarts() {
        var machine = VoiceInkGateStateMachine()

        _ = machine.observe(isCapturing: false, at: 0)

        #expect(machine.prepareToggle(at: 1) == [.acquire])
        #expect(machine.observe(isCapturing: true, at: 1.05) == [.acquire])
    }

    @Test
    func failedPendingStartRestoresGate() {
        var machine = VoiceInkGateStateMachine(
            tailDelay: 0.2,
            pendingStartTimeout: 1.5
        )

        _ = machine.observe(isCapturing: false, at: 0)
        _ = machine.prepareToggle(at: 1)

        #expect(machine.observe(isCapturing: false, at: 2.49) == [])
        #expect(machine.observe(isCapturing: false, at: 2.5) == [.release])
    }

    @Test
    func rapidRestartCancelsPendingRestore() {
        var machine = VoiceInkGateStateMachine(tailDelay: 0.2)

        _ = machine.observe(isCapturing: true, at: 0)
        _ = machine.observe(isCapturing: false, at: 1)

        #expect(machine.observe(isCapturing: true, at: 1.1) == [.acquire])
        #expect(machine.observe(isCapturing: true, at: 1.3) == [])
    }

    @Test
    func prepareToggleWhileCapturingDoesNotReleaseEarly() {
        var machine = VoiceInkGateStateMachine(tailDelay: 0.2)

        _ = machine.observe(isCapturing: true, at: 0)

        #expect(machine.prepareToggle(at: 1) == [])
        #expect(machine.observe(isCapturing: false, at: 1.05) == [])
        #expect(machine.observe(isCapturing: false, at: 1.25) == [.release])
    }
}
