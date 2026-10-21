import AudioToolbox
import Foundation

/// Short confetti-style chime for a perfect Challenge quiz.
/// Uses AudioToolbox (not AVAudioSession) so playback never blocks the main UI.
enum CelebrationSound {
    private static var soundID: SystemSoundID = 0
    private static var didLoad = false

    static func playPerfectQuiz() {
        // Never touch AVAudioSession here — setActive on the main thread during a
        // SwiftUI state update can freeze the UI on a white screen.
        DispatchQueue.global(qos: .userInitiated).async {
            prepareIfNeeded()
            guard soundID != 0 else { return }
            AudioServicesPlaySystemSound(soundID)
        }
    }

    private static func prepareIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let url = Bundle.main.url(forResource: "perfect_quiz", withExtension: "wav") else {
            return
        }
        var newID: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &newID)
        if status == kAudioServicesNoError {
            soundID = newID
        }
    }
}
