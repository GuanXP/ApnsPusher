//
//  JWTEncoder.swift
//  ApnsPusher
//
//  Created by Xiaopeng.Guan on 2021/11/3.
//

import Foundation
import JWTKit

class JWTEncoder {
    private let key: String
    private let keyID: String
    private let teamID: String
    
    private init(privateKey: String, keyID: String, teamID: String) {
        self.key = privateKey
        self.keyID = keyID
        self.teamID = teamID
    }
    
    static func bearer(privateKey: String, keyID: String, teamID: String) -> String {
        JWTEncoder(privateKey: privateKey,
                   keyID: keyID,
                   teamID: teamID).signature()
    }
    
    private func signature() -> String {
        do {
            let signer = try JWTSigner.es256(key: .private(pem: self.key))
            return try signer.sign(Payload(teamID: self.teamID),
                                   kid: JWKIdentifier(string: "\(keyID)"))
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
    var timestamp: Int64 = Int64(Date().timeIntervalSince1970)
    
    func verify(using signer: JWTSigner) throws {
        
    }
}
