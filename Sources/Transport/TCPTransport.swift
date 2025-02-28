//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  HTTPTransport.swift
//  Starscream
//
//  Created by Dalton Cherry on 1/23/19.
//  Copyright © 2019 Vluxe. All rights reserved.
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
import Network

public enum TCPTransportError: Error {
    case invalidRequest
}

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
public class TCPTransport: Transport {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.vluxe.starscream.networkstream", attributes: [])
    private weak var delegate: TransportEventClient?
    private var isRunning = false
    private var isTLS = false

    public var usingTLS: Bool { isTLS }

    public init(connection: NWConnection) {
        self.connection = connection
        start()
    }

    public init() {
        // normal connection, will use the "connect" method below
    }

    public func connect(url: URL, timeout: Double = 10, certificatePinning: CertificatePinning? = nil) {
        guard let parts = url.getParts() else {
            delegate?.connectionChanged(state: .failed(TCPTransportError.invalidRequest))
            return
        }
        isTLS = parts.isTLS
        let options = NWProtocolTCP.Options()
        options.connectionTimeout = Int(timeout.rounded(.up))

        let tlsOptions = isTLS ? NWProtocolTLS.Options() : nil
        if let tlsOpts = tlsOptions {
            typealias VerifierClosure = (sec_protocol_metadata_t, sec_trust_t, @escaping sec_protocol_verify_complete_t) -> Void
            let verifier: VerifierClosure = { _, trust, completion in
                let trust = sec_trust_copy_ref(trust).takeRetainedValue()
                guard let pinner = certificatePinning else { return completion(true) }

                pinner.evaluateTrust(trust: trust, domain: parts.host) { state in
                    switch state {
                        case .success:
                            completion(true)
                        case .failed(_):
                            completion(false)
                    }
                }
            }
            sec_protocol_options_set_verify_block(tlsOpts.securityProtocolOptions, verifier, queue)
        }
        let parameters = NWParameters(tls: tlsOptions, tcp: options)
        let conn = NWConnection(
            host: NWEndpoint.Host.name(parts.host, nil), port: NWEndpoint.Port(rawValue: UInt16(parts.port))!, using: parameters
        )
        connection = conn
        start()
    }

    public func disconnect() {
        isRunning = false
        connection?.cancel()
    }

    public func register(delegate: TransportEventClient) {
        self.delegate = delegate
    }

    public func write(data: Data, completion: @escaping (Error?) -> Void) {
        connection?.send(content: data, completion: .contentProcessed { error in
            completion(error)
        })
    }

    private func start() {
        guard let conn = connection else {
            return
        }
        conn.stateUpdateHandler = { [weak self] newState in
            switch newState {
                case .ready:
                    self?.delegate?.connectionChanged(state: .connected)
                case .waiting:
                    self?.delegate?.connectionChanged(state: .waiting)
                case .cancelled:
                    self?.delegate?.connectionChanged(state: .cancelled)
                case .failed(let error):
                    self?.delegate?.connectionChanged(state: .failed(error))
                case .setup, .preparing:
                    break
                @unknown default:
                    break
            }
        }

        conn.viabilityUpdateHandler = { [weak self] isViable in
            self?.delegate?.connectionChanged(state: .viability(isViable))
        }

        conn.betterPathUpdateHandler = { [weak self] isBetter in
            self?.delegate?.connectionChanged(state: .shouldReconnect(isBetter))
        }

        conn.start(queue: queue)
        isRunning = true
        readLoop()
    }

    // readLoop keeps reading from the connection to get the latest content
    private func readLoop() {
        if !isRunning {
            return
        }
        connection?.receive(minimumIncompleteLength: 2, maximumLength: 4096) { [weak self] data, context, isComplete, error in
            guard let transport = self else { return }

            if let data = data {
                transport.delegate?.connectionChanged(state: .receive(data))
            }

            // Refer to https://developer.apple.com/documentation/network/implementing_netcat_with_network_framework
            if let context = context, context.isFinal, isComplete {
                return
            }

            if error == nil {
                transport.readLoop()
            }

        }
    }
}
