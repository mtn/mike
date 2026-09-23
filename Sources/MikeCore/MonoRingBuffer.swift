import Darwin
import Synchronization

struct MonoRingBufferMetrics: Equatable, Sendable {
    let availableFrames: Int
    let droppedInputFrames: UInt64
    let inputFrames: UInt64
    let outputFrames: UInt64
    let silentOutputFrames: UInt64
}

/// A lock-free, single-producer/single-consumer mono-sample ring.
///
/// The input callback exclusively advances `writePosition`; the output
/// callback exclusively advances `readPosition`. Acquire/release ordering
/// publishes samples without blocking either real-time audio callback.
final class MonoRingBuffer: @unchecked Sendable {
    private let capacity: Int
    private let droppedInputFrames = Atomic<UInt64>(0)
    private let inputFrames = Atomic<UInt64>(0)
    private let outputFrames = Atomic<UInt64>(0)
    private let readPosition = Atomic<UInt64>(0)
    private let silentOutputFrames = Atomic<UInt64>(0)
    private let storage: UnsafeMutablePointer<Float32>
    private let writePosition = Atomic<UInt64>(0)

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    /// Clears the ring after both audio devices have stopped.
    func clear() {
        readPosition.store(0, ordering: .relaxed)
        writePosition.store(0, ordering: .relaxed)
        droppedInputFrames.store(0, ordering: .relaxed)
        inputFrames.store(0, ordering: .relaxed)
        outputFrames.store(0, ordering: .relaxed)
        silentOutputFrames.store(0, ordering: .relaxed)
    }

    func write(_ samples: UnsafePointer<Float32>, count sampleCount: Int) {
        guard sampleCount > 0 else {
            return
        }

        let write = writePosition.load(ordering: .relaxed)
        let read = readPosition.load(ordering: .acquiring)
        let available = Int(write - read)
        let writableFrames = min(sampleCount, capacity - available)

        for offset in 0..<writableFrames {
            let index = Int((write + UInt64(offset)) % UInt64(capacity))
            storage[index] = samples[offset]
        }

        inputFrames.wrappingAdd(UInt64(sampleCount), ordering: .relaxed)
        let droppedFrames = sampleCount - writableFrames
        if droppedFrames > 0 {
            droppedInputFrames.wrappingAdd(
                UInt64(droppedFrames),
                ordering: .relaxed
            )
        }
        writePosition.store(
            write + UInt64(writableFrames),
            ordering: .releasing
        )
    }

    @discardableResult
    func readDuplicatingMonoToStereo(
        into output: UnsafeMutablePointer<Float32>,
        frameCount: Int
    ) -> Int {
        guard frameCount > 0 else {
            return 0
        }

        let read = readPosition.load(ordering: .relaxed)
        let write = writePosition.load(ordering: .acquiring)
        let readableFrames = min(frameCount, Int(write - read))

        for frame in 0..<readableFrames {
            let index = Int((read + UInt64(frame)) % UInt64(capacity))
            let sample = storage[index]

            output[frame * 2] = sample
            output[frame * 2 + 1] = sample
        }

        outputFrames.wrappingAdd(UInt64(readableFrames), ordering: .relaxed)
        let silentFrames = frameCount - readableFrames
        if silentFrames > 0 {
            silentOutputFrames.wrappingAdd(
                UInt64(silentFrames),
                ordering: .relaxed
            )
        }
        readPosition.store(
            read + UInt64(readableFrames),
            ordering: .releasing
        )

        if readableFrames < frameCount {
            let firstSilentSample = readableFrames * 2
            let silentSampleCount = (frameCount - readableFrames) * 2
            memset(
                output.advanced(by: firstSilentSample),
                0,
                silentSampleCount * MemoryLayout<Float32>.size
            )
        }

        return readableFrames
    }

    func metrics() -> MonoRingBufferMetrics {
        let read = readPosition.load(ordering: .acquiring)
        let write = writePosition.load(ordering: .acquiring)

        return MonoRingBufferMetrics(
            availableFrames: Int(write - read),
            droppedInputFrames: droppedInputFrames.load(ordering: .relaxed),
            inputFrames: inputFrames.load(ordering: .relaxed),
            outputFrames: outputFrames.load(ordering: .relaxed),
            silentOutputFrames: silentOutputFrames.load(ordering: .relaxed)
        )
    }
}
