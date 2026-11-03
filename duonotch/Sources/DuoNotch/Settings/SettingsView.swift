import SwiftUI
import ServiceManagement
import DuoNotchShared

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            AccountsSettings()
                .tabItem { Label("Accounts", systemImage: "person.2") }
            BehaviourSettings()
                .tabItem { Label("Behaviour", systemImage: "slider.horizontal.3") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 520)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            state.refreshHooksInstalled()
        }
    }
}

// MARK: - Accounts

private struct AccountsSettings: View {
    @EnvironmentObject private var state: AppState
    @State private var installMessage: String?
    @State private var keychainHints: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Each Claude Code login lives in its own config folder. The default one is ~/.claude. Start a second login with:")
                .font(.callout)
            Text("CLAUDE_CONFIG_DIR=~/.claude-work claude")
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))

            List {
                ForEach($state.accounts) { $account in
                    AccountRow(account: $account, installMessage: $installMessage)
                }
            }
            .frame(minHeight: 260)

            if let installMessage {
                Text(installMessage).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button("Rescan home folder") {
                    state.mergeDiscoveredAccounts()
                    state.refreshHooksInstalled()
                }
                Button("Refresh usage now") {
                    Task { await state.refreshAll() }
                }
                Spacer()
                Button("Show keychain items") {
                    keychainHints = CredentialStore.allClaudeKeychainServices()
                }
            }
            if !keychainHints.isEmpty {
                Text("Keychain items named \"Claude Code…\": " + keychainHints.joined(separator: ", "))
                    .font(.caption)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private struct AccountRow: View {
    @EnvironmentObject private var state: AppState
    @Binding var account: Account
    @Binding var installMessage: String?
    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("", isOn: $account.enabled).labelsHidden()
                Circle().fill(account.color).frame(width: 10, height: 10)
                TextField("Label", text: $account.label)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Picker("", selection: $account.colorHex) {
                    ForEach(AccountPalette.presets) { preset in
                        Text(preset.name).tag(preset.hex)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                Spacer()
                Button(showAdvanced ? "Less" : "More") { showAdvanced.toggle() }
                    .buttonStyle(.link)
            }

            HStack(spacing: 8) {
                Text(account.displayPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                hooksControl
            }

            if let error = state.errors[account.id] {
                Text(error).font(.caption).foregroundStyle(.orange)
            } else if let reading = state.readings[account.id] {
                Text(state.summaryLine(for: account) + (reading.subscriptionType.map { " · \(Formatting.planName($0))" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if showAdvanced {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Keychain service override (leave empty for automatic)",
                              text: Binding(
                                get: { account.keychainServiceOverride ?? "" },
                                set: { account.keychainServiceOverride = $0.isEmpty ? nil : $0 }
                              ))
                        .textFieldStyle(.roundedBorder)
                    Text("Tried: " + CredentialStore.keychainServiceCandidates(for: account).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    HStack {
                        Button("Reveal settings.json") {
                            NSWorkspace.shared.activateFileViewerSelecting([HookInstaller.settingsURL(for: account.configDir)])
                        }
                        Button("Remove from DuoNotch", role: .destructive) {
                            state.removeAccount(account)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var hooksControl: some View {
        let installed = state.hooksInstalled[account.id] ?? false
        HStack(spacing: 6) {
            Image(systemName: installed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(installed ? Color.green : Color.secondary)
            Text(installed ? "Hooks installed" : "Hooks not installed")
                .font(.caption)
            Button(installed ? "Reinstall" : "Install hooks") {
                do {
                    try HookInstaller.install(configDir: account.configDir)
                    installMessage = "Hooks written to \(HookInstaller.settingsURL(for: account.configDir).path). Restart any running `claude` so it picks them up."
                } catch {
                    installMessage = "Could not install hooks: \(error.localizedDescription)"
                }
                state.refreshHooksInstalled()
            }
            .controlSize(.small)
            if installed {
                Button("Remove") {
                    do {
                        try HookInstaller.uninstall(configDir: account.configDir)
                        installMessage = "Hooks removed from \(account.displayPath)/settings.json"
                    } catch {
                        installMessage = "Could not remove hooks: \(error.localizedDescription)"
                    }
                    state.refreshHooksInstalled()
                }
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Behaviour

private struct BehaviourSettings: View {
    @EnvironmentObject private var state: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("Readings") {
                Picker("Poll usage every", selection: $state.pollIntervalSeconds) {
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                }
                Text("While a session is running the notch polls every 30 seconds regardless.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Notch") {
                Toggle("Open for 5 seconds when a session finishes or asks something", isOn: $state.peekOnFinish)
                Toggle("Keep the notch open", isOn: $state.pinnedOpen)
                Toggle("Show percentages in the menu bar", isOn: $state.showMenuBarText)
            }

            Section("App") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                        }
                    }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.orange)
                }
                Toggle("Demo mode (fake accounts and sessions)", isOn: $state.demoMode)
            }

            Section("Hook server") {
                LabeledContent("Status", value: state.serverStatus)
                LabeledContent("Hook binary", value: HookInstaller.hookBinaryURL?.path ?? "not found next to the app")
                LabeledContent("Usage endpoint", value: ClaudeUsageClient.endpoint.absoluteString)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DuoNotch").font(.title2.bold())
            Text("Pins two Claude subscriptions to the top of the screen: one ring per login, a hover panel with session and weekly limits, live counts of open, running and finished Claude Code chats, and Allow / Deny buttons for permission prompts.")
            Text("What it reads").font(.headline)
            Text("""
            • The OAuth token Claude Code stored for each login, from the login keychain (or `.credentials.json` in the config folder). It is read only, never written or refreshed.
            • The usage endpoint Claude Code's own `/usage` command uses. It is not a documented API and may change.
            • Hook events from Claude Code (session start, prompt, stop, end, permission requests) over 127.0.0.1 with a per-Mac secret. Only counts, tool names and a one-line summary are kept; prompts and replies are never stored.
            """)
            .font(.callout)
            Spacer()
        }
        .padding()
    }
}
