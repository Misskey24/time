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
    private let renderSize = CGSize(width: 730, height: 388)
    private var frameRate: Int32 {
        Int32(PerformanceMetricsMonitor.maximumSupportedFrameRate)
    }
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

        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        if #available(iOS 15.0, *) {
            let maxFPS = Float(PerformanceMetricsMonitor.maximumSupportedFrameRate)
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 10,
                maximum: maxFPS,
                preferred: maxFPS
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
            enqueueFrame()
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
        enqueueFrame()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak pip] in
            guard let self, let pip else { return }
            self.startPictureInPictureWhenPossible(pip)
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        PerformanceMetricsMonitor.shared.recordDisplayRefresh(
            timestamp: link.timestamp,
            targetTimestamp: link.targetTimestamp
        )
        enqueueFrame()
    }

    private func enqueueFrame() {
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
        let text = Self.pipTimeText(from: StopwatchEngine.shared.formattedTime())
        let source = Self.pipSourceName(from: StopwatchEngine.shared.source.rawValue)
        let snapshot = PerformanceMetricsMonitor.shared.snapshot
        guard let pixelBuffer = renderPixelBuffer(source: source, text: text, snapshot: snapshot) else { return nil }

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

    private func renderPixelBuffer(source: String, text: String, snapshot: PerformanceMetricsSnapshot) -> CVPixelBuffer? {
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
        UIColor(red: 0.30, green: 0.35, blue: 0.43, alpha: 1.0).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 36).fill()

        let secondaryColor = UIColor(red: 0.82, green: 0.86, blue: 0.92, alpha: 1.0)
        let topAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 42, weight: .regular),
            .foregroundColor: secondaryColor
        ]
        let latencyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 42, weight: .regular),
            .foregroundColor: Self.latencyColor(for: snapshot.latencyLevel)
        ]
        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 110, weight: .regular),
            .foregroundColor: UIColor.white
        ]
        let lastDigitAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 110, weight: .regular),
            .foregroundColor: UIColor(red: 1.0, green: 0.25, blue: 0.18, alpha: 1)
        ]
        let refreshAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 46, weight: .regular),
            .foregroundColor: secondaryColor
        ]
        let uploadSpeedAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 34, weight: .regular),
            .foregroundColor: Self.speedColor(for: snapshot.uploadBytesPerSecond, inactiveColor: secondaryColor)
        ]
        let downloadSpeedAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 34, weight: .regular),
            .foregroundColor: Self.speedColor(for: snapshot.downloadBytesPerSecond, inactiveColor: secondaryColor)
        ]

        let horizontalPadding: CGFloat = 38
        let latencyNS = snapshot.latencyText.replacingOccurrences(of: " ", with: "") as NSString
        latencyNS.draw(at: CGPoint(x: horizontalPadding, y: 30), withAttributes: latencyAttrs)

        let sourceNS = source as NSString
        let sourceSize = sourceNS.size(withAttributes: topAttrs)
        sourceNS.draw(
            at: CGPoint(x: renderSize.width - horizontalPadding - sourceSize.width, y: 30),
            withAttributes: topAttrs
        )

        let body = String(text.dropLast())
        let lastDigit = String(text.suffix(1))
        let bodyNS = body as NSString
        let lastDigitNS = lastDigit as NSString
        let bodySize = bodyNS.size(withAttributes: timeAttrs)
        let lastDigitSize = lastDigitNS.size(withAttributes: lastDigitAttrs)
        let totalWidth = bodySize.width + lastDigitSize.width
        let startX = (renderSize.width - totalWidth) / 2
        let timeY: CGFloat = 116
        bodyNS.draw(
            at: CGPoint(x: startX, y: timeY),
            withAttributes: timeAttrs
        )
        lastDigitNS.draw(
            at: CGPoint(x: startX + bodySize.width, y: timeY),
            withAttributes: lastDigitAttrs
        )

        let refreshNS = snapshot.refreshRateText.replacingOccurrences(of: " ", with: "") as NSString
        refreshNS.draw(at: CGPoint(x: horizontalPadding, y: 295), withAttributes: refreshAttrs)

        drawRightAligned("↑ \(Self.formatPiPSpeed(snapshot.uploadBytesPerSecond))", y: 280, rightPadding: horizontalPadding, attributes: uploadSpeedAttrs)
        drawRightAligned("↓ \(Self.formatPiPSpeed(snapshot.downloadBytesPerSecond))", y: 329, rightPadding: horizontalPadding, attributes: downloadSpeedAttrs)

        return pixelBuffer
    }

    private func drawRightAligned(_ text: String, y: CGFloat, rightPadding: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let nsText = text as NSString
        let size = nsText.size(withAttributes: attributes)
        nsText.draw(
            at: CGPoint(x: renderSize.width - rightPadding - size.width, y: y),
            withAttributes: attributes
        )
    }

    private static func pipTimeText(from text: String) -> String {
        guard let lastColon = text.lastIndex(of: ":") else { return text }
        let next = text.index(after: lastColon)
        return String(text[..<lastColon]) + "." + String(text[next...])
    }

    private static func pipSourceName(from source: String) -> String {
        source.replacingOccurrences(of: "QQ音乐", with: "QQ 音乐")
    }

    private static func formatPiPSpeed(_ bytesPerSecond: Double) -> String {
        let bytes = max(0, bytesPerSecond)
        if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB/s", bytes / 1024 / 1024)
        }
        return String(format: "%.0f KB/s", bytes / 1024)
    }

    private static func latencyColor(for level: PerformanceMetricsSnapshot.LatencyLevel) -> UIColor {
        switch level {
        case .unknown, .good:
            return UIColor(red: 0.82, green: 0.86, blue: 0.92, alpha: 1.0)
        case .warning:
            return UIColor(red: 1.0, green: 0.82, blue: 0.25, alpha: 1.0)
        case .bad:
            return UIColor(red: 1.0, green: 0.25, blue: 0.18, alpha: 1.0)
        }
    }

    private static func speedColor(for bytesPerSecond: Double, inactiveColor: UIColor) -> UIColor {
        bytesPerSecond >= 1024 ? UIColor.white : inactiveColor
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
