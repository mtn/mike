import Foundation
import KarabinerElementsUserCommandReceiver
import OSLog

final class KarabinerCommandService: Sendable {
    static let endpoint = "/tmp/com.mtn.mike-karabiner.sock"

    private static let logger = Logger(
        subsystem: "com.mtn.mike",
        category: "karabiner"
    )

    private let receiver: KEUserCommandReceiver

    init() {
        receiver = KEUserCommandReceiver(
            path: Self.endpoint,
            onJSON: { json in
                guard
                    let payload = json as? [String: Any],
                    payload["command"] as? String
                        == "prepare_voiceink_toggle"
                else {
                    return
                }

                Task {
                    await MikeCommandBus.shared.prepareVoiceInkToggle()
                }
            },
            onError: { error in
                Self.logger.error(
                    "Karabiner command receiver failed: \(error.localizedDescription)"
                )
            }
        )
    }

    func start() async throws {
        try await receiver.start()
    }

    func stop() async {
        await receiver.stop()
    }
}
