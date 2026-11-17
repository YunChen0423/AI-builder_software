import Foundation
import Network

/// Explicitly enabled loopback bridge; one local adapter, bounded lines, no hardware auto-discovery.
final class HardwareBridge {
    private var listener: NWListener?
    private var connection: NWConnection?
    private var pending = Data()
    private var lastSequence: Int64 = -1
    private var sending = false
    private var generation = 0
    var onContact: ((Bool) -> Void)?
    var onDisconnect: (() -> Void)?
    var onStatus: ((String) -> Void)?
    var enabled: Bool { listener != nil }
    func start() {
        stop()
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 18457)
            let next = try NWListener(using: parameters)
            listener = next
            let token = generation
            next.stateUpdateHandler = { [weak self] state in
                guard let self, token == self.generation else { return }
                switch state {
                case .ready: self.onStatus?("本机接口已开启 · 127.0.0.1:18457 · 等待适配器")
                case .failed(let error): self.onStatus?("接口无法启动：\(error.localizedDescription)"); self.stop()
                default: break
                }
            }
            next.newConnectionHandler = { [weak self] client in
                guard let self, token == self.generation, self.connection == nil else { client.cancel(); return }
                self.connection = client; self.pending.removeAll(); self.lastSequence = -1; self.sending = false
                client.stateUpdateHandler = { [weak self, weak client] state in
                    guard let self, let client, self.connection === client else { return }
                    switch state {
                    case .ready: self.onStatus?("本机适配器已连接 · 等待接触信号"); self.receive(client)
                    case .failed, .cancelled: self.drop(client)
                    default: break
                    }
                }
                client.start(queue: .main)
            }
            next.start(queue: .main)
        } catch { onStatus?("接口无法启动：\(error.localizedDescription)") }
    }
    func stop() {
        generation += 1
        listener?.cancel(); listener = nil
        connection?.cancel(); connection = nil; pending.removeAll(); sending = false
        onDisconnect?()
    }
    private func drop(_ client: NWConnection) {
        guard connection === client else { return }
        connection = nil; client.cancel(); pending.removeAll(); sending = false; onDisconnect?()
        onStatus?("适配器已断开 · 接触信号已失效")
    }
    private func receive(_ client: NWConnection) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak client] data, _, complete, error in
            guard let self, let client, self.connection === client else { return }
            if let data { self.pending.append(data) }
            while let newline = self.pending.firstIndex(of: 10) {
                let line = self.pending.prefix(upTo: newline)
                guard line.count <= 2048 else { self.drop(client); return }
                self.pending.removeSubrange(...newline)
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   object["type"] as? String == "contact", object["version"] as? Int == 1,
                   let number = object["pressed"] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID(),
                   let seq = object["sequence"] as? Int64, seq > self.lastSequence {
                    self.lastSequence = seq; self.onContact?(number.boolValue)
                }
            }
            if self.pending.count > 2048 || complete || error != nil { self.drop(client); return }
            self.receive(client)
        }
    }
    func send(_ frame: AirFrame) {
        guard let client = connection, !sending, let bytes = try? JSONEncoder().encode(frame) else { return }
        sending = true
        client.send(content: bytes + Data([10]), completion: .contentProcessed { [weak self, weak client] error in
            guard let self, let client, self.connection === client else { return }
            self.sending = false
            if error != nil { self.drop(client) }
        })
    }
}
