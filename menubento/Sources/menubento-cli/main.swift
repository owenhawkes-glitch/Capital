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

default:
    print("usage: menubento-cli list | movetest")
}
