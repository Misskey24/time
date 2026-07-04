import AVFoundation
import Foundation

final class BackgroundAudioKeeper {
    static let shared = BackgroundAudioKeeper()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isRunning = false

    private init() {
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func start() {
        guard !isRunning else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: [])

            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410) else { return }
            buffer.frameLength = buffer.frameCapacity

            if !engine.isRunning {
                try engine.start()
            }
            player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
            player.play()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    func stop() {
        guard isRunning else { return }
        player.stop()
        engine.stop()
        isRunning = false
    }
}