/// Temporarily mutes a device and restores only the state this lease changed.
public final class RestoringMuteLease<Controller: DeviceMuteControlling> {
    private let controller: Controller
    private var shouldUnmuteOnRelease = false

    public private(set) var isHeld = false

    public init(controller: Controller) {
        self.controller = controller
    }

    public func acquire() throws {
        guard !isHeld else {
            return
        }

        let wasMuted = try controller.isMuted()
        if !wasMuted {
            try controller.setMuted(true)
        }

        shouldUnmuteOnRelease = !wasMuted
        isHeld = true
    }

    public func release() throws {
        guard isHeld else {
            return
        }

        if shouldUnmuteOnRelease {
            try controller.setMuted(false)
        }

        shouldUnmuteOnRelease = false
        isHeld = false
    }
}
