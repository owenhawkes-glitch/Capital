import AppKit
import ApplicationServices

/// A stable name for one menu bar item, so layouts, groups and presets can
/// find it again after a relaunch.
public struct ItemRef: Codable, Hashable, Identifiable, Sendable {
    /// Bundle identifier of the owning app (or its process name).
    public var owner: String
    /// The item's own identifier, title or description, or "#n" (its index
    /// among the app's items, left to right) when it has none.
    public var key: String

    public init(owner: String, key: String) {
        self.owner = owner
        self.key = key
    }

    public var id: String { owner + "|" + key }
}

/// One item currently in the menu bar.
public struct MenuBarItem: Identifiable, Sendable {
    public var ref: ItemRef
    public var pid: pid_t
    /// Global frame, top-left origin (the same space CGEvents use).
    public var frame: CGRect
    /// Human-readable name.
    public var name: String
    public var appName: String
    /// The system won't let these be moved (the clock).
    public var isFixed: Bool
    /// True for MenuBento's own items (separators, spacers, dividers).
    public var isOurs: Bool
    public var canPress: Bool

    public init(ref: ItemRef, pid: pid_t, frame: CGRect, name: String, appName: String,
                isFixed: Bool, isOurs: Bool, canPress: Bool) {
        self.ref = ref; self.pid = pid; self.frame = frame; self.name = name
        self.appName = appName; self.isFixed = isFixed; self.isOurs = isOurs; self.canPress = canPress
    }

    public var id: String { ref.id }
    public var midX: CGFloat { frame.midX }
}

/// Reads every app's status items through the Accessibility API.
///
/// On macOS 26+ status items are no longer separate windows (the whole bar
/// is one MenuBarAgent window), so the window list can't see them; each
/// app's `AXExtrasMenuBar` still lists them with their frames.
public enum MenuBarScanner {
    /// Scans all running apps. Pass our own pid so our items are skipped
    /// (the app knows their frames directly; asking AX about ourselves from
    /// the main thread would deadlock).
    public static func scan(skipping skipPID: pid_t? = nil) -> [MenuBarItem] {
        guard AXIsProcessTrusted() else { return [] }
        var items: [MenuBarItem] = []
        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            if pid == skipPID { continue }
            let owner = app.bundleIdentifier ?? app.localizedName ?? "pid\(pid)"
            let appName = app.localizedName ?? owner
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, 0.25)
            guard let bar: AXUIElement = attribute(axApp, "AXExtrasMenuBar") else { continue }
            let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute) ?? []
            // Sort left to right so "#n" keys are stable while nothing moves.
            let framed = children.compactMap { el -> (AXUIElement, CGRect)? in
                guard let f = frame(of: el) else { return nil }
                return (el, f)
            }.sorted { $0.1.minX < $1.1.minX }
            for (index, (el, f)) in framed.enumerated() {
                let identifier: String? = attribute(el, "AXIdentifier")
                let title: String? = attribute(el, kAXTitleAttribute)
                let desc: String? = attribute(el, kAXDescriptionAttribute)
                let help: String? = attribute(el, kAXHelpAttribute)
                let label = [identifier, title, desc, help].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }
                let key = label.map { String(firstLine($0).prefix(80)) } ?? "#\(index)"
                var actions: CFArray?
                AXUIElementCopyActionNames(el, &actions)
                let canPress = ((actions as? [String]) ?? []).contains(kAXPressAction)
                let isSystem = owner == "com.apple.MenuBarAgent"
                // The clock is the right-most, widest MenuBarAgent item.
                let isClock = isSystem && index == framed.count - 1 && f.width > 60
                let name: String
                if let label, label != appName, !label.hasPrefix(appName) {
                    name = "\(appName) – \(firstLine(label))"
                } else if let label {
                    name = firstLine(label)
                } else if isSystem {
                    name = isClock ? "Clock" : "System item \(index + 1)"
                } else {
                    name = framed.count > 1 ? "\(appName) \(index + 1)" : appName
                }
                items.append(MenuBarItem(ref: ItemRef(owner: owner, key: isClock ? "clock" : key), pid: pid, frame: f,
                                         name: name, appName: appName, isFixed: isClock,
                                         isOurs: false, canPress: canPress))
            }
        }
        return items.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// Presses an item (opens its menu) without moving the pointer.
    @discardableResult
    public static func press(_ item: MenuBarItem) -> Bool {
        guard let el = element(for: item) else { return false }
        return AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
    }

    /// Finds the live AX element for an item again (frames change).
    public static func element(for item: MenuBarItem) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        guard let bar: AXUIElement = attribute(axApp, "AXExtrasMenuBar") else { return nil }
        let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute) ?? []
        return children.min { a, b in
            abs((frame(of: a)?.midX ?? .infinity) - item.midX) < abs((frame(of: b)?.midX ?? .infinity) - item.midX)
        }
    }

    /// The frames of the frontmost app's menus (Apple menu, File, Edit…),
    /// used to draw the left island.
    public static func appMenuFrames() -> [CGRect] {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return [] }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        guard let bar: AXUIElement = attribute(axApp, kAXMenuBarAttribute) else { return [] }
        let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute) ?? []
        return children.compactMap { frame(of: $0) }.filter { $0.width > 0 && $0.minY < 5 }
    }

    // MARK: - AX helpers

    static func attribute<T>(_ el: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success, let value else { return nil }
        return value as? T
    }

    static func frame(of el: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s) == .success,
              let p, let s else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    static func firstLine(_ s: String) -> String {
        String(s.split(whereSeparator: \.isNewline).first ?? Substring(s))
    }
}
