//
//  JWTCache.swift
//  ApnsPusher
//
//  Created by Xiaopeng.Guan on 2021/11/11.
//

import Foundation

///
/// To avoid TooManyProviderTokenUpdate error, we need cache the signatures
/// until they exipres
///
class JWTCache {
    private var key: String = ""
    private var keyID: String = ""
    private var teamID: String = ""
    
    private var signature: String = ""
    private let timestamp = JWTTimestamp()
    private let lock = NSRecursiveLock()
    
    func update(key: String, keyID: String, teamID: String) {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        
        guard key != self.key || keyID != self.keyID || teamID != self.teamID else {
            return
        }
        self.key = key
        self.keyID = keyID
        self.teamID = teamID
        signature = ""
    }
    
    func getSignature() -> String {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        
        if signature.isEmpty || timestamp.expired() {
            signature = JWTEncoder.sign(key: key, keyID: keyID, teamID: teamID, timestamp: timestamp.get())
        }
        return signature
    }
}
