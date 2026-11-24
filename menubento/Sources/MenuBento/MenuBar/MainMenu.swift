import AppKit

/// The menu behind a right-click (or ⌃-click) on the MenuBento icon.
@MainActor
enum MainMenu {
    static func build(model: AppModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(action(model.state == .hidden ? "Show hidden items" : "Hide items", symbol: "eye") {
            model.toggle()
        })
        menu.addItem(action(model.state == .showAll ? "Hide always-hidden items" : "Show everything", symbol: "eye.circle") {
            model.setState(model.state == .showAll ? .hidden : .showAll)
        })
        menu.addItem(action("Open MenuBento bar", symbol: "menubar.dock.rectangle") {
            BentoBar.shared.show()
        })

        if !model.groups.isEmpty {
            menu.addItem(.separator())
            menu.addItem(header("Groups"))
            for group in model.groups {
                let item = action(group.name, symbol: group.symbol) {
                    Task { await model.setGroup(group.id, hidden: !group.isHidden) }
                }
                item.state = group.isHidden ? .off : .on
                item.toolTip = group.isHidden ? "Hidden – click to show" : "Shown – click to hide"
                item.isEnabled = model.busy == nil
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let presets = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        presets.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: nil)
        let sub = NSMenu()
        if model.presets.isEmpty {
            let none = NSMenuItem(title: "No presets yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            sub.addItem(none)
        }
        for preset in model.presets {
            let item = action(preset.name, symbol: nil) { Task { await model.applyPreset(preset.id) } }
            item.isEnabled = model.busy == nil
            sub.addItem(item)
        }
        sub.addItem(.separator())
        sub.addItem(action("Save current layout…", symbol: "plus") { promptForPresetName(model: model) })
        presets.submenu = sub
        menu.addItem(presets)

        menu.addItem(action("Add spacer", symbol: "arrow.left.and.right") { model.addExtra(.spacer) })
        menu.addItem(action("Add divider", symbol: "line.3.horizontal.decrease") { model.addExtra(.divider) })

        menu.addItem(.separator())
        let settings = action("Settings…", symbol: "gearshape") { SettingsWindow.shared.show() }
        settings.keyEquivalent = ","
        menu.addItem(settings)
        let quit = action("Quit MenuBento", symbol: nil) { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)
        return menu
    }

    static func promptForPresetName(model: AppModel) {
        let alert = NSAlert()
        alert.messageText = "Save layout as a preset"
        alert.informativeText = "Saves the order and sections of every menu bar item, plus your spacers and dividers."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Work, Streaming, Minimal…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.suppressionButton?.title = "Include the menu bar look"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.state = .on
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        let includeLook = alert.suppressionButton?.state == .on
        Task { await model.savePreset(named: name.isEmpty ? "Preset \(model.presets.count + 1)" : name, includeLook: includeLook) }
    }

    private static func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: title) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func action(_ title: String, symbol: String?, _ run: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, run: run)
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }
}

/// An NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(title: String, run: @escaping @MainActor () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { MainActor.assumeIsolated { run() } }
}
