import Foundation
import Network
import DuoNotchShared

// duonotch-hook
//
// Claude Code runs this for the hook events DuoNotch registers
// (SessionStart, UserPromptSubmit, Stop, SessionEnd, Notification,
// PermissionRequest). It reads the hook JSON from stdin, forwards it to the
// running app over localhost and exits. For PermissionRequest it waits for
// the decision made in the notch and prints it in Claude Code's hook output
// format. If the app is not running it exits silently so Claude Code
// behaves exactly as if no hook were installed.

private func emitPermissionDecision(_ reply: HookReply) {
    guard let behavior = reply.behavior, behavior == "allow" || behavior == "deny" else { return }
    var decision: [String: Any] = ["behavior": behavior]
    if behavior == "deny" {
        decision["message"] = reply.message ?? "Denied from DuoNotch"
    }
    let output: [String: Any] = [
        "hookSpecificOutput": [
            "hookEventName": "PermissionRequest",
            "decision": decision,
        ],
    ]
    if let data = try? JSONSerialization.data(withJSONObject: output),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

private enum HookClient {
    /// Sends one JSON line and waits (up to `timeout`) for one JSON line back.
    static func send(_ body: Data, timeout: TimeInterval) -> HookReply? {
        let connection = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: HookWire.port)!,
            using: .tcp
        )
        let done = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "duonotch.hook.client")
        var result: HookReply?
        var buffer = Data()
        var finished = false

        func finish(_ reply: HookReply?) {
            if finished { return }
            finished = true
            result = reply
            done.signal()
        }

        func readLoop() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data { buffer.append(data) }
                if let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[buffer.startIndex..<newline])
                    finish(try? JSONDecoder().decode(HookReply.self, from: line))
                    return
                }
                if error != nil || isComplete {
                    finish(nil)
                    return
                }
                readLoop()
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                var framed = body
                framed.append(0x0A)
                connection.send(content: framed, completion: .contentProcessed { error in
                    if error != nil { finish(nil) } else { readLoop() }
                })
            case .failed, .cancelled, .waiting:
                // .waiting is what we get when nothing is listening (ECONNREFUSED).
                finish(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
        _ = done.wait(timeout: .now() + timeout)
        connection.cancel()
        return result
    }
}

let input = FileHandle.standardInput.readDataToEndOfFile()
guard !input.isEmpty,
      let payload = try? JSONDecoder().decode(HookPayload.self, from: input) else {
    exit(0)
}
// No token means the app has never been launched on this Mac: stay silent.
guard let token = HookWire.readToken() else { exit(0) }

let configDir = HookWire.resolveConfigDir(ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"])
let envelope = HookEnvelope(token: token, configDir: configDir, claudePid: getppid(), payload: payload)
let isPermissionRequest = payload.hook_event_name == "PermissionRequest"

// Claude Code's hook timeout for PermissionRequest is set by the app's
// installer (see HookInstaller). Stay comfortably under it.
let timeout: TimeInterval = isPermissionRequest ? 280 : 3

guard let line = try? JSONEncoder().encode(envelope) else { exit(0) }
let reply = HookClient.send(line, timeout: timeout)
if isPermissionRequest, let reply {
    emitPermissionDecision(reply)
}
exit(0)
