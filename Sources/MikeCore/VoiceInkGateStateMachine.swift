import Foundation

public enum VoiceInkGateAction: Equatable, Sendable {
    case acquire
    case release
}

/// Coordinates immediate pre-muting with VoiceInk's observed capture state.
public struct VoiceInkGateStateMachine: Sendable {
    public let pendingStartTimeout: TimeInterval
    public let tailDelay: TimeInterval

    public private(set) var isCapturing: Bool?

    private var pendingStartDeadline: TimeInterval?
    private var restoreDeadline: TimeInterval?

    public init(
        tailDelay: TimeInterval = 0.2,
        pendingStartTimeout: TimeInterval = 1.5
    ) {
        self.tailDelay = tailDelay
        self.pendingStartTimeout = pendingStartTimeout
    }

    /// Prepares for the same toggle shortcut starting or stopping VoiceInk.
    ///
    /// When VoiceInk is idle, the call feed closes before the shortcut is
    /// forwarded. When it is already active, its existing gate remains held
    /// until CoreAudio confirms that capture stopped.
    public mutating func prepareToggle(
        at time: TimeInterval
    ) -> [VoiceInkGateAction] {
        guard isCapturing != true else {
            return []
        }

        pendingStartDeadline = time + pendingStartTimeout
        restoreDeadline = nil
        return [.acquire]
    }

    /// Observes VoiceInk's current CoreAudio input state and returns gate work.
    public mutating func observe(
        isCapturing newValue: Bool,
        at time: TimeInterval
    ) -> [VoiceInkGateAction] {
        var actions: [VoiceInkGateAction] = []

        if newValue != isCapturing {
            let previousValue = isCapturing
            isCapturing = newValue

            if newValue {
                pendingStartDeadline = nil
                restoreDeadline = nil
                actions.append(.acquire)
            } else if previousValue == true {
                restoreDeadline = time + tailDelay
            }
        }

        guard !newValue else {
            return actions
        }

        if let restoreDeadline, time >= restoreDeadline {
            self.restoreDeadline = nil
            pendingStartDeadline = nil
            actions.append(.release)
        } else if let pendingStartDeadline, time >= pendingStartDeadline {
            self.pendingStartDeadline = nil
            actions.append(.release)
        }

        return actions
    }
}
