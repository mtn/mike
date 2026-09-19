import CoreAudio
import Foundation

/// Reads per-process microphone activity from the CoreAudio hardware service.
public struct CoreAudioProcessInspector: Sendable {
    public init() {}

    public func processes() throws -> [AudioProcessInfo] {
        guard #available(macOS 14.2, *) else {
            throw CoreAudioError.unsupportedOperatingSystem
        }

        return try readProcessObjectList().compactMap(readProcess)
    }

    public func isCapturing(bundleID: String) throws -> Bool {
        try processes().contains {
            $0.bundleID == bundleID && $0.isRunningInput
        }
    }

    @available(macOS 14.2, *)
    private func readProcessObjectList() throws -> [AudioObjectID] {
        var address = propertyAddress(kAudioHardwarePropertyProcessObjectList)
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

        var objects = [AudioObjectID](
            repeating: 0,
            count: Int(byteCount) / MemoryLayout<AudioObjectID>.size
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

    @available(macOS 14.2, *)
    private func readProcess(_ objectID: AudioObjectID) -> AudioProcessInfo? {
        // A process can disappear between reading the object list and reading
        // its properties. Skip that stale object instead of failing the scan.
        guard let processID = try? readProcessID(from: objectID) else {
            return nil
        }

        let isRunning =
            (try? readUInt32(
                from: objectID,
                selector: kAudioProcessPropertyIsRunningInput
            )) ?? 0

        return AudioProcessInfo(
            objectID: objectID,
            processID: processID,
            bundleID: try? readBundleID(from: objectID),
            isRunningInput: isRunning == 1
        )
    }

    @available(macOS 14.2, *)
    private func readProcessID(from objectID: AudioObjectID) throws -> pid_t {
        var address = propertyAddress(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var byteCount = UInt32(MemoryLayout<pid_t>.size)

        let status = AudioObjectGetPropertyData(
            objectID,
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
        return value
    }

    @available(macOS 14.2, *)
    private func readUInt32(
        from objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> UInt32 {
        var address = propertyAddress(selector)
        var value: UInt32 = 0
        var byteCount = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &byteCount,
            &value
        )
        guard status == noErr else {
            throw CoreAudioError.propertyData(selector: selector, status: status)
        }
        return value
    }

    @available(macOS 14.2, *)
    private func readBundleID(from objectID: AudioObjectID) throws -> String? {
        var address = propertyAddress(kAudioProcessPropertyBundleID)
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
        guard status == noErr else {
            throw CoreAudioError.propertyData(
                selector: address.mSelector,
                status: status
            )
        }

        return value?.takeRetainedValue() as String?
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
}
