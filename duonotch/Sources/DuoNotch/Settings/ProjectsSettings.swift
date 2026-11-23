import SwiftUI
import AppKit

/// Settings → Projects: the folders you work in, which login each uses,
/// and the exact command the notch runs for them.
struct ProjectsSettings: View {
    @EnvironmentObject private var state: AppState
    @State private var suggestions: [Project] = []
    @State private var searched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Each project becomes a chip in the notch. Click the chip and a terminal opens in that folder with the right login and starts Claude Code. Sessions started there, or from any folder inside it, are labelled with the project name.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Add folder…") { addFolder() }
                Button(searched ? "Search again" : "Find my git repos") {
                    suggestions = Project.discoverGitRepos().filter { candidate in
                        !state.projects.contains { $0.path == candidate.path }
                    }
                    searched = true
                }
                Spacer()
                Picker("Open in", selection: $state.terminalApp) {
                    ForEach(ProjectLauncher.TerminalApp.allCases) { app in
                        Text(app.name).tag(app)
                    }
                }
                .frame(width: 170)
            }

            if searched {
                if suggestions.isEmpty {
                    Text("No new git repositories found in your home folder (two levels deep).")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    GroupBox("Found in your home folder") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(suggestions) { candidate in
                                    HStack {
                                        Text(candidate.name).font(.callout)
                                        Text(candidate.displayPath)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                        Button("Add") {
                                            state.addProject(candidate)
                                            suggestions.removeAll { $0.path == candidate.path }
                                        }
                                        .controlSize(.small)
                                    }
                                }
                                if suggestions.count > 1 {
                                    Button("Add all \(suggestions.count)") {
                                        suggestions.forEach { state.addProject($0) }
                                        suggestions = []
                                    }
                                    .controlSize(.small)
                                }
                            }
                            .padding(4)
                        }
                        .frame(maxHeight: 140)
                    }
                }
            }

            List {
                ForEach($state.projects) { $project in
                    ProjectRow(project: $project)
                }
            }
            .frame(minHeight: 200)

            if let message = state.launchMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose one or more project folders"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            state.addProject(Project(name: url.lastPathComponent, path: url.standardizedFileURL.path))
        }
    }
}

private struct ProjectRow: View {
    @EnvironmentObject private var state: AppState
    @Binding var project: Project
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Name", text: $project.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                Picker("", selection: $project.accountID) {
                    Text("Default login").tag(String?.none)
                    ForEach(state.accounts) { account in
                        Text(account.label).tag(Optional(account.id))
                    }
                }
                .labelsHidden()
                .frame(width: 200)
                Spacer()
                Button("Open now") { state.launch(project) }
                    .controlSize(.small)
                Button(showDetails ? "Less" : "More") { showDetails.toggle() }
                    .buttonStyle(.link)
            }

            HStack(spacing: 6) {
                Text(project.displayPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Copy path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(project.path, forType: .string)
                }
                .controlSize(.mini)
                Spacer()
            }

            if showDetails {
                let command = ProjectLauncher.commandLine(for: project, account: state.account(for: project))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(command)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Button("Copy command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        }
                        .controlSize(.mini)
                    }
                    TextField("Extra flags for claude, e.g. --model opus", text: $project.extraArgs)
                        .textFieldStyle(.roundedBorder)
                    TextField("Notes: the things you always forget about this project", text: $project.notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                    HStack {
                        Button("Change folder…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.directoryURL = URL(fileURLWithPath: project.path)
                            if panel.runModal() == .OK, let url = panel.url {
                                project.path = url.standardizedFileURL.path
                            }
                        }
                        Button("Remove", role: .destructive) { state.removeProject(project) }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}
