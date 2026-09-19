import Testing
@testable import MikeCore

struct CaptureStateTrackerTests {
    @Test
    func emitsInitialState() {
        var tracker = CaptureStateTracker()

        #expect(tracker.observe(isCapturing: false) == .initial(isCapturing: false))
    }

    @Test
    func deduplicatesRepeatedSamples() {
        var tracker = CaptureStateTracker()

        _ = tracker.observe(isCapturing: false)

        #expect(tracker.observe(isCapturing: false) == nil)
        #expect(tracker.observe(isCapturing: false) == nil)
    }

    @Test
    func emitsStartAndStopTransitions() {
        var tracker = CaptureStateTracker()

        _ = tracker.observe(isCapturing: false)

        #expect(tracker.observe(isCapturing: true) == .started)
        #expect(tracker.observe(isCapturing: true) == nil)
        #expect(tracker.observe(isCapturing: false) == .stopped)
    }
}
