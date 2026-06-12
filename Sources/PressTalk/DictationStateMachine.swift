import Foundation

/// Explicit dictation lifecycle (KTD5). A monotonically increasing generation
/// number tags every recording; late callbacks from an older generation are
/// discarded so they can never clobber newer state (B5).
///
/// All transitions must happen on the main thread.
public final class DictationStateMachine {
    public enum State: Equatable {
        case idle
        case recording(generation: Int)
        case transcribing(generation: Int)
    }

    public enum StartOutcome: Equatable {
        case started(generation: Int)
        case ignoredAlreadyRecording
        case ignoredTranscriptionInFlight
    }

    public private(set) var state: State = .idle
    private var lastGeneration = 0

    public init() {}

    /// Hotkey pressed. During transcription the press is ignored (default
    /// policy: the caller shows a brief "still recognizing" hint).
    public func requestStart() -> StartOutcome {
        switch state {
        case .idle:
            lastGeneration += 1
            state = .recording(generation: lastGeneration)
            return .started(generation: lastGeneration)
        case .recording:
            return .ignoredAlreadyRecording
        case .transcribing:
            return .ignoredTranscriptionInFlight
        }
    }

    /// Hotkey released (or duration cap auto-stop): recording → transcribing.
    /// Returns the generation to transcribe, or nil for a stray stop.
    public func requestStop() -> Int? {
        guard case .recording(let generation) = state else { return nil }
        state = .transcribing(generation: generation)
        return generation
    }

    /// Recording failed to start: roll back to idle.
    public func recordingFailed(generation: Int) {
        guard case .recording(let current) = state, current == generation else { return }
        state = .idle
    }

    /// Transcription for `generation` finished (success or failure).
    /// Returns false when the callback belongs to an older generation and
    /// must not touch state or UI.
    @discardableResult
    public func transcriptionCompleted(generation: Int) -> Bool {
        guard case .transcribing(let current) = state, current == generation else { return false }
        state = .idle
        return true
    }
}
