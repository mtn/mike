import CoreAudio

/// The stable identity and capabilities of one CoreAudio device.
public struct AudioDeviceInfo: Equatable, Sendable {
    public let objectID: AudioDeviceID
    public let name: String
    public let uid: String
    public let inputChannelCount: UInt32
    public let outputChannelCount: UInt32
    public let supportsOutputMute: Bool

    public init(
        objectID: AudioDeviceID,
        name: String,
        uid: String,
        inputChannelCount: UInt32,
        outputChannelCount: UInt32,
        supportsOutputMute: Bool
    ) {
        self.objectID = objectID
        self.name = name
        self.uid = uid
        self.inputChannelCount = inputChannelCount
        self.outputChannelCount = outputChannelCount
        self.supportsOutputMute = supportsOutputMute
    }
}
