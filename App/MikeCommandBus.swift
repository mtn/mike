actor MikeCommandBus {
    static let shared = MikeCommandBus()

    typealias Handler = @MainActor @Sendable () -> Void

    private var prepareVoiceInkToggleHandler: Handler?

    func install(prepareVoiceInkToggle: @escaping Handler) {
        prepareVoiceInkToggleHandler = prepareVoiceInkToggle
    }

    func removeHandler() {
        prepareVoiceInkToggleHandler = nil
    }

    func prepareVoiceInkToggle() async {
        await prepareVoiceInkToggleHandler?()
    }
}
