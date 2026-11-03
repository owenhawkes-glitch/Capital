# DuoNotch

A small macOS app that pins **two Claude subscriptions** to the top of the
screen, in the style of [codenotch](https://github.com/vinzdg/codenotch),
written from scratch in Swift / SwiftUI.

Collapsed, it is a black slab either side of the camera housing (or a fake
notch on screens without one) with one usage ring per login. Hover it and it
drops down to show, for each login:

- the rolling **session** limit (the 5-hour window `claude /usage` leads with)
- the **weekly** limit, plus the Opus-only weekly window where the plan has one
- when each window resets
- live counts of Claude Code chats: **running**, **waiting on you**, **idle**
  and **done**
- **Allow / Deny / Terminal** buttons for permission prompts, so you can approve
  a tool call from the notch without finding the right terminal tab

Nothing is written to Claude Code's credentials. Tokens are read, never
refreshed. Prompts and replies are never stored; only counts, tool names and a
one-line summary of the pending tool call.

## Requirements

- macOS 14 Sonoma or later (Apple silicon or Intel)
- Xcode 15+ command line tools (`xcode-select --install`) – the project is a
  plain Swift package, no XcodeGen needed
- One or two Claude Code logins (see below)

## Build and run

```bash
cd duonotch
make run        # debug build → dist/DuoNotch.app, then launches it
```

```bash
make demo       # same, but with fake accounts, sessions and a pending approval
```

```bash
make install    # release build copied to /Applications
```

Open the package in Xcode with `open Package.swift` if you prefer.

The first time it reads a login's token the keychain will ask
"DuoNotch wants to access key *Claude Code-credentials*". Click **Always
Allow**. The debug build is ad-hoc signed so the choice sticks for that
build; rebuilding may ask again.

## Two logins

Claude Code keeps everything about a login in its config directory:
`~/.claude` by default, or whatever `CLAUDE_CONFIG_DIR` points at. So a second
subscription is just a second config directory:

```bash
CLAUDE_CONFIG_DIR=~/.claude-work claude
```

Sign in when it asks. From then on every `claude` started with that variable
is the work login, and plain `claude` is the personal one. Put an alias in
your shell profile if you like:

```bash
alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work claude'
```

DuoNotch scans your home folder for `~/.claude` and `~/.claude-*` and shows
one ring per directory. Settings → Accounts lets you rename, recolour,
disable or remove each one. Labels default to the email in that login's
`.claude.json`.

### Where the token comes from

For each login DuoNotch looks, in order, at:

1. `<config dir>/.credentials.json` (present on some setups)
2. the login keychain item named `Claude Code-credentials` (default
   directory) or `Claude Code-credentials-<hash>` (custom directory)

If a custom directory's keychain item has a different name on your machine,
open Settings → Accounts → **More** on that account, click **Show keychain
items** to see every `Claude Code…` entry, and paste the right name into the
override field.

An expired token is reported as such; run `claude` once for that login and
Claude Code refreshes it. DuoNotch never refreshes tokens itself so it can't
log you out of a terminal.

### The usage endpoint

Readings come from the endpoint Claude Code's own `/usage` command uses
(`https://api.anthropic.com/api/oauth/usage`). It is not a documented public
API. If it moves, set a new URL with:

```bash
defaults write com.hawkes.duonotch usageEndpoint "https://…"
```

Polling is every 5 minutes (configurable), every 30 seconds while a session is
running, with back-off on HTTP 429.

## Sessions and approvals

Chat counts and approvals come from Claude Code **hooks**. DuoNotch ships a
tiny helper, `duonotch-hook`, that Claude Code runs on these events:

| Event              | What the notch does                                 |
| ------------------ | --------------------------------------------------- |
| `SessionStart`     | adds the chat as *idle*                             |
| `UserPromptSubmit` | marks it *running*                                  |
| `Stop`             | marks it *idle* (turn finished), peeks for 5 s      |
| `Notification`     | `permission_prompt` → *waiting*, `idle_prompt` → *idle* |
| `PermissionRequest`| shows Allow / Deny / Terminal in the notch          |
| `SessionEnd`       | marks it *done* (kept for an hour)                  |

The helper reads `CLAUDE_CONFIG_DIR` from its environment, which is how each
event is attributed to the right login. It talks to the app over
`127.0.0.1:47123` with a random per-Mac secret stored in
`~/Library/Application Support/DuoNotch/hook-token`. If the app isn't running
the helper exits silently and Claude Code behaves as if no hook existed.

### Installing the hooks

Settings → Accounts → **Install hooks** on each login. This merges six entries
into that login's `settings.json` (a backup `settings.json.duonotch-backup`
is kept next to it) and leaves any hooks you already had alone. Restart
running `claude` sessions so they pick the hooks up.

If you'd rather edit by hand, this is what gets added, with the path pointing
at the helper inside the app bundle:

```json
{
  "hooks": {
    "SessionStart":      [{ "hooks": [{ "type": "command", "command": "\"/Applications/DuoNotch.app/Contents/MacOS/duonotch-hook\"", "timeout": 10 }] }],
    "UserPromptSubmit":  [{ "hooks": [{ "type": "command", "command": "\"/Applications/DuoNotch.app/Contents/MacOS/duonotch-hook\"", "timeout": 10 }] }],
    "Stop":              [{ "hooks": [{ "type": "command", "command": "\"/Applications/DuoNotch.app/Contents/MacOS/duonotch-hook\"", "timeout": 10 }] }],
    "SessionEnd":        [{ "hooks": [{ "type": "command", "command": "\"/Applications/DuoNotch.app/Contents/MacOS/duonotch-hook\"", "timeout": 10 }] }],
    "Notification":      [{ "hooks": [{ "type": "command", "command": "\"/Applications/DuoNotch.app/Contents/MacOS/duonotch-hook\"", "timeout": 10 }] }],
    "PermissionRequest": [{ "hooks": [{ "type": "command", "command": "\"/Applications/DuoNotch.app/Contents/MacOS/duonotch-hook\"", "timeout": 300 }] }]
  }
}
```

If you move the app, click **Reinstall** so the path is updated.

### How approval works

When Claude Code needs permission for a tool call it runs the
`PermissionRequest` hook and waits up to 300 s for an answer. The helper
forwards the request to the notch, which opens and shows the tool and a
one-line summary (the shell command, the file path, the URL). Then:

- **Allow** – the hook answers `allow`; Claude Code proceeds, no terminal prompt
- **Deny** – the hook answers `deny`; Claude gets "Denied from DuoNotch"
- **Terminal** – the hook answers nothing; Claude Code shows its usual prompt
  in the terminal, where you answer as normal

While a request is pending the terminal is waiting on the hook, so if you're
already in that terminal click **Terminal** (or just wait – after 300 s the
prompt appears there anyway).

## Project layout

```
duonotch/
├── Package.swift                 Swift package: app, hook helper, shared module
├── Makefile                      build / bundle / run / install
├── Resources/Info.plist          LSUIElement app (menu bar only, no Dock icon)
└── Sources/
    ├── DuoNotchShared/           wire protocol shared by app and hook
    │   ├── HookWire.swift        port, token file, CLAUDE_CONFIG_DIR resolution
    │   ├── HookMessages.swift    HookPayload / HookEnvelope / HookReply
    │   └── JSONValue.swift       loosely typed JSON for tool_input
    ├── duonotch-hook/main.swift  the hook helper Claude Code runs
    └── DuoNotch/
        ├── App/                  @main, menu bar item, AppState (all state)
        ├── Accounts/             config-dir discovery, keychain / file credentials
        ├── Usage/                usage endpoint client and reading model
        ├── Sessions/             hook server, session model, settings.json installer
        ├── Notch/                NSPanel controller, geometry, SwiftUI views
        ├── Settings/             Settings window
        └── Support/              demo data
```

Design notes:

- The notch is a borderless, non-activating `NSPanel` one level above the
  menu bar, so it can cover the hardware notch. `NotchGeometry` measures the
  camera housing with `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`
  and `safeAreaInsets`; on other screens it draws a 32 pt fake notch.
- The panel is only as big as the drawn shape. It grows before the SwiftUI
  expansion animation and shrinks after the collapse animation, so it never
  blocks clicks on the menu bar.
- Hover is detected by polling `NSEvent.mouseLocation` against the shape's
  rectangle, which works even though the app is never the active app.
- `AppState` is a single `@MainActor` observable object. Everything the notch,
  the menu bar item and Settings show comes from it.

## Logs and troubleshooting

- "No Claude Code login found" – run `claude` once for that config directory,
  then **Refresh usage now**. If you use a custom directory, check the keychain
  item name as described above.
- "Token rejected" – the stored token was revoked; run `claude` for that login.
- "hooks not installed" in the expanded panel – Settings → Accounts →
  **Install hooks**, then restart `claude`.
- Approvals never appear – check Settings → Behaviour → Hook server says
  *listening*, and that the hook binary path shown there exists. Run
  `claude --debug` and look for the `PermissionRequest` hook output.
- Sessions stick around – a session whose `claude` process has exited is
  marked done on the next 30 s housekeeping pass and dropped after an hour.

## Roadmap

- Click a session row to raise its terminal window
- Per-account alerts at 80 % / 100 %
- Menu bar text styling, multiple screens, choose which screen hosts the notch
- Launch-at-login toggle is wired but only works from a bundle in /Applications

## License

MIT.
