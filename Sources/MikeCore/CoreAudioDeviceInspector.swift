import CoreAudio
import Foundation

/// Discovers CoreAudio devices without changing the system defaults.
public struct CoreAudioDeviceInspector: Sendable {
    public init() {}

    public func devices() throws -> [AudioDeviceInfo] {
        try readDeviceObjectList().compactMap(readDevice)
    }

    public func device(named name: String) throws -> AudioDeviceInfo {
        guard let device = try devices().first(where: { $0.name == name }) else {
            throw CoreAudioError.audioDeviceNotFound(name)
        }
        return device
    }

    private func readDeviceObjectList() throws -> [AudioDeviceID] {
        var address = propertyAddress(kAudioHardwarePropertyDevices)
        var byteCount: UInt32 = 0

        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &byteCount
        )
        guard sizeStatus == noErr else {
            throw CoreAudioError.propertyDataSize(
                selector: address.mSelector,
                status: sizeStatus
            )
        }

        guard byteCount > 0 else {
            return []
        }

        var objects = [AudioDeviceID](
            repeating: 0,
            count: Int(byteCount) / MemoryLayout<AudioDeviceID>.size
        )
        let dataStatus = objects.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &byteCount,
                buffer.baseAddress!
            )
        }
        guard dataStatus == noErr else {
            throw CoreAudioError.propertyData(
                selector: address.mSelector,
                status: dataStatus
            )
        }

        return objects
    }

    private func readDevice(_ objectID: AudioDeviceID) -> AudioDeviceInfo? {
        guard
            let name = try? readString(
                from: objectID,
                selector: kAudioObjectPropertyName
            ),
            let uid = try? readString(
                from: objectID,
                selector: kAudioDevicePropertyDeviceUID
            )
        else {
            return nil
        }

        var muteAddress = outputMuteAddress()
        return AudioDeviceInfo(
            objectID: objectID,
            name: name,
            uid: uid,
            inputChannelCount: readChannelCount(
                from: objectID,
                scope: kAudioDevicePropertyScopeInput
            ),
            outputChannelCount: readChannelCount(
                from: objectID,
                scope: kAudioDevicePropertyScopeOutput
            ),
            supportsOutputMute: AudioObjectHasProperty(objectID, &muteAddress)
        )
    }

    private func readChannelCount(
        from objectID: AudioObjectID,
        scope: AudioObjectPropertyScope
    ) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var byteCount = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &byteCount,
            &format
        )
        return status == noErr ? format.mChannelsPerFrame : 0
    }

    private func readString(
        from objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> String {
        var address = propertyAddress(selector)
        var value: Unmanaged<CFString>?
        var byteCount = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &byteCount,
            &value
        )
        guard status == noErr, let value else {
            throw CoreAudioError.propertyData(selector: selector, status: status)
        }
        return value.takeRetainedValue() as String
    }

    private func propertyAddress(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func outputMuteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
