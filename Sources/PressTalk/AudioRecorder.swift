import Foundation
import AVFoundation

public final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    /// Gemini inline requests are capped at 20 MB: 16 kHz/16-bit/mono ≈ 32 KB/s,
    /// base64 inflates ×4/3 ≈ 2.56 MB/min, so ~7.5 min hits the cap.
    /// 5 minutes leaves comfortable headroom (KTD10).
    public static let maxRecordingDuration: TimeInterval = 300
    /// Warn this many seconds before the hard stop (i.e. at 4:30).
    public static let warningLeadTime: TimeInterval = 30

    /// Fired once per recording when `maxRecordingDuration - warningLeadTime` elapses.
    public var onDurationWarning: (() -> Void)?
    /// Fired when the cap is reached; the recording is still active — the owner
    /// is expected to stop it through the same path as a hotkey release.
    public var onDurationLimitReached: (() -> Void)?

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var warningTimer: Timer?
    private var limitTimer: Timer?

    public var isRecording: Bool {
        return recorder?.isRecording ?? false
    }

    public func startRecording(format: AudioFormatPreference = .standard) -> URL? {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let filename = "presstalk_\(UUID().uuidString).wav"
        let audioURL = tempDirectory.appendingPathComponent(filename)
        self.fileURL = audioURL

        // Format comes from the active provider's preference (E4).
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channels,
            AVLinearPCMBitDepthKey: format.bitDepth,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            let recorder = try AVAudioRecorder(url: audioURL, settings: settings)
            recorder.delegate = self

            let prepared = recorder.prepareToRecord()
            Log.audio.debug("AVAudioRecorder prepareToRecord returned: \(prepared)")

            if recorder.record() {
                self.recorder = recorder
                startDurationTimers()
                return audioURL
            } else {
                Log.audio.error("Failed to start recording (record() returned false)")
                return nil
            }
        } catch {
            Log.audio.error("Failed to initialize AVAudioRecorder: \((error as NSError).code)")
            return nil
        }
    }

    public func stopRecording() -> URL? {
        cancelDurationTimers()
        guard let recorder = recorder, recorder.isRecording else {
            return nil
        }
        recorder.stop()
        let url = fileURL
        self.recorder = nil
        return url
    }

    public func cleanup(url: URL) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
                Log.audio.debug("Cleaned up temp audio file")
            } catch {
                Log.audio.error("Failed to delete temp audio file: \((error as NSError).code)")
            }
        }
    }

    private func startDurationTimers() {
        warningTimer = Timer.scheduledTimer(
            withTimeInterval: Self.maxRecordingDuration - Self.warningLeadTime,
            repeats: false
        ) { [weak self] _ in
            Log.audio.info("Recording approaching duration limit")
            self?.onDurationWarning?()
        }
        limitTimer = Timer.scheduledTimer(
            withTimeInterval: Self.maxRecordingDuration,
            repeats: false
        ) { [weak self] _ in
            Log.audio.info("Recording duration limit reached; auto-stopping")
            self?.onDurationLimitReached?()
        }
    }

    private func cancelDurationTimers() {
        warningTimer?.invalidate()
        warningTimer = nil
        limitTimer?.invalidate()
        limitTimer = nil
    }
}
