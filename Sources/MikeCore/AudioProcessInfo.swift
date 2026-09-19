import CoreAudio

/// The microphone-capture state CoreAudio reports for one process.
public struct AudioProcessInfo: Equatable, Sendable {
    public let objectID: AudioObjectID
    public let processID: pid_t
    public let bundleID: String?
    public let isRunningInput: Bool

    public init(
        objectID: AudioObjectID,
        processID: pid_t,
        bundleID: String?,
        isRunningInput: Bool
    ) {
        self.objectID = objectID
        self.processID = processID
        self.bundleID = bundleID
        self.isRunningInput = isRunningInput
    }
}
