import Foundation
import CoreGraphics

final class VirtualDisplayManager {
    private var virtualDisplay: CGVirtualDisplay?
    private(set) var displayID: CGDirectDisplayID = 0
    private(set) var currentWidth: Int = 1920
    private(set) var currentHeight: Int = 1080

    func createDisplay(width: Int, height: Int) {
        currentWidth = width
        currentHeight = height

        guard let descriptor = CGVirtualDisplayDescriptor() else {
            print("[FloatScreen] Failed to create display descriptor")
            return
        }
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = "FloatScreen"
        descriptor.maxPixelsWide = UInt32(width)
        descriptor.maxPixelsHigh = UInt32(height)
        descriptor.sizeInMillimeters = CGSize(
            width: Double(width) * 25.4 / 160.0,
            height: Double(height) * 25.4 / 160.0
        )
        descriptor.productID = 0x1234
        descriptor.vendorID = 0x4321
        descriptor.serialNum = 0x0001

        guard let display = CGVirtualDisplay(descriptor: descriptor) else {
            print("[FloatScreen] Failed to create virtual display")
            return
        }
        self.virtualDisplay = display
        self.displayID = display.displayID

        let settings = CGVirtualDisplaySettings()
        guard let mode = CGVirtualDisplayMode(
            width: UInt(width),
            height: UInt(height),
            refreshRate: 60
        ) else {
            print("[FloatScreen] Failed to create display mode")
            return
        }
        settings.modes = [mode]
        settings.hiDPI = 1
        display.apply(settings)

        print("[FloatScreen] Virtual display created: ID=\(displayID), \(width)x\(height)")
    }

    func changeResolution(width: Int, height: Int) {
        destroyDisplay()
        createDisplay(width: width, height: height)
    }

    func destroyDisplay() {
        virtualDisplay = nil
        displayID = 0
    }
}
