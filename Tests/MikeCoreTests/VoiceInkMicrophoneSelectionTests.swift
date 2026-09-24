import Testing
@testable import MikeCore

struct VoiceInkMicrophoneSelectionTests {
    private let antlion = AudioDeviceInfo(
        objectID: 1, name: "Antlion", uid: "antlion",
        inputChannelCount: 1, outputChannelCount: 0, supportsOutputMute: false
    )
    private let builtin = AudioDeviceInfo(
        objectID: 2, name: "MacBook", uid: "builtin",
        inputChannelCount: 1, outputChannelCount: 0, supportsOutputMute: false
    )
    private let blackHole = AudioDeviceInfo(
        objectID: 3, name: "BlackHole", uid: "blackhole",
        inputChannelCount: 2, outputChannelCount: 2, supportsOutputMute: true
    )

    @Test
    func resolvesPinnedDeviceByStableUID() {
        let selection = VoiceInkMicrophoneSelection(mode: .custom, customUID: "antlion")
        #expect(selection.resolve(among: [builtin, antlion], defaultInputUID: "builtin") == antlion)
    }

    @Test
    func doesNotGuessWhenPinnedDeviceDisconnects() {
        let selection = VoiceInkMicrophoneSelection(mode: .custom, customUID: "antlion")
        #expect(selection.resolve(among: [builtin], defaultInputUID: "builtin") == nil)
    }

    @Test
    func followsSystemDefaultInsteadOfStaleCustomPreference() {
        let selection = VoiceInkMicrophoneSelection(mode: .systemDefault, customUID: "antlion")
        #expect(selection.resolve(among: [builtin, antlion], defaultInputUID: "builtin") == builtin)
    }

    @Test
    func selectsFirstAvailablePriorityInOrder() {
        let selection = VoiceInkMicrophoneSelection(
            mode: .prioritized,
            priorities: [
                .init(id: "builtin", priority: 2),
                .init(id: "antlion", priority: 1),
            ]
        )
        #expect(selection.resolve(among: [builtin, antlion], defaultInputUID: nil) == antlion)
        #expect(selection.resolve(among: [builtin], defaultInputUID: nil) == builtin)
    }

    @Test
    func doesNotSelectOutputOnlyDeviceAsMicrophone() {
        let selection = VoiceInkMicrophoneSelection(mode: .custom, customUID: "blackhole")
        let outputOnly = AudioDeviceInfo(
            objectID: blackHole.objectID, name: blackHole.name, uid: blackHole.uid,
            inputChannelCount: 0, outputChannelCount: 2, supportsOutputMute: true
        )
        #expect(selection.resolve(among: [outputOnly], defaultInputUID: nil) == nil)
    }
}
