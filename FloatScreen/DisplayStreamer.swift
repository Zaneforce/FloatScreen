import Foundation
import ScreenCaptureKit
import CoreMedia

protocol DisplayStreamerDelegate: AnyObject {
    func streamer(_ streamer: DisplayStreamer, didOutputSurface surface: IOSurfaceRef)
}

final class DisplayStreamer: NSObject {
    private var targetDisplayID: CGDirectDisplayID
    private var stream: SCStream?

    weak var delegate: DisplayStreamerDelegate?

    init(displayID: CGDirectDisplayID) {
        self.targetDisplayID = displayID
        super.init()
    }

    func updateDisplayID(_ newID: CGDirectDisplayID) {
        self.targetDisplayID = newID
    }

    func startCapture(width: Int, height: Int) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false
            )

            guard let scDisplay = content.displays.first(where: {
                $0.displayID == targetDisplayID
            }) else {
                print("[FloatScreen] Virtual display \(targetDisplayID) not found in shareable content")
                return
            }

            let filter = SCContentFilter(display: scDisplay, excludingWindows: [])

            let config = SCStreamConfiguration()
            config.width = width
            config.height = height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.queueDepth = 3
            config.showsCursor = true

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: DispatchQueue(
                    label: "com.floatscreen.stream",
                    qos: .userInteractive
                )
            )

            try await stream.startCapture()
            self.stream = stream
            print("[FloatScreen] Stream started for display \(targetDisplayID)")
        } catch {
            print("[FloatScreen] Failed to start capture: \(error)")
        }
    }

    func stopCapture() async {
        do {
            try await stream?.stopCapture()
        } catch {
            print("[FloatScreen] Error stopping capture: \(error)")
        }
        stream = nil
    }
}

extension DisplayStreamer: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer) else { return }

        let ioSurface = surfaceRef.takeUnretainedValue()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.streamer(self, didOutputSurface: ioSurface)
        }
    }
}

extension DisplayStreamer: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        print("[FloatScreen] Stream stopped with error: \(error)")
    }
}
