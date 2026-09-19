import CoreAudio
import Foundation

public enum CoreAudioError: Error, LocalizedError, Equatable {
    case unsupportedOperatingSystem
    case propertyDataSize(selector: AudioObjectPropertySelector, status: OSStatus)
    case propertyData(selector: AudioObjectPropertySelector, status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unsupportedOperatingSystem:
            return "CoreAudio process inspection requires macOS 14.2 or later."
        case .propertyDataSize(let selector, let status):
            return "Could not read the size of CoreAudio property \(fourCC(selector)): \(format(status))."
        case .propertyData(let selector, let status):
            return "Could not read CoreAudio property \(fourCC(selector)): \(format(status))."
        }
    }

    private func format(_ status: OSStatus) -> String {
        let code = fourCC(UInt32(bitPattern: status))
        return code.contains(where: { !$0.isASCII || $0.isWhitespace })
            ? String(status)
            : "'\(code)' (\(status))"
    }

    private func fourCC(_ value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? String(value)
    }
}
