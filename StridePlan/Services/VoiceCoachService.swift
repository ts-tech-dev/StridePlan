import AVFoundation
import Foundation

protocol VoiceCoaching: AnyObject {
    func speak(_ text: String)
    func stop()
}

/// Speaks cues over music by ducking other audio, then restores it when the queue empties.
/// `speak`/`stop` are called from the main actor and delegate callbacks are forwarded to the main queue,
/// so mutable state is only touched on the main thread.
final class VoiceCoachService: NSObject, VoiceCoaching, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()
    private var pending = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        activateSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.prefersAssistiveTechnologySettings = true
        pending += 1
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        pending = 0
        deactivateSession()
    }

    private func activateSession() {
        do {
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            print("[VoiceCoach] audio session error: \(error)")
        }
    }

    private func deactivateSession() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.finishOne() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.finishOne() }
    }

    private func finishOne() {
        pending = max(0, pending - 1)
        if pending == 0 { deactivateSession() }
    }
}

final class MockVoiceCoach: VoiceCoaching {
    private(set) var spoken: [String] = []
    func speak(_ text: String) { spoken.append(text) }
    func stop() {}
}
