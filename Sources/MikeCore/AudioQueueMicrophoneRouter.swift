import AudioToolbox
import CoreAudio
import Foundation

public enum AudioQueueRouterError: Error, LocalizedError, Equatable {
    case audioQueue(operation: String, status: OSStatus)
    case alreadyRunning
    case deviceSelection(expected: String, actual: String?)

    public var errorDescription: String? {
        switch self {
        case .audioQueue(let operation, let status):
            return "\(operation) failed with CoreAudio status \(status)."
        case .alreadyRunning:
            return "The microphone router is already running."
        case .deviceSelection(let expected, let actual):
            return "AudioQueue selected \(actual ?? "<none>") instead of \(expected)."
        }
    }
}

public struct AudioRouteMetrics: Equatable, Sendable {
    public let availableFrames: Int
    public let droppedInputFrames: UInt64
    public let inputFrames: UInt64
    public let outputFrames: UInt64
    public let silentOutputFrames: UInt64
}

/// Relays one physical microphone into a stereo virtual output device.
///
/// The relay uses mono, 48 kHz, 32-bit floating-point samples internally and
/// duplicates each input frame into the left and right output channels.
public final class AudioQueueMicrophoneRouter: @unchecked Sendable {
    public let inputDevice: AudioDeviceInfo
    public let outputDevice: AudioDeviceInfo

    private static let sampleRate = 48_000.0
    private static let framesPerBuffer = 480
    private static let bufferCount = 4

    private let ringBuffer = MonoRingBuffer(capacity: Int(sampleRate))
    private var inputQueue: AudioQueueRef?
    private var outputIOProcID: AudioDeviceIOProcID?
    private var outputIsRunning = false

    public private(set) var isRunning = false

    public init(inputDevice: AudioDeviceInfo, outputDevice: AudioDeviceInfo) {
        self.inputDevice = inputDevice
        self.outputDevice = outputDevice
    }

    public var metrics: AudioRouteMetrics {
        let metrics = ringBuffer.metrics()
        return AudioRouteMetrics(
            availableFrames: metrics.availableFrames,
            droppedInputFrames: metrics.droppedInputFrames,
            inputFrames: metrics.inputFrames,
            outputFrames: metrics.outputFrames,
            silentOutputFrames: metrics.silentOutputFrames
        )
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard !isRunning else {
            throw AudioQueueRouterError.alreadyRunning
        }

        do {
            try validateOutputDeviceFormat()
            try createInputQueue()
            try createOutputIOProc()
            try startAudio()
            isRunning = true
        } catch {
            disposeAudio()
            throw error
        }
    }

    private func validateOutputDeviceFormat() throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var byteCount = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(
            outputDevice.objectID,
            &address,
            0,
            nil,
            &byteCount,
            &format
        )
        guard status == noErr else {
            throw CoreAudioError.propertyData(
                selector: address.mSelector,
                status: status
            )
        }

        let requiredFlags =
            kAudioFormatFlagIsFloat
            | kAudioFormatFlagIsPacked
        let isSupported =
            format.mSampleRate == Self.sampleRate
            && format.mFormatID == kAudioFormatLinearPCM
            && format.mFormatFlags & requiredFlags == requiredFlags
            && format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
            && format.mBytesPerFrame == 8
            && format.mChannelsPerFrame == 2
            && format.mBitsPerChannel == 32

        guard isSupported else {
            throw CoreAudioError.unsupportedDeviceFormat(
                device: outputDevice.name,
                details:
                    "\(format.mSampleRate.formatted()) Hz, "
                    + "\(format.mChannelsPerFrame) channels, "
                    + "\(format.mBitsPerChannel)-bit, flags 0x"
                    + String(format.mFormatFlags, radix: 16)
            )
        }
    }

    public func stop() {
        guard inputQueue != nil || outputIOProcID != nil else {
            return
        }

        if outputIsRunning, let outputIOProcID {
            AudioDeviceStop(outputDevice.objectID, outputIOProcID)
            outputIsRunning = false
        }
        if let inputQueue {
            AudioQueueStop(inputQueue, true)
        }
        disposeAudio()
        ringBuffer.clear()
        isRunning = false
    }

    private func createInputQueue() throws {
        var format = Self.linearPCMFormat(channelCount: 1)
        var queue: AudioQueueRef?
        try check(
            AudioQueueNewInput(
                &format,
                Self.inputCallback,
                Unmanaged.passUnretained(self).toOpaque(),
                nil,
                nil,
                0,
                &queue
            ),
            operation: "Creating the input audio queue"
        )
        guard let queue else {
            throw AudioQueueRouterError.audioQueue(
                operation: "Creating the input audio queue",
                status: kAudio_ParamError
            )
        }
        inputQueue = queue

        try select(device: inputDevice, for: queue)

        let bufferByteCount = UInt32(
            Self.framesPerBuffer * Int(format.mBytesPerFrame)
        )
        for _ in 0..<Self.bufferCount {
            var buffer: AudioQueueBufferRef?
            try check(
                AudioQueueAllocateBuffer(queue, bufferByteCount, &buffer),
                operation: "Allocating an input audio buffer"
            )
            guard let buffer else {
                throw AudioQueueRouterError.audioQueue(
                    operation: "Allocating an input audio buffer",
                    status: kAudio_ParamError
                )
            }
            try check(
                AudioQueueEnqueueBuffer(queue, buffer, 0, nil),
                operation: "Enqueuing an input audio buffer"
            )
        }
    }

    private func createOutputIOProc() throws {
        var ioProcID: AudioDeviceIOProcID?
        try check(
            AudioDeviceCreateIOProcID(
                outputDevice.objectID,
                Self.outputIOProc,
                Unmanaged.passUnretained(self).toOpaque(),
                &ioProcID
            ),
            operation: "Creating the output device IO procedure"
        )
        guard let ioProcID else {
            throw AudioQueueRouterError.audioQueue(
                operation: "Creating the output device IO procedure",
                status: kAudio_ParamError
            )
        }
        outputIOProcID = ioProcID
    }

    private func startAudio() throws {
        guard let inputQueue, let outputIOProcID else {
            throw AudioQueueRouterError.audioQueue(
                operation: "Starting audio",
                status: kAudio_ParamError
            )
        }

        try check(
            AudioQueueStart(inputQueue, nil),
            operation: "Starting the input audio queue"
        )
        try check(
            AudioDeviceStart(outputDevice.objectID, outputIOProcID),
            operation: "Starting the output device"
        )
        outputIsRunning = true
    }

    private func disposeAudio() {
        if let inputQueue {
            AudioQueueDispose(inputQueue, true)
            self.inputQueue = nil
        }
        if let outputIOProcID {
            AudioDeviceDestroyIOProcID(outputDevice.objectID, outputIOProcID)
            self.outputIOProcID = nil
        }
    }

    private func select(
        device: AudioDeviceInfo,
        for queue: AudioQueueRef
    ) throws {
        let uid = device.uid as CFString
        var unmanagedUID: Unmanaged<CFString>? = .passUnretained(uid)
        let status = withExtendedLifetime(uid) {
            AudioQueueSetProperty(
                queue,
                kAudioQueueProperty_CurrentDevice,
                &unmanagedUID,
                UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            )
        }
        try check(status, operation: "Selecting \(device.name)")

        let selectedUID = try currentDeviceUID(for: queue)
        guard selectedUID == device.uid else {
            throw AudioQueueRouterError.deviceSelection(
                expected: device.uid,
                actual: selectedUID
            )
        }
    }

    private func currentDeviceUID(for queue: AudioQueueRef) throws -> String? {
        var value: Unmanaged<CFString>?
        var byteCount = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(
            AudioQueueGetProperty(
                queue,
                kAudioQueueProperty_CurrentDevice,
                &value,
                &byteCount
            ),
            operation: "Reading the selected audio device"
        )
        return value?.takeUnretainedValue() as String?
    }

    private func receiveInput(
        queue: AudioQueueRef,
        buffer: AudioQueueBufferRef
    ) {
        let sampleCount =
            Int(buffer.pointee.mAudioDataByteSize)
            / MemoryLayout<Float32>.size
        if sampleCount > 0 {
            let samples = buffer.pointee.mAudioData.assumingMemoryBound(
                to: Float32.self
            )
            ringBuffer.write(samples, count: sampleCount)
        }

        AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
    }

    private func provideOutput(_ outputData: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(outputData)
        guard buffers.count == 1,
            buffers[0].mNumberChannels == 2,
            let data = buffers[0].mData
        else {
            for index in buffers.indices {
                if let data = buffers[index].mData {
                    memset(data, 0, Int(buffers[index].mDataByteSize))
                }
            }
            return
        }

        let frameCapacity =
            Int(buffers[0].mDataByteSize)
            / (MemoryLayout<Float32>.size * 2)
        ringBuffer.readDuplicatingMonoToStereo(
            into: data.assumingMemoryBound(to: Float32.self),
            frameCount: frameCapacity
        )
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw AudioQueueRouterError.audioQueue(
                operation: operation,
                status: status
            )
        }
    }

    private static func linearPCMFormat(
        channelCount: UInt32
    ) -> AudioStreamBasicDescription {
        let bytesPerFrame = UInt32(MemoryLayout<Float32>.size) * channelCount
        return AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: channelCount,
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }

    private static let inputCallback: AudioQueueInputCallback = {
        userData,
        queue,
        buffer,
        _,
        _,
        _
        in
        guard let userData else {
            return
        }
        let router = Unmanaged<AudioQueueMicrophoneRouter>
            .fromOpaque(userData)
            .takeUnretainedValue()
        router.receiveInput(queue: queue, buffer: buffer)
    }

    private static let outputIOProc: AudioDeviceIOProc = {
        _,
        _,
        _,
        _,
        outputData,
        _,
        userData in
        guard let userData else {
            return noErr
        }
        let router = Unmanaged<AudioQueueMicrophoneRouter>
            .fromOpaque(userData)
            .takeUnretainedValue()
        router.provideOutput(outputData)
        return noErr
    }
}
