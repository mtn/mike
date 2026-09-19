/// A deduplicated observation emitted by ``CaptureStateTracker``.
public enum CaptureStateChange: Equatable, Sendable {
    case initial(isCapturing: Bool)
    case started
    case stopped
}

/// Turns repeated capture-state samples into meaningful transitions.
///
/// CoreAudio can report the same state many times. Keeping deduplication in a
/// small value type prevents those repeated observations from reaching the
/// eventual gate and menu-bar UI.
public struct CaptureStateTracker: Sendable {
    private var previousState: Bool?

    public init() {}

    public mutating func observe(isCapturing: Bool) -> CaptureStateChange? {
        guard let previousState else {
            self.previousState = isCapturing
            return .initial(isCapturing: isCapturing)
        }

        guard previousState != isCapturing else {
            return nil
        }

        self.previousState = isCapturing
        return isCapturing ? .started : .stopped
    }
}
