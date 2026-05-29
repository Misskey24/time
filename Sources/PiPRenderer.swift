import UIKit
import AVKit
import AVFoundation
import CoreMedia
import CoreVideo

final class PiPRenderer: NSObject {
    let containerView = UIView()
    var onStatus: ((String) -> Void)?

    private let displayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?
    private var displayLink: CADisplayLink?
    private let renderSize = CGSize(width: 480, height: 240)
    private let frameRate: Int32 = 30
    private var frameIndex: Int64 = 0
    private var startRetryCount = 0

    override init() {
        super.init()
        configureAudioSession()
        configureContainer()
        configurePiPController()
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            onStatus?("Audio session error: \(error.localizedDescription)")
        }
    }

    private func configureContainer() {
        containerView.backgroundColor = .black
        containerView.layer.masksToBounds = true

        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        displayLayer.frame = CGRect(origin: .zero, size: renderSize)
        containerView.layer.addSublayer(displayLayer)
    }

    private func configurePiPController() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            onStatus?("PiP is not supported by this device.")
            return
        }

        if #available(iOS 15.0, *) {
            let source = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: displayLayer,
                playbackDelegate: self
            )
            let controller = AVPictureInPictureController(contentSource: source)
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            controller.requiresLinearPlayback = true
            controller.delegate = self
            pipController = controller
        } else {
            onStatus?("Custom PiP requires iOS 15 or later.")
        }
    }

    func layoutDisplayLayer(in bounds: CGRect) {
        let target = bounds.isEmpty ? CGRect(origin: .zero, size: renderSize) : bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = target
        CATransaction.commit()
    }

    func startTicking() {
        guard displayLink == nil else { return }

        let link = CADisplayLink(target: self, selector: #selector(tick))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: Float(frameRate),
                maximum: Float(frameRate),
                preferred: Float(frameRate)
            )
        } else {
            link.preferredFramesPerSecond = Int(frameRate)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopTicking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func startPiP() {
        guard let pip = pipController else {
            onStatus?("PiP controller is not ready.")
            return
        }

        configureAudioSession()
        startRetryCount = 0
        frameIndex = 0
        displayLayer.flushAndRemoveImage()
        startTicking()

        // Feed several real frames before asking iOS to detach the layer into PiP.
        for _ in 0..<5 {
            tick()
        }

        startPictureInPictureWhenPossible(pip)
    }

    func startTapped() {
        startPiP()
    }

    func stopPiP() {
        pipController?.stopPictureInPicture()
    }

    private func startPictureInPictureWhenPossible(_ pip: AVPictureInPictureController) {
        if pip.isPictureInPicturePossible {
            onStatus?("Starting floating window...")
            pip.startPictureInPicture()
            return
        }

        guard startRetryCount < 20 else {
            onStatus?("PiP is not ready yet. Leave the app open and try again.")
            return
        }

        startRetryCount += 1
        tick()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak pip] in
            guard let self, let pip else { return }
            self.startPictureInPictureWhenPossible(pip)
        }
    }

    @objc private func tick() {
        if displayLayer.status == .failed {
            displayLayer.flush()
        }

        guard displayLayer.isReadyForMoreMediaData,
              let buffer = makeSampleBuffer() else {
            return
        }

        displayLayer.enqueue(buffer)
        frameIndex += 1
    }

    private func makeSampleBuffer() -> CMSampleBuffer? {
        let text = StopwatchEngine.shared.formattedTime()
        let header = StopwatchEngine.shared.source.rawValue
        guard let pixelBuffer = renderPixelBuffer(header: header, text: text) else { return nil }

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }

        let presentationTime = CMTime(value: frameIndex, timescale: frameRate)
        let duration = CMTime(value: 1, timescale: frameRate)
        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) {
            let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                attachment,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        return sampleBuffer
    }

    private func renderPixelBuffer(header: String, text: String) -> CVPixelBuffer? {
        let width = Int(renderSize.width)
        let height = Int(renderSize.height)
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else {
            return nil
        }

        // PiP presents this raw BGRA buffer vertically flipped on some iOS
        // builds. Draw the frame vertically flipped once so the final floating
        // window reads normally.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        UIColor(red: 0.27, green: 0.30, blue: 0.39, alpha: 1.0).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 26).fill()

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 26, weight: .medium),
            .foregroundColor: UIColor(white: 1, alpha: 0.72)
        ]
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 74, weight: .regular),
            .foregroundColor: UIColor.white
        ]
        let lastDigitAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 74, weight: .regular),
            .foregroundColor: UIColor(red: 1.0, green: 0.25, blue: 0.18, alpha: 1)
        ]

        let headerNS = header as NSString
        let headerSize = headerNS.size(withAttributes: headerAttrs)
        headerNS.draw(
            at: CGPoint(x: (renderSize.width - headerSize.width) / 2, y: 24),
            withAttributes: headerAttrs
        )

        let body = String(text.dropLast())
        let lastDigit = String(text.suffix(1))
        let bodyNS = body as NSString
        let lastDigitNS = lastDigit as NSString
        let bodySize = bodyNS.size(withAttributes: timeAttrs)
        let lastDigitSize = lastDigitNS.size(withAttributes: lastDigitAttrs)
        let totalWidth = bodySize.width + lastDigitSize.width
        let startX = (renderSize.width - totalWidth) / 2
        let timeY = (renderSize.height - max(bodySize.height, lastDigitSize.height)) / 2 + 22
        bodyNS.draw(
            at: CGPoint(x: startX, y: timeY),
            withAttributes: timeAttrs
        )
        lastDigitNS.draw(
            at: CGPoint(x: startX + bodySize.width, y: timeY),
            withAttributes: lastDigitAttrs
        )

        return pixelBuffer
    }
}

extension PiPRenderer: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {}

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: CMTime(value: 10000000, timescale: frameRate))
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

extension PiPRenderer: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        startTicking()
        onStatus?("Floating window started.")
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        onStatus?("PiP failed: \(error.localizedDescription)")
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        stopTicking()
    }
}
