import Testing
@testable import MikeCore

struct MonoRingBufferTests {
    @Test
    func duplicatesMonoFramesIntoStereo() {
        let ring = MonoRingBuffer(capacity: 4)
        let input: [Float32] = [0.25, -0.5]
        var output = [Float32](repeating: 9, count: 4)

        input.withUnsafeBufferPointer {
            ring.write($0.baseAddress!, count: $0.count)
        }
        let framesRead = output.withUnsafeMutableBufferPointer {
            ring.readDuplicatingMonoToStereo(
                into: $0.baseAddress!,
                frameCount: 2
            )
        }

        #expect(framesRead == 2)
        #expect(output == [0.25, 0.25, -0.5, -0.5])
        #expect(
            ring.metrics()
                == MonoRingBufferMetrics(
                    availableFrames: 0,
                    droppedInputFrames: 0,
                    inputFrames: 2,
                    outputFrames: 2,
                    silentOutputFrames: 0
                )
        )
    }

    @Test
    func suppliesSilenceWhenInputRunsDry() {
        let ring = MonoRingBuffer(capacity: 4)
        let input: [Float32] = [0.75]
        var output = [Float32](repeating: 9, count: 4)

        input.withUnsafeBufferPointer {
            ring.write($0.baseAddress!, count: $0.count)
        }
        let framesRead = output.withUnsafeMutableBufferPointer {
            ring.readDuplicatingMonoToStereo(
                into: $0.baseAddress!,
                frameCount: 2
            )
        }

        #expect(framesRead == 1)
        #expect(output == [0.75, 0.75, 0, 0])
        #expect(ring.metrics().silentOutputFrames == 1)
    }

    @Test
    func dropsNewestFramesWhenInputOverflows() {
        let ring = MonoRingBuffer(capacity: 2)
        let input: [Float32] = [1, 2, 3]
        var output = [Float32](repeating: 0, count: 4)

        input.withUnsafeBufferPointer {
            ring.write($0.baseAddress!, count: $0.count)
        }
        let framesRead = output.withUnsafeMutableBufferPointer {
            ring.readDuplicatingMonoToStereo(
                into: $0.baseAddress!,
                frameCount: 2
            )
        }

        #expect(framesRead == 2)
        #expect(output == [1, 1, 2, 2])
        #expect(ring.metrics().droppedInputFrames == 1)
    }
}
