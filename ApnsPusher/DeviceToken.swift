//
//  DeviceToken.swift
//  ApnsPusher
//
//  Created by Xiaopeng.Guan on 2021/11/3.
//

import Foundation

class DeviceToken: ObservableObject {
    @Published var token: String
    @Published var selected = true
    private var pushed: Bool? = nil
    @Published var pushStateImageName: String = "paperplane.circle"
    
    init(token: String) {
        self.token = token
    }
    
    func toJSON() -> String {
        let dict = [
            "token":token,
            "selected": selected
        ] as [String : Any]
        guard let json = try? JSONSerialization.data(withJSONObject: dict) else {
            return ""
        }
        return String(bytes: json, encoding: .utf8) ?? ""
    }
    
    static func fromJSON(json: String) -> DeviceToken {
        let deviceToken = DeviceToken(token: "")
        guard let data = json.data(using: .utf8) else {
            return deviceToken
        }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String : Any] else {
            return deviceToken
        }
        deviceToken.token = dict["token"] as? String ?? ""
        deviceToken.selected = dict["selected"] as? Bool ?? false
        return deviceToken
    }
    
    func setPushed(pushed: Bool?) {
        DispatchQueue.main.async { [weak self] in
            self?.updatePushed(pushed: pushed)
        }
    }
    
    private func updatePushed(pushed: Bool?) {
        self.pushed = pushed
        if pushed == nil {
            self.pushStateImageName = "paperplane.circle"
        } else if pushed == true {
            self.pushStateImageName = "checkmark.circle.fill"
        } else {
            self.pushStateImageName = "exclamationmark.circle.fill"
        }
    }
}

