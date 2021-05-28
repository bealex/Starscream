//
// CryptoExtensions
// Starscream
//
// Created by Alex Babaev on 28 May 2021.
// Copyright © 2021 Alex Babaev. All rights reserved.
//

import Foundation
import CryptoKit

extension String {
    func sha1Base64() -> String {
        let data = data(using: .utf8)!
        return Data(Insecure.SHA1.hash(data: data)).base64EncodedString()
    }
}
