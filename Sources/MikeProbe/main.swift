import Foundation
import MikeCore

private struct Configuration {
    static let voiceInkBundleID = "com.prakashjoshipax.VoiceInk"

    var bundleID = voiceInkBundleID
    var interval: TimeInterval = 0.1
    var listOnly = false

    static func parse(_ arguments: ArraySlice<String>) throws -> Configuration {
        var configuration = Configuration()
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]
            switch argument {
            case "--bundle-id":
                index = arguments.index(after: index)
                guard index < arguments.endIndex else {
                    throw ArgumentError.missingValue(argument)
                }
                configuration.bundleID = arguments[index]
            case "--interval-ms":
                index = arguments.index(after: index)
                guard index < arguments.endIndex,
                    let milliseconds = Double(arguments[index]),
                    milliseconds >= 10
                else {
                    throw ArgumentError.invalidInterval
                }
                configuration.interval = milliseconds / 1_000
            case "--list":
                configuration.listOnly = true
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
}

private enum ArgumentError: Error, LocalizedError {
    case invalidInterval
    case missingValue(String)
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case .invalidInterval:
            return "--interval-ms must be a number of at least 10."
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
        Usage: mike-probe [options]

          --bundle-id ID       Bundle ID to monitor
                               (default: \(Configuration.voiceInkBundleID))
          --interval-ms MS     Polling interval of at least 10 ms (default: 100)
          --list               Print current CoreAudio process objects and exit
          -h, --help           Show this help
        """
    )
}

private func timestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func describe(_ change: CaptureStateChange) -> String {
    switch change {
    case .initial(let isCapturing):
        return isCapturing ? "initial: capturing" : "initial: idle"
    case .started:
        return "started capturing"
    case .stopped:
        return "stopped capturing"
    }
}

do {
    let configuration = try Configuration.parse(CommandLine.arguments.dropFirst())
    let inspector = CoreAudioProcessInspector()

    if configuration.listOnly {
        for process in try inspector.processes().sorted(by: {
            ($0.bundleID ?? "") < ($1.bundleID ?? "")
        }) {
            print(
                "object=\(process.objectID) pid=\(process.processID) "
                    + "input=\(process.isRunningInput ? "active" : "idle") " + "bundle=\(process.bundleID ?? "<none>")"
            )
        }
        exit(EXIT_SUCCESS)
    }

    print(
        "Monitoring \(configuration.bundleID) every "
            + "\(Int(configuration.interval * 1_000)) ms. Press Control-C to stop."
    )

    var tracker = CaptureStateTracker()
    while true {
        let isCapturing = try inspector.isCapturing(bundleID: configuration.bundleID)
        if let change = tracker.observe(isCapturing: isCapturing) {
            print("\(timestamp()) \(describe(change))")
            fflush(stdout)
        }
        Thread.sleep(forTimeInterval: configuration.interval)
    }
} catch {
    fputs("mike-probe: \(error.localizedDescription)\n", stderr)
    printUsage()
    exit(EXIT_FAILURE)
}
