import SwiftUI
import MenuBentoCore

/// Settings → Menu bar items: drag items between Visible, Hidden and Always
/// hidden, or reorder them. Dropping performs the same ⌘-drag in the real
/// menu bar.
struct ItemsSettings: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var reorder = ReorderState.shared
    /// The whole bar, left to right, while a drag is in progress.
    @State private var draft: [ItemRef]?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NeedsAccessibility()
            Text("Drag items between sections, or up and down to change their order (top = left). MenuBento moves them in the menu bar by holding ⌘ and dragging, the way you would; your pointer jumps back afterwards. You can also ⌘-drag items in the menu bar yourself: anything left of the ‹ separator is hidden.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                ForEach(MenuSection.allCases) { section in
                    column(section)
                }
            }
            HStack {
                Button("Refresh") { Task { await model.refresh() } }
                Button("Show everything for a moment") {
                    model.setState(.showAll)
                }
                Spacer()
                Text("\(model.items.filter { !$0.isOurs }.count) items").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .disabled(model.busy != nil)
        .onChange(of: reorder.draggingID) { _, id in
            // A drag that ended outside any target: forget the draft.
            if id == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if draft != nil && model.busy == nil { draft = nil } } }
        }
    }

    // MARK: - Columns

    private var order: [ItemRef] { draft ?? model.order }

    private func refs(in section: MenuSection) -> [ItemRef] {
        let all = order
        let ah = all.firstIndex(of: OurItems.alwaysHidden) ?? -1
        let h = all.firstIndex(of: OurItems.hidden) ?? -1
        return all.enumerated().compactMap { i, ref in
            if ref == OurItems.hidden || ref == OurItems.alwaysHidden { return nil }
            switch section {
            case .alwaysHidden: return i < ah ? ref : nil
            case .hidden: return i > ah && i < h ? ref : nil
            case .visible: return i > h ? ref : nil
            }
        }
    }

    private func column(_ section: MenuSection) -> some View {
        let list = refs(in: section)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(section.name, systemImage: section.symbol).font(.headline)
                Spacer()
                Text("\(list.count)").font(.caption).foregroundStyle(.secondary)
            }
            Text(section.help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(list, id: \.self) { ref in
                        row(ref, section: section)
                    }
                    // Dropping on the empty part of a column puts the item
                    // at that section's end.
                    Color.clear.frame(height: max(40, 60 - CGFloat(list.count) * 4))
                        .contentShape(Rectangle())
                        .reorderTarget(id: "section.\(section.rawValue)", move: { dragged, _ in moveToEnd(dragged, section) }, commit: commit)
                }
                .padding(6)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
            .reorderTarget(id: "column.\(section.rawValue)", move: { _, _ in }, commit: commit)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func row(_ ref: ItemRef, section: MenuSection) -> some View {
        let item = model.items.first { $0.ref == ref }
        let movable = !(item?.isFixed ?? false) && ref != OurItems.main
        HStack(spacing: 8) {
            ItemIcon(item: item)
            VStack(alignment: .leading, spacing: 1) {
                Text(item?.name ?? model.name(for: ref)).lineLimit(1)
                Text(item?.isOurs == true ? "MenuBento" : (item?.appName ?? ref.owner)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if !movable {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary).help("macOS keeps this in place")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(reorder.draggingID == ref.id ? Color.accentColor.opacity(0.25) : Color(nsColor: .controlBackgroundColor)))
        .contentShape(Rectangle())
        .modifier(DragIf(enabled: movable, id: ref.id))
        .reorderTarget(id: ref.id, move: moveInDraft, commit: commit)
        .contextMenu {
            if movable {
                ForEach(MenuSection.allCases.filter { $0 != section }) { other in
                    Button("Move to \(other.name)") { Task { await model.move([ref], to: other) } }
                }
            }
            if !model.groups.isEmpty && item?.isOurs != true {
                Menu("Add to group") {
                    ForEach(model.groups) { group in
                        Button(group.name) {
                            if let i = model.groups.firstIndex(where: { $0.id == group.id }), !model.groups[i].members.contains(ref) {
                                model.groups[i].members.append(ref)
                            }
                        }
                    }
                }
            }
            Button("Copy identifier") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ref.id, forType: .string)
            }
        }
    }

    // MARK: - Drag and drop

    private func moveInDraft(_ dragged: String, _ target: String) {
        var list = draft ?? model.order
        guard let from = list.firstIndex(where: { $0.id == dragged }),
              let to = list.firstIndex(where: { $0.id == target }) else { return }
        let ref = list.remove(at: from)
        list.insert(ref, at: to)
        draft = list
    }

    private func moveToEnd(_ dragged: String, _ section: MenuSection) {
        var list = draft ?? model.order
        guard let from = list.firstIndex(where: { $0.id == dragged }) else { return }
        let ref = list.remove(at: from)
        let index: Int
        switch section {
        case .alwaysHidden: index = list.firstIndex(of: OurItems.alwaysHidden) ?? 0
        case .hidden: index = list.firstIndex(of: OurItems.hidden) ?? 0
        // The right end is pinned by the clock, so join Visible at its left.
        case .visible: index = (list.firstIndex(of: OurItems.hidden) ?? -1) + 1
        }
        list.insert(ref, at: index)
        draft = list
    }

    private func commit() {
        guard let target = draft else { return }
        Task {
            await model.arrange(to: target, label: "Moving…")
            draft = nil
        }
    }
}

private struct DragIf: ViewModifier {
    let enabled: Bool
    let id: String
    func body(content: Content) -> some View {
        if enabled { content.reorderSource(id: id) } else { content }
    }
}

/// The owning app's icon, or a symbol for MenuBento's own items.
struct ItemIcon: View {
    let item: MenuBarItem?

    var body: some View {
        Group {
            if let item, item.isOurs {
                Image(systemName: item.ref == OurItems.main ? "rectangle.split.2x2" : (item.ref.key.hasPrefix("extra") ? "arrow.left.and.right" : "chevron.compact.left"))
                    .frame(width: 20, height: 20)
            } else if let image = item.flatMap({ ItemImageCache.shared.image(for: $0.ref) }) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 26, height: 20)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.black))
            } else if let pid = item?.pid, let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "questionmark.square.dashed").frame(width: 20, height: 20)
            }
        }
        .frame(width: 26)
    }
}
