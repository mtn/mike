import Darwin
import Foundation
import MikeCore

private struct Configuration {
    static let defaultDeviceName = "BlackHole 2ch"
    static let voiceInkBundleID = "com.prakashjoshipax.VoiceInk"

    enum Command: String {
        case list
        case mute
        case status
        case unmute
        case watch
    }

    var command: Command
    var deviceName = defaultDeviceName
    var interval: TimeInterval = 0.05
    var tailDelay: TimeInterval = 0.2

    static func parse(_ arguments: ArraySlice<String>) throws -> Configuration {
        guard let commandArgument = arguments.first,
            let command = Command(rawValue: commandArgument)
        else {
            throw ArgumentError.missingCommand
        }

        var configuration = Configuration(command: command)
        var index = arguments.index(after: arguments.startIndex)

        while index < arguments.endIndex {
            let argument = arguments[index]
            switch argument {
            case "--device":
                index = arguments.index(after: index)
                guard index < arguments.endIndex else {
                    throw ArgumentError.missingValue(argument)
                }
                configuration.deviceName = arguments[index]
            case "--interval-ms":
                configuration.interval = try milliseconds(
                    following: argument,
                    arguments: arguments,
                    index: &index
                )
            case "--tail-ms":
                configuration.tailDelay = try milliseconds(
                    following: argument,
                    arguments: arguments,
                    index: &index
                )
            case "--help", "-h":
                printUsage()
                exit(EXIT_SUCCESS)
            default:
                throw ArgumentError.unknownArgument(argument)
            }
            index = arguments.index(after: index)
        }

        return configuration
    }

    private static func milliseconds(
        following argument: String,
        arguments: ArraySlice<String>,
        index: inout ArraySlice<String>.Index
    ) throws -> TimeInterval {
        index = arguments.index(after: index)
        guard index < arguments.endIndex,
            let value = Double(arguments[index]),
            value >= 10
        else {
            throw ArgumentError.invalidMilliseconds(argument)
        }
        return value / 1_000
    }
}

private enum ArgumentError: Error, LocalizedError {
    case invalidMilliseconds(String)
    case missingCommand
    case missingValue(String)
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case .invalidMilliseconds(let argument):
            return "\(argument) must be a number of at least 10."
        case .missingCommand:
            return "A command is required."
        case .missingValue(let argument):
            return "\(argument) requires a value."
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        }
    }
}

private func printUsage() {
    print(
        """
        Usage: mike-gate <command> [options]

        Commands:
          list                 List CoreAudio devices and mute support
          status               Print the target device's mute state
          mute                 Mute the target device
          unmute               Unmute the target device
          watch                Gate the target device while VoiceInk captures

        Options:
          --device NAME        Target device (default: \(Configuration.defaultDeviceName))
          --interval-ms MS     VoiceInk polling interval (default: 50)
          --tail-ms MS         Delay before restoring the gate (default: 200)
          -h, --help           Show this help
        """
    )
}

private func timestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func makeStopSemaphore() -> (DispatchSemaphore, [DispatchSourceSignal]) {
    let semaphore = DispatchSemaphore(value: 0)
    let sources = [SIGINT, SIGTERM].map { signalNumber in
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(
            signal: signalNumber,
            queue: .global(qos: .userInitiated)
        )
        source.setEventHandler {
            semaphore.signal()
        }
        source.resume()
        return source
    }
    return (semaphore, sources)
}

private func watch(
    configuration: Configuration,
    controller: CoreAudioDeviceMuteController
) throws {
    let inspector = CoreAudioProcessInspector()
    let lease = RestoringMuteLease(controller: controller)
    let (stopSemaphore, signalSources) = makeStopSemaphore()
    var tracker = CaptureStateTracker()
    var restoreAt: Date?

    // Keep the signal sources alive until this function exits.
    withExtendedLifetime(signalSources) {
        print(
            "Watching \(Configuration.voiceInkBundleID); gating \(controller.device.name). "
                + "Press Control-C to stop."
        )

        defer {
            do {
                try lease.release()
            } catch {
                fputs("mike-gate: could not restore mute state: \(error.localizedDescription)\n", stderr)
            }
        }

        while stopSemaphore.wait(timeout: .now() + configuration.interval) == .timedOut {
            do {
                let isCapturing = try inspector.isCapturing(
                    bundleID: Configuration.voiceInkBundleID
                )
                if let change = tracker.observe(isCapturing: isCapturing) {
                    switch change {
                    case .initial(let capturing):
                        if capturing {
                            try lease.acquire()
                            print("\(timestamp()) VoiceInk already capturing; gate closed")
                        } else {
                            print("\(timestamp()) VoiceInk idle; gate unchanged")
                        }
                    case .started:
                        restoreAt = nil
                        try lease.acquire()
                        print("\(timestamp()) VoiceInk started; gate closed")
                    case .stopped:
                        restoreAt = Date().addingTimeInterval(configuration.tailDelay)
                        print("\(timestamp()) VoiceInk stopped; waiting to restore gate")
                    }
                    fflush(stdout)
                }

                if let deadline = restoreAt, Date() >= deadline, !isCapturing {
                    try lease.release()
                    restoreAt = nil
                    print("\(timestamp()) gate restored")
                    fflush(stdout)
                }
            } catch {
                fputs("mike-gate: observation failed: \(error.localizedDescription)\n", stderr)
            }
        }
    }
}

do {
    let configuration = try Configuration.parse(CommandLine.arguments.dropFirst())
    let deviceInspector = CoreAudioDeviceInspector()

    if configuration.command == .list {
        for device in try deviceInspector.devices().sorted(by: { $0.name < $1.name }) {
            print(
                "id=\(device.objectID) mute=\(device.supportsOutputMute ? "yes" : "no") "
                    + "uid=\(device.uid) name=\(device.name)"
            )
        }
        exit(EXIT_SUCCESS)
    }

    let device = try deviceInspector.device(named: configuration.deviceName)
    let controller = try CoreAudioDeviceMuteController(device: device)

    switch configuration.command {
    case .list:
        break
    case .status:
        print("\(device.name): \(try controller.isMuted() ? "muted" : "unmuted")")
    case .mute:
        try controller.setMuted(true)
        print("\(device.name): muted")
    case .unmute:
        try controller.setMuted(false)
        print("\(device.name): unmuted")
    case .watch:
        try watch(configuration: configuration, controller: controller)
    }
} catch {
    fputs("mike-gate: \(error.localizedDescription)\n", stderr)
    printUsage()
    exit(EXIT_FAILURE)
}
