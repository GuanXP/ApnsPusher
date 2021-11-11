//
//  JWTTimestamp.swift
//  ApnsPusher
//
//  Created by Xiaopeng.Guan on 2021/11/11.
//

import Foundation

class JWTTimestamp {
    private var updated = Date()
    
    func expired() -> Bool {
        // more than 1 hour means expired
        Date().timeIntervalSince(updated) > 40 * 60
    }
    
    func get() -> Int64 {
        if expired() {
            updated = Date()
        }
        return Int64(updated.timeIntervalSince1970)
    }
}
