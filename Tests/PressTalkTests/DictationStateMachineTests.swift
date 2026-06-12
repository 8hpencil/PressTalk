import XCTest
@testable import PressTalk

final class DictationStateMachineTests: XCTestCase {
    func testStartFromIdleBeginsRecording() {
        let machine = DictationStateMachine()
        XCTAssertEqual(machine.requestStart(), .started(generation: 1))
        XCTAssertEqual(machine.state, .recording(generation: 1))
    }

    func testStartWhileRecordingIsIgnored() {
        let machine = DictationStateMachine()
        _ = machine.requestStart()
        XCTAssertEqual(machine.requestStart(), .ignoredAlreadyRecording)
        XCTAssertEqual(machine.state, .recording(generation: 1))
    }

    func testStartWhileTranscribingIsIgnored() {
        let machine = DictationStateMachine()
        _ = machine.requestStart()
        XCTAssertEqual(machine.requestStop(), 1)
        XCTAssertEqual(machine.state, .transcribing(generation: 1))
        XCTAssertEqual(machine.requestStart(), .ignoredTranscriptionInFlight)
        XCTAssertEqual(machine.state, .transcribing(generation: 1))
    }

    func testStrayStopInIdleReturnsNil() {
        let machine = DictationStateMachine()
        XCTAssertNil(machine.requestStop())
        XCTAssertEqual(machine.state, .idle)
    }

    func testCompletionOfCurrentGenerationReturnsToIdle() {
        let machine = DictationStateMachine()
        _ = machine.requestStart()
        let generation = machine.requestStop()!
        XCTAssertTrue(machine.transcriptionCompleted(generation: generation))
        XCTAssertEqual(machine.state, .idle)
    }

    func testLateCallbackFromOlderGenerationIsDiscarded() {
        let machine = DictationStateMachine()
        _ = machine.requestStart()
        let oldGeneration = machine.requestStop()!
        XCTAssertTrue(machine.transcriptionCompleted(generation: oldGeneration))

        // A new recording starts; the old generation's late callback must
        // not touch state (B5).
        _ = machine.requestStart()
        XCTAssertFalse(machine.transcriptionCompleted(generation: oldGeneration))
        XCTAssertEqual(machine.state, .recording(generation: 2))
    }

    func testRecordingFailedRollsBackOnlyMatchingGeneration() {
        let machine = DictationStateMachine()
        guard case .started(let generation) = machine.requestStart() else {
            return XCTFail("expected start")
        }
        machine.recordingFailed(generation: generation - 1)
        XCTAssertEqual(machine.state, .recording(generation: generation))
        machine.recordingFailed(generation: generation)
        XCTAssertEqual(machine.state, .idle)
    }

    func testGenerationsIncreaseAcrossCycles() {
        let machine = DictationStateMachine()
        for expected in 1...3 {
            XCTAssertEqual(machine.requestStart(), .started(generation: expected))
            XCTAssertEqual(machine.requestStop(), expected)
            XCTAssertTrue(machine.transcriptionCompleted(generation: expected))
        }
    }
}
