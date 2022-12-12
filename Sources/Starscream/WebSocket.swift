//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Websocket.swift
//  Starscream
//
//  Created by Dalton Cherry on 7/16/14.
//  Copyright (c) 2014-2019 Dalton Cherry.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
//////////////////////////////////////////////////////////////////////////////////////////////////

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ErrorType: Error {
    case compressionError
    case securityError
    case protocolError // There was an error parsing the WebSocket frames
    case serverError
}

public struct WSError: Error {
    public let type: ErrorType
    public let message: String
    public let code: UInt16

    public init(type: ErrorType, message: String, code: UInt16) {
        self.type = type
        self.message = message
        self.code = code
    }
}

public protocol WebSocketClient: AnyObject {
    func connect()
    func disconnect(closeCode: UInt16)
    func write(string: String, completion: (() -> Void)?)
    func write(stringData: Data, completion: (() -> Void)?)
    func write(data: Data, completion: (() -> Void)?)
    func write(ping: Data, completion: (() -> Void)?)
    func write(pong: Data, completion: (() -> Void)?)
}

// implements some of the base behaviors
extension WebSocketClient {
    public func write(string: String) {
        write(string: string, completion: nil)
    }

    public func write(data: Data) {
        write(data: data, completion: nil)
    }

    public func write(ping: Data) {
        write(ping: ping, completion: nil)
    }

    public func write(pong: Data) {
        write(pong: pong, completion: nil)
    }

    public func disconnect() {
        disconnect(closeCode: CloseCode.normal.rawValue)
    }
}

public enum WebSocketEvent {
    case connected([String: String])
    case disconnected(String, UInt16)
    case text(String)
    case binary(Data)
    case pong(Data?)
    case ping(Data?)
    case error(Error?)
    case viabilityChanged(Bool)
    case reconnectSuggested(Bool)
    case cancelled
}

public protocol WebSocketDelegate: AnyObject {
    func didReceive(event: WebSocketEvent, client: WebSocketClient)
}

open class WebSocket: WebSocketClient, EngineDelegate {
    private let engine: Engine
    public weak var delegate: WebSocketDelegate?
    public var onEvent: ((WebSocketEvent) -> Void)?

    public var request: URLRequest
    // Where the callback is executed. It defaults to the main UI thread queue.
    public var callbackQueue = DispatchQueue.main
    public var respondToPingWithPong: Bool {
        get {
            guard let engine = engine as? WSEngine else { return true }

            return engine.respondToPingWithPong
        }
        set {
            guard let engine = engine as? WSEngine else { return }

            engine.respondToPingWithPong = newValue
        }
    }

    public init(request: URLRequest, engine: Engine) {
        self.request = request
        self.engine = engine
    }

    public convenience init(
        request: URLRequest,
        certPinner: CertificatePinning? = FoundationSecurity(),
        compressionHandler: CompressionHandler? = nil,
        useCustomEngine: Bool = true
    ) {
        let engine: Engine
        if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *), !useCustomEngine {
            engine = NativeEngine()
        } else {
            engine = WSEngine(transport: TCPTransport(), certPinner: certPinner, compressionHandler: compressionHandler)
        }
        self.init(request: request, engine: engine)
    }

    public func connect() {
        engine.register(delegate: self)
        engine.start(request: request)
    }

    public func disconnect(closeCode: UInt16 = CloseCode.normal.rawValue) {
        engine.stop(closeCode: closeCode)
    }

    public func forceDisconnect() {
        engine.forceStop()
    }

    public func write(data: Data, completion: (() -> Void)?) {
         write(data: data, opcode: .binaryFrame, completion: completion)
    }

    public func write(string: String, completion: (() -> Void)?) {
        engine.write(string: string, completion: completion)
    }

    public func write(stringData: Data, completion: (() -> Void)?) {
        write(data: stringData, opcode: .textFrame, completion: completion)
    }

    public func write(ping: Data, completion: (() -> Void)?) {
        write(data: ping, opcode: .ping, completion: completion)
    }

    public func write(pong: Data, completion: (() -> Void)?) {
        write(data: pong, opcode: .pong, completion: completion)
    }

    private func write(data: Data, opcode: FrameOpCode, completion: (() -> Void)?) {
        engine.write(data: data, opcode: opcode, completion: completion)
    }

    // MARK: - EngineDelegate
    public func didReceive(event: WebSocketEvent) {
        callbackQueue.async { [weak self] in
            guard let webSocket = self else { return }

            webSocket.delegate?.didReceive(event: event, client: webSocket)
            webSocket.onEvent?(event)
        }
    }
}
