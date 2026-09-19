import CoreAudio

/// Controls the output mute property of one CoreAudio device.
///
/// BlackHole uses this output property to decide whether readers of its input
/// receive routed samples or digital silence.
public struct CoreAudioDeviceMuteController: DeviceMuteControlling, Sendable {
    public let device: AudioDeviceInfo

    public init(device: AudioDeviceInfo) throws {
        guard device.supportsOutputMute else {
            throw CoreAudioError.muteNotSupported(device.name)
        }
        self.device = device
    }

    public func isMuted() throws -> Bool {
        var address = muteAddress()
        var value: UInt32 = 0
        var byteCount = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            device.objectID,
            &address,
            0,
            nil,
            &byteCount,
            &value
        )
        guard status == noErr else {
            throw CoreAudioError.propertyData(
                selector: address.mSelector,
                status: status
            )
        }
        return value != 0
    }

    public func setMuted(_ muted: Bool) throws {
        var address = muteAddress()
        var value: UInt32 = muted ? 1 : 0
        let byteCount = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectSetPropertyData(
            device.objectID,
            &address,
            0,
            nil,
            byteCount,
            &value
        )
        guard status == noErr else {
            throw CoreAudioError.propertyData(
                selector: address.mSelector,
                status: status
            )
        }
    }

    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
