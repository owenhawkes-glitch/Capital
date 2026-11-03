import Foundation
import Network
import DuoNotchShared

/// Loopback TCP listener that receives one JSON envelope per connection
/// from `duonotch-hook` and answers with one JSON reply line.
final class HookServer {
    typealias ReplyHandler = (HookReply) -> Void

    /// Called on an arbitrary queue; hop to the main actor before touching state.
    var onEnvelope: ((HookEnvelope, @escaping ReplyHandler) -> Void)?
    var onStatus: ((String) -> Void)?

    private let token: String
    private let queue = DispatchQueue(label: "duonotch.hook.server")
    private var listener: NWListener?

    init(token: String) {
        self.token = token
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: .ipv4(.loopback),
                port: NWEndpoint.Port(rawValue: HookWire.port)!
            )
            let listener = try NWListener(using: params)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.onStatus?("listening on 127.0.0.1:\(HookWire.port)")
                case .failed(let error): self?.onStatus?("failed: \(error.localizedDescription)")
                case .cancelled: self?.onStatus?("stopped")
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            onStatus?("could not listen: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Private

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveLine(connection, buffer: Data()) { [weak self] line in
            guard let self, let line,
                  let envelope = try? JSONDecoder().decode(HookEnvelope.self, from: line),
                  envelope.token == self.token else {
                connection.cancel()
                return
            }
            let reply: ReplyHandler = { reply in
                var data = (try? JSONEncoder().encode(reply)) ?? Data("{}".utf8)
                data.append(0x0A)
                connection.send(content: data, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
            if let onEnvelope = self.onEnvelope {
                onEnvelope(envelope, reply)
            } else {
                reply(HookReply())
            }
        }
    }

    private func receiveLine(_ connection: NWConnection, buffer: Data, handler: @escaping (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            var accumulated = buffer
            if let data { accumulated.append(data) }
            if let newline = accumulated.firstIndex(of: 0x0A) {
                handler(Data(accumulated[accumulated.startIndex..<newline]))
                return
            }
            if error != nil || isComplete || accumulated.count > (1 << 20) {
                handler(nil)
                return
            }
            self?.receiveLine(connection, buffer: accumulated, handler: handler)
        }
    }
}
