import CoreAudio

/// The stable identity and capabilities of one CoreAudio device.
public struct AudioDeviceInfo: Equatable, Sendable {
    public let objectID: AudioDeviceID
    public let name: String
    public let uid: String
    public let supportsOutputMute: Bool

    public init(
        objectID: AudioDeviceID,
        name: String,
        uid: String,
        supportsOutputMute: Bool
    ) {
        self.objectID = objectID
        self.name = name
        self.uid = uid
        self.supportsOutputMute = supportsOutputMute
    }
}
