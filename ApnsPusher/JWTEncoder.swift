//
//  JWTEncoder.swift
//  ApnsPusher
//
//  Created by Xiaopeng.Guan on 2021/11/3.
//

import Foundation
import JWTKit

class JWTEncoder {
    static func sign(key: String, keyID: String, teamID: String, timestamp: Int64) -> String {
        do {
            let signer = try JWTSigner.es256(key: .private(pem: key))
            let payload = Payload(teamID: teamID, timestamp: timestamp)
            return try signer.sign(payload, kid: JWKIdentifier(string: "\(keyID)"))
        } catch {
            return ""
        }
    }
}

private struct Payload: JWTPayload {
    enum CodingKeys: String, CodingKey {
        case teamID = "iss"
        case timestamp = "iat"
    }
    
    var teamID: String
    var timestamp: Int64
    
    func verify(using signer: JWTSigner) throws {
    }
}
