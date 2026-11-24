import SwiftUI
import ServiceManagement
import MenuBentoCore

// MARK: - Groups

struct GroupsSettings: View {
    @ObservedObject private var model = AppModel.shared
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A group is a set of items you can hide or show together in one click, from here or from the MenuBento menu (right-click the icon). Hiding a group parks its items in Always hidden; showing it puts each one back in the section it came from.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            NeedsAccessibility()
            HStack {
                TextField("New group name", text: $newName).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                    .onSubmit(addGroup)
                Button("Add group", action: addGroup).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach($model.groups) { $group in
                        GroupCard(group: $group)
                    }
                }
            }
            if model.groups.isEmpty {
                Text("No groups yet. Add one, then add items from the list below each group, or right-click an item on the Menu bar items page.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private func addGroup() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.groups.append(ItemGroup(name: name))
        newName = ""
    }
}

private struct GroupCard: View {
    @ObservedObject private var model = AppModel.shared
    @Binding var group: ItemGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    ForEach(ItemGroup.symbols, id: \.self) { s in
                        Button { group.symbol = s } label: { Label(s, systemImage: s) }
                    }
                } label: { Image(systemName: group.symbol) }
                .menuStyle(.borderlessButton).frame(width: 40)
                TextField("Name", text: $group.name).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Spacer()
                Toggle(group.isHidden ? "Hidden" : "Shown", isOn: Binding(
                    get: { !group.isHidden },
                    set: { show in let id = group.id; Task { await model.setGroup(id, hidden: !show) } }))
                    .toggleStyle(.switch)
                    .disabled(model.busy != nil || group.members.isEmpty)
                Button(role: .destructive) {
                    model.groups.removeAll { $0.id == group.id }
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
            }
            FlowMembers(group: $group)
            Menu("Add item…") {
                ForEach(model.items.filter { !$0.isOurs && !$0.isFixed && !group.members.contains($0.ref) }) { item in
                    Button(item.name) { group.members.append(item.ref) }
                }
            }
            .frame(maxWidth: 200)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
    }
}

private struct FlowMembers: View {
    @ObservedObject private var model = AppModel.shared
    @Binding var group: ItemGroup

    var body: some View {
        if group.members.isEmpty {
            Text("No items yet.").font(.caption).foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(group.members, id: \.self) { ref in
                    let item = model.items.first { $0.ref == ref }
                    HStack(spacing: 6) {
                        ItemIcon(item: item)
                        Text(item?.name ?? model.name(for: ref)).lineLimit(1).font(.callout)
                            .foregroundStyle(item == nil ? .secondary : .primary)
                        Spacer(minLength: 0)
                        Button { group.members.removeAll { $0 == ref } } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                    .help(item == nil ? "Not running right now" : ref.id)
                }
            }
        }
    }
}

// MARK: - Spacers and dividers

struct ExtrasSettings: View {
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spacers add a gap between menu bar items; dividers draw a line or dots. New ones appear at the start of the Visible section; drag them into place on the Menu bar items page, or ⌘-drag them in the menu bar.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { model.addExtra(.spacer) } label: { Label("Add spacer", systemImage: "arrow.left.and.right") }
                Button { model.addExtra(.divider) } label: { Label("Add divider", systemImage: "line.3.horizontal.decrease") }
            }
            List {
                ForEach($model.extras) { $extra in
                    HStack(spacing: 12) {
                        preview(extra).frame(width: 40, height: 24).background(RoundedRectangle(cornerRadius: 5).fill(.black))
                        if extra.kind == .spacer {
                            Text("Spacer").frame(width: 70, alignment: .leading)
                            Slider(value: $extra.width, in: 4...80, step: 2) { Text("Width") }.frame(maxWidth: 220)
                            Text("\(Int(extra.width)) pt").monospacedDigit().frame(width: 44)
                        } else {
                            Text("Divider").frame(width: 70, alignment: .leading)
                            Picker("", selection: $extra.style) {
                                ForEach(ExtraItem.Style.allCases) { Text($0.name).tag($0) }
                            }
                            .labelsHidden().frame(width: 120)
                            Picker("", selection: Binding(get: { extra.colorHex == ExtraItem.glowColor ? "glow" : "custom" },
                                                          set: { extra.colorHex = $0 == "glow" ? ExtraItem.glowColor : "#9A9AA0" })) {
                                Text("Match the glow").tag("glow")
                                Text("Custom colour").tag("custom")
                            }
                            .labelsHidden().frame(width: 150)
                            if extra.colorHex != ExtraItem.glowColor {
                                ColorPicker("", selection: hexColorBinding($extra.colorHex), supportsOpacity: false).labelsHidden()
                            }
                        }
                        Spacer()
                        Button(role: .destructive) { model.extras.removeAll { $0.id == extra.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 240)
            Text("“Match the glow” dividers use the theme's glow colours and move in step with the glowing edge (Appearance). They keep still when Reduce Motion is on.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
    }

    @ViewBuilder
    private func preview(_ extra: ExtraItem) -> some View {
        if extra.kind == .spacer {
            HStack(spacing: 0) {
                Image(systemName: "chevron.compact.right").font(.caption2)
                Color.clear.frame(width: min(CGFloat(extra.width) / 3, 20))
                Image(systemName: "chevron.compact.left").font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.6))
        } else {
            DividerGlyph(extra: extra)
        }
    }
}

// MARK: - Hidden items

struct HiddenSettings: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var loginStatus = SMAppService.mainApp.status

    var body: some View {
        Form {
            Section("Showing hidden items") {
                Picker("Click MenuBento to show hidden items", selection: $model.revealMode) {
                    ForEach(RevealMode.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text(model.revealMode == .inPlace
                     ? "Hidden items slide back into the menu bar, left of the ‹ separator. Needs no extra permission."
                     : "A bar drops down under the menu bar with the hidden items. Click one to open its menu (MenuBento briefly reveals it and clicks it for you, which needs Accessibility).")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show on hover (rest the pointer just left of your visible items, or on the MenuBento icon)", isOn: $model.showOnHover)
                Toggle("Hide again automatically", isOn: $model.autoRehide)
                if model.autoRehide {
                    HStack {
                        Text("After leaving the menu bar for")
                        Slider(value: $model.rehideDelay, in: 1...15, step: 1).frame(maxWidth: 200)
                        Text("\(Int(model.rehideDelay)) s").monospacedDigit()
                    }
                    Text("Waits while any menu is open.").font(.caption).foregroundStyle(.secondary)
                }
                Text("⌥-click MenuBento shows Always hidden items too. Right-click for groups, presets and settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("MenuBento bar") {
                Toggle("Show pictures of the real items (needs Screen Recording)", isOn: $model.barShowsImages)
                if model.barShowsImages && !permissions.screenRecording {
                    HStack {
                        Text("Without Screen Recording the bar shows each app's icon and name instead.").font(.caption).foregroundStyle(.secondary)
                        Button("Grant…") { permissions.requestScreenRecording() }
                    }
                }
                HStack {
                    Button("Open the bar") { BentoBar.shared.show() }
                    Button("Retake pictures") {
                        ItemImageCache.shared.clear()
                        Task {
                            model.setState(.showAll)
                            try? await Task.sleep(for: .milliseconds(450))
                            await model.captureImagesIfAllowed()
                            model.setState(.hidden)
                        }
                    }
                    .disabled(!permissions.screenRecording)
                }
                Text("macOS doesn't draw hidden items at all, so pictures are taken whenever they're revealed (the bar flashes them in for half a second the first time).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("App") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        let service = SMAppService.mainApp
                        do {
                            if enabled, service.status != .enabled { try service.register() }
                            if !enabled, service.status == .enabled || service.status == .requiresApproval { try service.unregister() }
                            launchError = nil
                        } catch { launchError = error.localizedDescription }
                        loginStatus = service.status
                    }
                HStack(spacing: 6) {
                    Image(systemName: loginStatus.symbol).foregroundStyle(loginStatus.tint)
                    Text(loginStatus.text).font(.caption).foregroundStyle(.secondary)
                    if loginStatus == .requiresApproval {
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }.font(.caption)
                    }
                }
                if !Bundle.main.bundlePath.hasPrefix("/Applications/") {
                    Text("MenuBento is running from \(Bundle.main.bundlePath). Install it with `make install` so login uses the copy in Applications.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let launchError { Text(launchError).font(.caption).foregroundStyle(.orange) }
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loginStatus = SMAppService.mainApp.status
            launchAtLogin = loginStatus == .enabled || loginStatus == .requiresApproval
        }
    }
}

private extension SMAppService.Status {
    var text: String {
        switch self {
        case .enabled: "On: MenuBento opens when you log in."
        case .requiresApproval: "Waiting for your approval in System Settings → General → Login Items."
        case .notRegistered: "Off."
        case .notFound: "Off (macOS can't find this copy of MenuBento; install it in Applications)."
        @unknown default: "Unknown."
        }
    }
    var symbol: String {
        switch self {
        case .enabled: "checkmark.circle.fill"
        case .requiresApproval: "exclamationmark.circle"
        default: "circle"
        }
    }
    var tint: Color {
        switch self {
        case .enabled: .green
        case .requiresApproval: .orange
        default: .secondary
        }
    }
}

// MARK: - Presets

struct PresetsSettings: View {
    @ObservedObject private var model = AppModel.shared
    @State private var newName = ""
    @State private var includeLook = true
    @State private var confirmOverwrite: LayoutPreset?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A preset remembers the order and section of every item, your spacers and dividers, and (if you like) the menu bar's look. Apply one here or from the MenuBento menu (right-click the icon → Presets).")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Name for the current layout", text: $newName).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Toggle("Include look", isOn: $includeLook)
                Button("Save current layout") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    Task { await model.savePreset(named: name.isEmpty ? "Preset \(model.presets.count + 1)" : name, includeLook: includeLook) }
                    newName = ""
                }
            }
            List {
                ForEach($model.presets) { $preset in
                    HStack(spacing: 10) {
                        Image(systemName: "square.stack").foregroundStyle(.secondary)
                        TextField("Name", text: $preset.name).textFieldStyle(.plain).frame(maxWidth: 200)
                        Text("\(preset.count(in: .visible)) visible · \(preset.count(in: .hidden)) hidden · \(preset.count(in: .alwaysHidden)) always hidden\(preset.extras.isEmpty ? "" : " · \(preset.extras.count) spacers/dividers")\(preset.appearance == nil ? "" : " · look")")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Apply") { let id = preset.id; Task { await model.applyPreset(id) } }
                            .disabled(model.busy != nil)
                        Button("Overwrite") { confirmOverwrite = preset }
                        Button(role: .destructive) { model.presets.removeAll { $0.id == preset.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                    .help("Saved \(preset.saved.formatted(date: .abbreviated, time: .shortened)) — click the name to rename")
                }
                .onMove { model.presets.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(minHeight: 260)
            if model.presets.isEmpty {
                Text("No presets yet.").font(.callout).foregroundStyle(.secondary)
            }
            Text("Applying a preset needs Accessibility to move items. Items that aren't running are skipped and keep their place in the preset.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .confirmationDialog("Replace “\(confirmOverwrite?.name ?? "")” with the current layout?", isPresented: Binding(
            get: { confirmOverwrite != nil }, set: { if !$0 { confirmOverwrite = nil } })) {
            Button("Overwrite") {
                if let id = confirmOverwrite?.id { Task { await model.overwritePreset(id) } }
                confirmOverwrite = nil
            }
        }
    }
}

// MARK: - Permissions

struct PermissionsSettings: View {
    @ObservedObject private var permissions = Permissions.shared

    var body: some View {
        Form {
            Section {
                row(title: "Accessibility", granted: permissions.accessibility, why: Permissions.accessibilityWhy,
                    needed: "Needed for: listing items, moving them, groups, presets, Cells look, clicking items from the MenuBento bar.",
                    action: permissions.requestAccessibility)
            }
            Section {
                row(title: "Screen Recording", granted: permissions.screenRecording, why: Permissions.screenRecordingWhy,
                    needed: "Optional. Only for pictures in the MenuBento bar.",
                    action: permissions.requestScreenRecording)
            }
            Section("Works without any permission") {
                Text("Hiding and showing items (click, ⌥-click, hover, auto-rehide), ⌘-dragging items yourself, spacers and dividers, and the menu bar look (Tint, Glow only and the island shapes). The MenuBento bar opens without permissions but needs Accessibility to list and click items.")
                    .font(.callout)
            }
            Section {
                Text("Already switched on but MenuBento still asks? The switch belongs to an earlier build: macOS ties each approval to the app's exact signature. Click Grant… here; MenuBento clears its own old entry first, so the next approval sticks.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func row(title: String, granted: Bool, why: String, needed: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(granted ? .green : .orange)
                Text(title).font(.headline)
                Spacer()
                if !granted { Button("Grant…", action: action) } else { Text("Granted").foregroundStyle(.secondary) }
            }
            Text(why).font(.callout).fixedSize(horizontal: false, vertical: true)
            Text(needed).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - About

struct AboutSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "rectangle.split.2x2").font(.largeTitle)
                Text("MenuBento").font(.title.bold())
            }
            Text("A menu bar manager in the style of DuoNotch: sections, groups, spacers and dividers, a drop-down bar for hidden items, and themes for the menu bar itself.")
            Text("How hiding works").font(.headline)
            Text("""
            MenuBento adds two separators to your menu bar. Everything left of ‹ is Hidden; everything left of « is Always hidden. To hide, a separator grows to just under half the screen width, pushing the items to its left past the middle of the bar, where macOS 27 stops drawing status items. (The older trick of a 10 000-point separator is ignored by macOS 27.)
            """).font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("What it never does").font(.headline)
            Text("It doesn't read other apps' windows, typing or data, and it doesn't change other apps' settings. Item names come from the labels apps give to VoiceOver.")
                .font(.callout)
            Spacer()
        }
        .padding(20)
    }
}
