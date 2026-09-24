import CoreAudio
import Foundation

/// VoiceInk's persisted input choice. This reflects its preference, not a live
/// recording session's device (which VoiceInk may change on disconnect).
public struct VoiceInkMicrophoneSelection: Sendable {
    public enum Mode: String, Sendable {
        case systemDefault = "System Default"
        case custom = "Custom Device"
        case prioritized = "Prioritized"
    }

    public struct Priority: Codable, Sendable {
        public let id: String
        public let priority: Int
    }

    public let mode: Mode
    public let customUID: String?
    public let priorities: [Priority]

    public init(mode: Mode, customUID: String? = nil, priorities: [Priority] = []) {
        self.mode = mode
        self.customUID = customUID
        self.priorities = priorities
    }

    public func resolve(
        among devices: [AudioDeviceInfo],
        defaultInputUID: String?
    ) -> AudioDeviceInfo? {
        let inputs = devices.filter { $0.inputChannelCount > 0 }
        switch mode {
        case .systemDefault:
            return inputs.first { $0.uid == defaultInputUID }
        case .custom:
            guard let customUID else { return nil }
            return inputs.first { $0.uid == customUID }
        case .prioritized:
            for item in priorities.sorted(by: { $0.priority < $1.priority }) {
                if let device = inputs.first(where: { $0.uid == item.id }) {
                    return device
                }
            }
            return nil
        }
    }
}

/// Reads VoiceInk preferences without changing VoiceInk or the system input.
public struct VoiceInkMicrophonePreferences {
    public static let domain = "com.prakashjoshipax.VoiceInk"

    public init() {}

    public func selection() -> VoiceInkMicrophoneSelection? {
        let domain = Self.domain as CFString
        CFPreferencesAppSynchronize(domain)

        let defaults = UserDefaults(suiteName: Self.domain)
        guard let rawMode = defaults?.string(forKey: "audioInputMode"),
            let mode = VoiceInkMicrophoneSelection.Mode(rawValue: rawMode)
        else {
            return nil
        }
        let priorityData = defaults?.data(forKey: "prioritizedDevices")
        let priorities =
            priorityData.flatMap {
                try? JSONDecoder().decode([VoiceInkMicrophoneSelection.Priority].self, from: $0)
            } ?? []
        return VoiceInkMicrophoneSelection(
            mode: mode,
            customUID: defaults?.string(forKey: "selectedAudioDeviceUID"),
            priorities: priorities
        )
    }
}
