import AppKit
import MenuBentoCore

// menubento-cli list       – every status item Accessibility can see
// menubento-cli movetest   – makes three throwaway items A, B, C and moves
//                            them around with Cmd-drags, printing the order
//                            after each move. Only touches its own items.

let args = CommandLine.arguments.dropFirst()

func order(_ items: [(String, NSStatusItem)]) -> String {
    items.map { ($0.0, $0.1.button?.window?.frame.minX ?? 0) }
        .sorted { $0.1 < $1.1 }
        .map { $0.0 }
        .joined()
}

switch args.first {
case "list":
    print("Accessibility trusted:", AXIsProcessTrusted())
    for item in MenuBarScanner.scan() {
        print(String(format: "%6.0f %4.0f  %@  [%@]%@", item.frame.minX, item.frame.width, item.name, item.ref.id, item.canPress ? "" : " (no press)"))
    }
    print("App menus:", MenuBarScanner.appMenuFrames().map { Int($0.minX) })

case "movetest":
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    func make(_ t: String) -> NSStatusItem {
        let s = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        s.button?.title = t
        return s
    }
    let a = make("A"), b = make("B"), c = make("C")
    let named = [("A", a), ("B", b), ("C", c)]
    func frame(_ s: NSStatusItem) -> CGRect { (s.button?.window?.frame ?? .zero).flippedToTopLeft }
    let plan: [(String, NSStatusItem, () -> Placement)] = [
        ("A left of C", a, { .leftOf(frame(c)) }),
        ("C right of A", c, { .rightOf(frame(a)) }),
        ("B left of A", b, { .leftOf(frame(a)) }),
        ("B right of C", b, { .rightOf(frame(c)) }),
    ]
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        print("start", order(named))
        var i = 0
        func next() {
            guard i < plan.count else { exit(0) }
            let (label, item, placement) = plan[i]
            let from = frame(item), to = placement()
            DispatchQueue.global().async {
                ItemMover.drag(from: from, to: to)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print(label, "→", order(named))
                    i += 1
                    next()
                }
            }
        }
        next()
    }
    app.run()

case "plantest":
    // Checks ArrangePlanner on small orders (no menu bar involved).
    func refs(_ s: String) -> [ItemRef] { s.map { ItemRef(owner: "t", key: String($0)) } }
    func simulate(_ cur: String, _ tgt: String, pinned: String = "") -> (String, Int) {
        var current = refs(cur)
        let target = refs(tgt)
        var settled = ArrangePlanner.stable(current: current, target: target, pinned: Set(refs(pinned)))
        var moves = 0
        for ref in target.reversed() where !settled.contains(ref) {
            guard let anchor = ArrangePlanner.anchor(for: ref, target: target, settled: settled) else { continue }
            current.removeAll { $0 == ref }
            switch anchor {
            case .leftOf(let o): current.insert(ref, at: current.firstIndex(of: o)!)
            case .rightOf(let o): current.insert(ref, at: current.firstIndex(of: o)! + 1)
            }
            precondition(ArrangePlanner.isPlaced(ref, current: current, target: target, settled: settled))
            settled.insert(ref)
            moves += 1
        }
        return (current.map(\.key).joined(), moves)
    }
    let cases: [(String, String, String, Int)] = [
        ("ABCDE", "ABCDE", "", 0),
        ("dAhBAx", "", "", 0),
        ("aHBAgm", "aAHBgm", "", 1),     // the group bug: only A should move
        ("EDCBA", "ABCDE", "", 4),
        ("ABCDK", "BACDK", "K", 1),
        ("XABCK", "ABCXK", "K", 1),
    ]
    var ok = true
    for (cur, tgt, pin, expected) in cases where !tgt.isEmpty {
        let (result, moves) = simulate(cur, tgt, pinned: pin)
        let pass = result == tgt && moves == expected
        ok = ok && pass
        print(pass ? "PASS" : "FAIL", cur, "→", tgt, "got", result, "in", moves, "moves (expected \(expected))")
    }
    exit(ok ? 0 : 1)

case "probe":
    // A throwaway status item that stays for N seconds (default 60).
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = args.dropFirst().first ?? "PROBE"
    // Separate autosave names, or two probes share one saved position.
    item.autosaveName = "probe." + (item.button?.title ?? "")
    let seconds = Double(args.dropFirst(2).first ?? "") ?? 60
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
    app.run()

case "click":
    // click X Y [option|right] – synthesised click (top-left coordinates).
    let a = Array(args.dropFirst())
    guard a.count >= 2, let x = Double(a[0]), let y = Double(a[1]) else { print("click X Y [option|right]"); exit(1) }
    let src = CGEventSource(stateID: .hidSystemState)
    let p = CGPoint(x: x, y: y)
    let saved = CGEvent(source: nil)?.location ?? p
    let right = a.count > 2 && a[2] == "right"
    let option = a.count > 2 && a[2] == "option"
    let flags: CGEventFlags = option ? .maskAlternate : []
    if option {
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x3A, keyDown: true)
        down?.flags = .maskAlternate
        down?.post(tap: .cghidEventTap)
        usleep(30_000)
    }
    defer {
        if option { CGEvent(keyboardEventSource: src, virtualKey: 0x3A, keyDown: false)?.post(tap: .cghidEventTap) }
    }
    for type in right ? [CGEventType.mouseMoved, .rightMouseDown, .rightMouseUp] : [.mouseMoved, .leftMouseDown, .leftMouseUp] {
        let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: right ? .right : .left)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
        usleep(40_000)
    }
    if !(a.count > 3 && a[3] == "stay") {
        usleep(80_000)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: saved, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

case "drag":
    // drag X1 Y1 X2 Y2 – a plain (no modifier) slow mouse drag, for testing
    // drag and drop in MenuBento's Settings window.
    let a = Array(args.dropFirst()).compactMap(Double.init)
    guard a.count == 4 else { print("drag X1 Y1 X2 Y2"); exit(1) }
    let src = CGEventSource(stateID: .hidSystemState)
    let from = CGPoint(x: a[0], y: a[1]), to = CGPoint(x: a[2], y: a[3])
    func post(_ t: CGEventType, _ p: CGPoint) {
        CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    post(.mouseMoved, from); usleep(100_000)
    post(.leftMouseDown, from); usleep(300_000)
    for i in 1...40 {
        let t = CGFloat(i) / 40
        post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
        usleep(25_000)
    }
    usleep(300_000)
    post(.leftMouseUp, to)

default:
    print("usage: menubento-cli list | movetest | probe [title] [seconds] | click X Y [option|right]")
}
