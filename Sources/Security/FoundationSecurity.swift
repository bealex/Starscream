//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  FoundationSecurity.swift
//  Starscream
//
//  Created by Dalton Cherry on 3/16/19.
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
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FoundationSecurityError: Error {
    case invalidRequest
}

public class FoundationSecurity {
    var allowSelfSigned = false

    public init(allowSelfSigned: Bool = false) {
        self.allowSelfSigned = allowSelfSigned
    }
}

extension FoundationSecurity: CertificatePinning {
    public func evaluateTrust(trust: SecTrust, domain: String?, completion: (PinningState) -> Void) {
        if allowSelfSigned {
            completion(.success)
            return
        }

        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, domain as NSString?))

        handleSecurityTrust(trust: trust, completion: completion)
    }

    private func handleSecurityTrust(trust: SecTrust, completion: (PinningState) -> Void) {
        if #available(iOS 12.0, OSX 10.14, watchOS 5.0, tvOS 12.0, *) {
            var error: CFError?
            if SecTrustEvaluateWithError(trust, &error) {
                completion(.success)
            } else {
                completion(.failed(error))
            }
        } else {
            var result: SecTrustResultType = .unspecified
            SecTrustEvaluate(trust, &result)
            if result == .unspecified || result == .proceed {
                completion(.success)
            } else {
                let error = CFErrorCreate(kCFAllocatorDefault, "FoundationSecurityError" as NSString?, Int(result.rawValue), nil)
                completion(.failed(error))
            }
        }
    }
}

extension FoundationSecurity: HeaderValidator {
    public func validate(headers: [String: String], key: String) -> Error? {
        if let acceptKey = headers[HTTPWSHeader.acceptName] {
            let data = "\(key)258EAFA5-E914-47DA-95CA-C5AB0DC85B11".data(using: .utf8)!
            let sha = Data(Insecure.SHA1.hash(data: data)).base64EncodedString()
            if sha != acceptKey {
                return WSError(type: .securityError, message: "accept header doesn't match", code: SecurityErrorCode.acceptFailed.rawValue)
            }
        }
        return nil
    }
}
