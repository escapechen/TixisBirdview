//
//  MqttClient.swift
//  TixisBirdview
//
//  A deliberately small MQTT 3.1.1 subscriber for Frigate event delivery.
//  It uses Network.framework, preserving macOS TLS and hostname validation.
//

import Foundation
import Network

final class MqttClient {
    struct Configuration: Equatable {
        let host: String
        let port: UInt16
        let useTLS: Bool
        let username: String
        let password: String
        let topicPrefix: String
    }

    typealias StateHandler = (_ isConnected: Bool, _ detail: String) -> Void
    typealias MessageHandler = (_ topic: String, _ payload: Data) -> Void

    private static let maximumPacketSize = 1024 * 1024
    private static let keepAliveSeconds: UInt16 = 30
    private static let connectTimeout: TimeInterval = 15

    private let queue = DispatchQueue(label: "org.tixisbirdview.mqtt")
    private let onStateChange: StateHandler
    private let onMessage: MessageHandler

    private var configuration: Configuration?
    private var connection: NWConnection?
    private var receiveBuffer = [UInt8]()
    private var isRunning = false
    private var isConnected = false
    private var status = "MQTT delivery is stopped."
    private var connectPacketSent = false
    private var awaitingPingResponse = false
    private var nextPacketIdentifier: UInt16 = 1
    private var subscriptionPacketIdentifier: UInt16 = 0
    private var reconnectDelaySeconds: TimeInterval = 1
    private var reconnectWorkItem: DispatchWorkItem?
    private var connectTimeoutWorkItem: DispatchWorkItem?
    private var pingWorkItem: DispatchWorkItem?

    init(onStateChange: @escaping StateHandler, onMessage: @escaping MessageHandler) {
        self.onStateChange = onStateChange
        self.onMessage = onMessage
    }

    deinit {
        stop()
    }

    func start(_ configuration: Configuration) {
        queue.async { [weak self] in
            guard let self else { return }
            let changed = self.configuration != configuration
            self.configuration = configuration
            self.isRunning = true
            self.reconnectDelaySeconds = 1
            if changed {
                self.disposeConnection()
            }
            self.beginConnection()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.cancelTimers()
            self.receiveBuffer.removeAll(keepingCapacity: false)
            self.awaitingPingResponse = false
            self.disposeConnection()
            self.setStatus(isConnected: false, detail: "MQTT delivery is stopped.")
        }
    }

    private func beginConnection() {
        guard isRunning, let configuration else { return }
        guard !configuration.host.isEmpty,
              let port = NWEndpoint.Port(rawValue: configuration.port) else {
            setStatus(isConnected: false, detail: "Enter an MQTT broker host before enabling MQTT delivery.")
            return
        }

        cancelTimers()
        disposeConnection()
        receiveBuffer.removeAll(keepingCapacity: true)
        connectPacketSent = false
        awaitingPingResponse = false
        setStatus(isConnected: false, detail: "Connecting to MQTT…")

        let parameters: NWParameters
        if configuration.useTLS {
            // Network.framework performs normal trust-chain, hostname, and
            // expiry checks. Do not install a permissive verify block here.
            parameters = NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
        } else {
            parameters = .tcp
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(configuration.host),
            port: port,
            using: parameters
        )
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            self.queue.async {
                guard self.connection === connection, self.isRunning else { return }
                switch state {
                case .ready:
                    self.sendConnectPacket()
                    self.receiveNext(from: connection)
                case .waiting(_), .failed(_):
                    self.reportFailure("Could not reach the MQTT broker.")
                case .cancelled:
                    self.reportFailure("MQTT broker connection closed.")
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)

        let timeout = DispatchWorkItem { [weak self, weak connection] in
            guard let self, let connection, self.connection === connection else { return }
            self.reportFailure("MQTT broker did not complete the connection in time.")
        }
        connectTimeoutWorkItem = timeout
        queue.asyncAfter(deadline: .now() + Self.connectTimeout, execute: timeout)
    }

    private func receiveNext(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            self.queue.async {
                guard self.connection === connection, self.isRunning else { return }
                if let data, !data.isEmpty {
                    self.receiveBuffer.append(contentsOf: data)
                    if self.receiveBuffer.count > Self.maximumPacketSize + 5 {
                        self.reportFailure("MQTT broker sent an unexpectedly large packet.")
                        return
                    }
                    guard self.processIncomingData() else { return }
                }
                if error != nil || isComplete {
                    self.reportFailure("MQTT broker connection closed.")
                    return
                }
                self.receiveNext(from: connection)
            }
        }
    }

    private func processIncomingData() -> Bool {
        while receiveBuffer.count >= 2 {
            var offset = 1
            var remainingLength = 0
            var multiplier = 1
            var complete = false
            for _ in 0..<4 {
                guard offset < receiveBuffer.count else { return true }
                let byte = receiveBuffer[offset]
                offset += 1
                remainingLength += Int(byte & 0x7f) * multiplier
                if byte & 0x80 == 0 {
                    complete = true
                    break
                }
                multiplier *= 128
            }
            guard complete, remainingLength <= Self.maximumPacketSize else {
                reportFailure("MQTT broker sent an invalid packet.")
                return false
            }
            guard receiveBuffer.count - offset >= remainingLength else { return true }
            let header = receiveBuffer[0]
            let payload = Array(receiveBuffer[offset..<(offset + remainingLength)])
            receiveBuffer.removeFirst(offset + remainingLength)
            guard processPacket(header: header, payload: payload) else { return false }
        }
        return true
    }

    private func processPacket(header: UInt8, payload: [UInt8]) -> Bool {
        switch header >> 4 {
        case 2: // CONNACK
            guard payload.count == 2, payload[0] == 0 else {
                reportFailure("MQTT broker sent an invalid connection response.")
                return false
            }
            guard payload[1] == 0 else {
                reportFailure(connectionRefusalText(payload[1]))
                return false
            }
            sendSubscriptions()
            return true
        case 3: // PUBLISH
            return handlePublish(header: header, payload: payload)
        case 9: // SUBACK
            guard payload.count >= 4,
                  payload[0] == UInt8(subscriptionPacketIdentifier >> 8),
                  payload[1] == UInt8(subscriptionPacketIdentifier & 0xff),
                  !payload.dropFirst(2).contains(0x80) else {
                reportFailure("MQTT broker did not authorize the Frigate event topics.")
                return false
            }
            connectTimeoutWorkItem?.cancel()
            reconnectDelaySeconds = 1
            setStatus(isConnected: true, detail: "MQTT delivery connected.")
            schedulePing()
            return true
        case 13: // PINGRESP
            awaitingPingResponse = false
            return true
        default:
            return true
        }
    }

    private func sendConnectPacket() {
        guard !connectPacketSent, let configuration else { return }
        var payload = encodeString("MQTT")
        payload.append(4) // MQTT 3.1.1
        var flags: UInt8 = 0x02 // clean session
        if !configuration.username.isEmpty { flags |= 0x80 }
        if !configuration.password.isEmpty { flags |= 0x40 }
        payload.append(flags)
        payload.append(UInt8(Self.keepAliveSeconds >> 8))
        payload.append(UInt8(Self.keepAliveSeconds & 0xff))
        payload += encodeString("tixisbirdview-\(UUID().uuidString)")
        if !configuration.username.isEmpty { payload += encodeString(configuration.username) }
        if !configuration.password.isEmpty { payload += encodeString(configuration.password) }
        guard !payload.isEmpty else {
            reportFailure("MQTT connection details are too large.")
            return
        }
        connectPacketSent = true
        writePacket(header: 0x10, payload: payload)
    }

    private func sendSubscriptions() {
        guard let configuration else { return }
        let prefix = configuration.topicPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !prefix.isEmpty else {
            reportFailure("Enter a concrete MQTT topic prefix, such as frigate.")
            return
        }
        subscriptionPacketIdentifier = nextPacketIdentifier
        nextPacketIdentifier &+= 1
        if nextPacketIdentifier == 0 { nextPacketIdentifier = 1 }

        var payload: [UInt8] = [
            UInt8(subscriptionPacketIdentifier >> 8),
            UInt8(subscriptionPacketIdentifier & 0xff),
        ]
        for topic in ["\(prefix)/events", "\(prefix)/reviews"] {
            let encodedTopic = encodeString(topic)
            guard !encodedTopic.isEmpty else {
                reportFailure("MQTT topic is too large.")
                return
            }
            payload += encodedTopic
            payload.append(0) // requested QoS 0
        }
        writePacket(header: 0x82, payload: payload)
    }

    private func handlePublish(header: UInt8, payload: [UInt8]) -> Bool {
        let qualityOfService = (header >> 1) & 0x03
        guard qualityOfService != 2 else {
            reportFailure("MQTT broker used unsupported QoS 2 delivery.")
            return false
        }
        var offset = 0
        guard let topic = readString(payload, offset: &offset) else {
            reportFailure("MQTT broker sent an invalid event message.")
            return false
        }
        var packetIdentifier: UInt16 = 0
        if qualityOfService == 1 {
            guard offset + 2 <= payload.count else {
                reportFailure("MQTT broker sent an invalid event message.")
                return false
            }
            packetIdentifier = UInt16(payload[offset]) << 8 | UInt16(payload[offset + 1])
            offset += 2
        }
        emitMessage(topic: topic, payload: Data(payload.dropFirst(offset)))
        if qualityOfService == 1 {
            writePacket(
                header: 0x40,
                payload: [UInt8(packetIdentifier >> 8), UInt8(packetIdentifier & 0xff)]
            )
        }
        return true
    }

    private func writePacket(header: UInt8, payload: [UInt8]) {
        guard payload.count <= Self.maximumPacketSize, let connection else {
            reportFailure("MQTT packet is too large.")
            return
        }
        var packet = [header]
        packet += encodeRemainingLength(payload.count)
        packet += payload
        connection.send(content: Data(packet), completion: .contentProcessed { [weak self, weak connection] error in
            guard let self, let connection else { return }
            self.queue.async {
                guard self.connection === connection, self.isRunning else { return }
                if error != nil {
                    self.reportFailure("Could not send data to the MQTT broker.")
                }
            }
        })
    }

    private func schedulePing() {
        pingWorkItem?.cancel()
        let ping = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, self.isConnected else { return }
            if self.awaitingPingResponse {
                self.reportFailure("MQTT broker did not answer its keep-alive check.")
                return
            }
            self.awaitingPingResponse = true
            self.writePacket(header: 0xc0, payload: [])
            self.schedulePing()
        }
        pingWorkItem = ping
        queue.asyncAfter(deadline: .now() + .seconds(Int(Self.keepAliveSeconds / 2)), execute: ping)
    }

    private func reportFailure(_ detail: String) {
        connectTimeoutWorkItem?.cancel()
        pingWorkItem?.cancel()
        awaitingPingResponse = false
        setStatus(isConnected: false, detail: detail)
        disposeConnection()
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard isRunning, reconnectWorkItem == nil else { return }
        let delay = reconnectDelaySeconds
        reconnectDelaySeconds = min(reconnectDelaySeconds * 2, 30)
        let reconnect = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWorkItem = nil
            self.beginConnection()
        }
        reconnectWorkItem = reconnect
        queue.asyncAfter(deadline: .now() + delay, execute: reconnect)
    }

    private func disposeConnection() {
        guard let connection else { return }
        self.connection = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    private func cancelTimers() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        connectTimeoutWorkItem?.cancel()
        connectTimeoutWorkItem = nil
        pingWorkItem?.cancel()
        pingWorkItem = nil
    }

    private func setStatus(isConnected: Bool, detail: String) {
        guard self.isConnected != isConnected || status != detail else { return }
        self.isConnected = isConnected
        status = detail
        DispatchQueue.main.async { [onStateChange] in
            onStateChange(isConnected, detail)
        }
    }

    private func emitMessage(topic: String, payload: Data) {
        DispatchQueue.main.async { [onMessage] in
            onMessage(topic, payload)
        }
    }

    private func encodeString(_ value: String) -> [UInt8] {
        let bytes = Array(value.utf8)
        guard bytes.count <= Int(UInt16.max) else { return [] }
        return [UInt8(bytes.count >> 8), UInt8(bytes.count & 0xff)] + bytes
    }

    private func encodeRemainingLength(_ value: Int) -> [UInt8] {
        var remaining = value
        var result = [UInt8]()
        repeat {
            var byte = UInt8(remaining % 128)
            remaining /= 128
            if remaining > 0 { byte |= 0x80 }
            result.append(byte)
        } while remaining > 0
        return result
    }

    private func readString(_ bytes: [UInt8], offset: inout Int) -> String? {
        guard offset + 2 <= bytes.count else { return nil }
        let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        offset += 2
        guard offset + length <= bytes.count else { return nil }
        let value = String(bytes: bytes[offset..<(offset + length)], encoding: .utf8)
        offset += length
        return value
    }

    private func connectionRefusalText(_ code: UInt8) -> String {
        switch code {
        case 1: "MQTT broker rejected the protocol version."
        case 2: "MQTT broker rejected the client identifier."
        case 3: "MQTT broker is unavailable."
        case 4: "MQTT broker rejected the username or password."
        case 5: "MQTT broker did not authorize this connection."
        default: "MQTT broker rejected the connection."
        }
    }
}
