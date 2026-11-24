import AppKit
import ScreenCaptureKit
import MenuBentoCore

/// Pictures of menu bar items for the MenuBento bar.
///
/// macOS 27 draws every status item into one MenuBarAgent window, and
/// hidden items aren't drawn at all, so pictures can only be taken while an
/// item is on screen. We grab the menu bar strip whenever hidden items are
/// revealed and cut it up by each item's frame. Needs Screen Recording.
@MainActor
final class ItemImageCache: ObservableObject {
    static let shared = ItemImageCache()

    @Published private(set) var images: [String: NSImage] = [:]

    func image(for ref: ItemRef) -> NSImage? { images[ref.id] }

    func capture(_ items: [MenuBarItem]) async {
        guard CGPreflightScreenCaptureAccess(), !items.isEmpty else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // Leave our own windows (overlay, MenuBento bar) out of the picture.
            let ours = content.windows.filter { $0.owningApplication?.processID == getpid() }
            for display in content.displays {
                let bounds = CGDisplayBounds(display.displayID)
                // Only items right of the middle are drawn (see ControlItems).
                let onThis = items.filter { bounds.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) && $0.frame.minX > bounds.midX - 20 }
                guard !onThis.isEmpty else { continue }
                let scale = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID }?.backingScaleFactor ?? 2
                let barHeight = onThis.map(\.frame.maxY).max().map { $0 - bounds.minY } ?? 30
                let config = SCStreamConfiguration()
                config.sourceRect = CGRect(x: 0, y: 0, width: bounds.width, height: barHeight)
                config.width = Int(bounds.width * scale)
                config.height = Int(barHeight * scale)
                config.showsCursor = false
                let filter = SCContentFilter(display: display, excludingWindows: ours)
                let strip = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                for item in onThis {
                    let rect = CGRect(x: (item.frame.minX - bounds.minX) * scale, y: (item.frame.minY - bounds.minY) * scale,
                                      width: item.frame.width * scale, height: item.frame.height * scale)
                    guard let cropped = strip.cropping(to: rect.integral) else { continue }
                    images[item.ref.id] = NSImage(cgImage: cropped, size: item.frame.size)
                }
            }
        } catch {
            NSLog("MenuBento: capture failed: \(error.localizedDescription)")
        }
    }

    func clear() { images = [:] }
}
