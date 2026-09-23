import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class MikeModel {
    private static let preferredInputNames = [
        "Antlion Wireless Microphone",
        "MacBook Pro Microphone",
    ]
    private static let preferredOutputUID = "BlackHole2ch_UID"

    var errorMessage: String?
    var callFeedStatus = "Open"
    var inputDevices: [AudioDeviceInfo] = []
    var isCallFeedMuted = false
    var isRouting = false
    var isStarting = false
    var isVoiceInkCapturing = false
    var outputDevices: [AudioDeviceInfo] = []
    var selectedInputUID = ""
    var selectedOutputUID = ""
    var status = "Not routing"
    var metricsStatus = "Waiting for samples…"

    private var gateLease: RestoringMuteLease<CoreAudioDeviceMuteController>?
    private var gateStateMachine = VoiceInkGateStateMachine()
    private var gateTask: Task<Void, Never>?
    private let karabinerService = KarabinerCommandService()
    private var karabinerTask: Task<Void, Never>?
    private var metricsTask: Task<Void, Never>?
    private var router: AudioQueueMicrophoneRouter?
    private var startupTask: Task<Void, Never>?

    init() {
        karabinerTask = Task { [weak self, karabinerService] in
            await MikeCommandBus.shared.install {
                self?.prepareVoiceInkToggle()
            }

            do {
                try await karabinerService.start()
            } catch {
                guard let self else {
                    return
                }
                self.errorMessage =
                    "Karabiner integration failed: \(error.localizedDescription)"
            }
        }
    }

    var menuBarIcon: String {
        if isCallFeedMuted {
            return "mic.slash.fill"
        }
        return isRouting ? "mic.and.signal.meter.fill" : "mic.slash"
    }

    func refreshDevices() {
        do {
            let devices = try CoreAudioDeviceInspector().devices()
            inputDevices = devices.filter { device in
                device.inputChannelCount > 0
                    && device.uid != Self.preferredOutputUID
            }
            outputDevices = devices.filter { device in
                device.uid == Self.preferredOutputUID
            }

            selectDefaultsIfNeeded()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleRouting() {
        guard !isStarting else {
            return
        }

        if isRouting {
            stopRouting()
        } else {
            isStarting = true
            startupTask = Task { [weak self] in
                guard let self else {
                    return
                }
                await self.startRouting()
                self.isStarting = false
                self.startupTask = nil
            }
        }
    }

    private func startRouting() async {
        errorMessage = nil
        status = "Requesting microphone access…"

        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            status = "Microphone access denied"
            errorMessage = "Enable Mike in System Settings → Privacy & Security → Microphone."
            return
        }

        guard
            let inputDevice = inputDevices.first(where: {
                $0.uid == selectedInputUID
            })
        else {
            status = "Not routing"
            errorMessage = "Select an available physical microphone."
            return
        }
        guard
            let outputDevice = outputDevices.first(where: {
                $0.uid == selectedOutputUID
            })
        else {
            status = "Not routing"
            errorMessage = "BlackHole 2ch is not available."
            return
        }

        do {
            let router = AudioQueueMicrophoneRouter(
                inputDevice: inputDevice,
                outputDevice: outputDevice
            )
            try router.start()
            let gateController = try CoreAudioDeviceMuteController(
                device: outputDevice
            )
            self.router = router
            gateLease = RestoringMuteLease(controller: gateController)
            gateStateMachine = VoiceInkGateStateMachine()
            isRouting = true
            status = "\(inputDevice.name) → \(outputDevice.name)"
            startVoiceInkWatcher()
            startMetricsUpdates()
        } catch {
            status = "Not routing"
            errorMessage = error.localizedDescription
        }
    }

    private func stopRouting() {
        startupTask?.cancel()
        startupTask = nil
        isStarting = false
        gateTask?.cancel()
        gateTask = nil
        metricsTask?.cancel()
        metricsTask = nil

        do {
            try gateLease?.release()
        } catch {
            errorMessage = "Could not restore the call feed: \(error.localizedDescription)"
        }
        gateLease = nil
        gateStateMachine = VoiceInkGateStateMachine()
        isCallFeedMuted = false
        isVoiceInkCapturing = false
        callFeedStatus = "Open"

        router?.stop()
        router = nil
        isRouting = false
        status = "Not routing"
        metricsStatus = "Waiting for samples…"
    }

    func shutdown() {
        stopRouting()
        karabinerTask?.cancel()
        karabinerTask = nil

        let service = karabinerService
        Task {
            await service.stop()
            await MikeCommandBus.shared.removeHandler()
        }
    }

    private func prepareVoiceInkToggle() {
        guard isRouting else {
            return
        }

        do {
            let actions = gateStateMachine.prepareToggle(
                at: Date().timeIntervalSinceReferenceDate
            )
            try applyGateActions(actions)
        } catch {
            errorMessage =
                "Could not prepare the call feed: \(error.localizedDescription)"
        }
    }

    private func startVoiceInkWatcher() {
        gateTask?.cancel()
        gateTask = Task { [weak self] in
            let inspector = CoreAudioProcessInspector()

            while !Task.isCancelled {
                do {
                    let capturing = try inspector.isCapturing(
                        bundleID: "com.prakashjoshipax.VoiceInk"
                    )
                    guard let self else {
                        return
                    }
                    let actions = self.gateStateMachine.observe(
                        isCapturing: capturing,
                        at: Date().timeIntervalSinceReferenceDate
                    )
                    self.isVoiceInkCapturing = capturing
                    try self.applyGateActions(actions)
                } catch {
                    guard let self else {
                        return
                    }
                    self.errorMessage = "VoiceInk monitoring failed: \(error.localizedDescription)"
                }

                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func applyGateActions(
        _ actions: [VoiceInkGateAction]
    ) throws {
        for action in actions {
            switch action {
            case .acquire:
                try gateLease?.acquire()
            case .release:
                try gateLease?.release()
            }
        }

        isCallFeedMuted = gateLease?.isHeld == true
        callFeedStatus =
            isCallFeedMuted
            ? "Muted while VoiceInk is recording"
            : "Open"
    }

    private func startMetricsUpdates() {
        metricsTask?.cancel()
        metricsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, let metrics = self.router?.metrics else {
                    return
                }
                let bufferedMilliseconds =
                    Double(metrics.availableFrames) / 48
                self.metricsStatus =
                    "Buffered "
                    + bufferedMilliseconds.formatted(
                        .number.precision(.fractionLength(1))
                    )
                    + " ms • dropped \(metrics.droppedInputFrames) • "
                    + "underrun \(metrics.silentOutputFrames)"
            }
        }
    }

    private func selectDefaultsIfNeeded() {
        if !inputDevices.contains(where: { $0.uid == selectedInputUID }) {
            selectedInputUID =
                Self.preferredInputNames.lazy.compactMap { preferredName in
                    self.inputDevices.first(where: {
                        $0.name == preferredName
                    })?.uid
                }.first ?? inputDevices.first?.uid ?? ""
        }

        if !outputDevices.contains(where: { $0.uid == selectedOutputUID }) {
            selectedOutputUID =
                outputDevices.first(where: {
                    $0.uid == Self.preferredOutputUID
                })?.uid ?? outputDevices.first?.uid ?? ""
        }
    }
}
