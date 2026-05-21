import AudioToolbox
import Foundation

protocol MessageSoundPlaying: AnyObject {
    func playIncomingMessageSound()
}

final class AudioToolboxMessageSoundPlayer: MessageSoundPlaying {
    private var soundID: SystemSoundID = 0

    init(resourceName: String = "message-received", resourceExtension: String = "wav") {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) else {
            Log.warning(.app, "message sound resource missing: \(resourceName).\(resourceExtension)")
            return
        }

        let status = AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
        if status != kAudioServicesNoError {
            soundID = 0
            Log.warning(.app, "message sound create failed status=\(status)")
        }
    }

    deinit {
        if soundID != 0 {
            AudioServicesDisposeSystemSoundID(soundID)
        }
    }

    func playIncomingMessageSound() {
        guard soundID != 0 else { return }
        AudioServicesPlaySystemSound(soundID)
    }
}
