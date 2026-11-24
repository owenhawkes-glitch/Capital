import AppKit
import CoreGraphics

/// Where to drop an item, relative to another item's frame (top-left
/// global coordinates).
public enum Placement: Sendable {
    case leftOf(CGRect)
    case rightOf(CGRect)

    var point: CGPoint {
        switch self {
        case .leftOf(let f): return CGPoint(x: f.minX + 1, y: f.midY)
        case .rightOf(let f): return CGPoint(x: f.maxX - 1, y: f.midY)
        }
    }
}

/// Moves menu bar items the same way a person does: hold Command and drag.
///
/// Posting synthetic mouse events needs Accessibility permission. The
/// pointer is put back where it was afterwards.
public enum ItemMover {
    /// Blocking: call off the main thread. Returns false when events
    /// couldn't be created (usually no Accessibility permission).
    @discardableResult
    public static func drag(from source: CGRect, to placement: Placement, nudge: CGFloat = 0) -> Bool {
        guard AXIsProcessTrusted(), let src = CGEventSource(stateID: .hidSystemState) else { return false }
        let start = CGPoint(x: source.midX, y: source.midY)
        var end = placement.point
        end.x += nudge
        let saved = CGEvent(source: nil)?.location ?? start

        func post(_ type: CGEventType, _ p: CGPoint, flags: CGEventFlags = .maskCommand) {
            guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
        func key(_ down: Bool) {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: down) else { return }
            e.flags = down ? .maskCommand : []
            e.post(tap: .cghidEventTap)
        }

        key(true)
        usleep(20_000)
        post(.mouseMoved, start)
        usleep(30_000)
        post(.leftMouseDown, start)
        usleep(60_000)
        let steps = 12
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y))
            usleep(18_000)
        }
        usleep(60_000)
        post(.leftMouseUp, end)
        usleep(30_000)
        key(false)
        usleep(20_000)
        post(.mouseMoved, saved, flags: [])
        // Give the menu bar time to settle before anyone re-reads frames.
        usleep(150_000)
        return true
    }

    /// The accessibility label (description or title) of whatever is on
    /// screen at a point, in top-left coordinates. Used to make sure a drag
    /// starts on the item we mean to move, never on a neighbour.
    public static func label(at p: CGPoint) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &element) == .success,
              let element else { return nil }
        for attribute in [kAXDescriptionAttribute, kAXTitleAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
               let text = value as? String, !text.isEmpty { return text }
        }
        return nil
    }

    /// Clicks at a point (used for items that don't support AXPress).
    public static func click(at p: CGPoint) {
        guard AXIsProcessTrusted(), let src = CGEventSource(stateID: .hidSystemState) else { return }
        let saved = CGEvent(source: nil)?.location ?? p
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(30_000)
        }
        usleep(50_000)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: saved, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
}

public extension CGRect {
    /// Converts an AppKit (bottom-left origin) screen rect to the top-left
    /// global space used by CGEvent and Accessibility.
    var flippedToTopLeft: CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: minX, y: h - maxY, width: width, height: height)
    }
}
